// Agent runtime with ReAct loop — tool-calling / multi-step planning.
//
// Threading model
// ---------------
// ReAct loop runs on the main isolate. Each LLM generation call spawns a
// worker isolate via MnnLlmSession.chatStream (same as plain chat). Tool
// execution happens on the main isolate between generation rounds. This
// keeps the UI responsive while allowing multi-turn reasoning.
//
// Tool-call format
// ----------------
// The model is instructed to emit tool calls in a simple XML-like tag:
//   <tool_call>
//   {"name": "calculator", "arguments": {"expression": "2+2"}}
//   </tool_call>
// This format is easy for small models (0.6B–4B) to produce reliably and
// can be parsed from a streamed buffer without look-ahead.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mnn_llm/mnn_llm.dart';

import 'agent_prompt.dart';

/// A JSON-Schema fragment describing a tool's parameters.
typedef ToolSchema = Map<String, dynamic>;

/// Result of executing a tool.
class ToolResult {
  const ToolResult.ok(this.output) : isError = false;
  const ToolResult.error(this.output) : isError = true;

  final String output;
  final bool isError;

  @override
  String toString() => isError ? 'ToolError($output)' : 'ToolResult($output)';
}

/// Error codes for categorizing tool execution failures.
enum ToolErrorCode {
  timeout,
  permission,
  notFound,
  network,
  invalidArgument,
  unsupported,
  unknown,
}

/// Build a standardized error message with optional fix advice.
String toolError(String reason, {ToolErrorCode code = ToolErrorCode.unknown, String? advice}) {
  final codeTag = switch (code) {
    ToolErrorCode.timeout => '⏱',
    ToolErrorCode.permission => '🔒',
    ToolErrorCode.notFound => '🔍',
    ToolErrorCode.network => '🌐',
    ToolErrorCode.invalidArgument => '⚠️',
    ToolErrorCode.unsupported => '🚫',
    ToolErrorCode.unknown => '❌',
  };
  final buf = StringBuffer('$codeTag $reason');
  if (advice != null && advice.isNotEmpty) {
    buf.write('\n➡ 建议: $advice');
  }
  return buf.toString();
}

/// A callable tool the agent can invoke.
class Tool {
  const Tool({
    required this.name,
    required this.description,
    required this.schema,
    required this.handler,
  });

  final String name;
  final String description;
  final ToolSchema schema;
  final Future<ToolResult> Function(Map<String, dynamic> args) handler;
}

// ---- Agent events --------------------------------------------------------

abstract class AgentEvent {}

class AgentTokenEvent extends AgentEvent {
  AgentTokenEvent(this.chunk);
  final String chunk;
}

class AgentToolCallEvent extends AgentEvent {
  AgentToolCallEvent({required this.toolName, required this.arguments});
  final String toolName;
  final Map<String, dynamic> arguments;
}

class ToolExecutionEvent extends AgentEvent {
  ToolExecutionEvent({required this.toolName, required this.result});
  final String toolName;
  final ToolResult result;
}

class AgentDoneEvent extends AgentEvent {
  AgentDoneEvent(this.answer, {this.steps = 0});
  final String answer;
  final int steps;
}

class AgentErrorEvent extends AgentEvent {
  AgentErrorEvent(this.message);
  final String message;
}

// ---- Agent runtime interface --------------------------------------------

abstract class AgentRuntime {
  void registerTool(Tool tool);
  void unregisterTool(String name);
  Stream<AgentEvent> run(String userInput);
  Future<void> dispose();

  /// 执行一个已注册的工具，返回结果 (供 H13 execute_plan 等 meta 工具反向调用)。
  /// 未找到工具时返回 ToolResult.error。
  Future<ToolResult> executeTool(String name, Map<String, dynamic> args);
}

// ---- Tool-call parser ----------------------------------------------------

const _kToolCallOpen = '<tool_call>';
const _kToolCallClose = '</tool_call>';

/// Tries to extract a tool call from [buffer].
/// Returns (jsonString, remainder) if a complete tool_call block is found,
/// otherwise returns (null, buffer).
({String? json, String remainder}) _tryParseToolCall(String buffer) {
  final openIdx = buffer.indexOf(_kToolCallOpen);
  if (openIdx < 0) return (json: null, remainder: buffer);

  final closeIdx = buffer.indexOf(_kToolCallClose, openIdx);
  if (closeIdx < 0) {
    // Tag opened but not closed yet — keep buffering.
    // Emit text before the tag so the user sees partial output.
    return (json: null, remainder: buffer.substring(openIdx));
  }

  final jsonStr = buffer
      .substring(openIdx + _kToolCallOpen.length, closeIdx)
      .trim();
  final remainder = buffer.substring(closeIdx + _kToolCallClose.length);
  return (json: jsonStr, remainder: remainder);
}

/// Parses the tool-call JSON into (name, arguments).
({String name, Map<String, dynamic> args})? _parseToolJson(String jsonStr) {
  try {
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map) return null;
    final name = decoded['name'];
    if (name is! String) return null;
    final args = decoded['arguments'];
    return (
      name: name,
      args: args is Map ? Map<String, dynamic>.from(args) : <String, dynamic>{},
    );
  } catch (_) {
    return null;
  }
}

// ---- LocalMnnAgentRuntime ------------------------------------------------

/// ReAct-style agent backed by an on-device MnnLlmSession.
///
/// Each [run] performs up to [maxSteps] reasoning rounds. In each round:
///   1. The model generates a response (streamed as [AgentTokenEvent]).
///   2. If the response contains a <tool_call> block, the tool is executed
///      and its result is fed back for the next round.
///   3. If no tool call is found, the response is the final answer.
class LocalMnnAgentRuntime implements AgentRuntime {
  LocalMnnAgentRuntime(this._session, {this.maxSteps = 5, this.androidMode = false});

  final MnnLlmSession _session;
  final Map<String, Tool> _tools = {};
  int maxSteps;
  static const Duration _defaultToolTimeout = Duration(seconds: 30);
  static const Duration _logMaxAge = Duration(hours: 24);
  static const int _logMaxLines = 5000;
  static const int _logTrimTarget = 3000;
  int _consecutivePermissionErrors = 0;

  /// When true the system prompt adds Android-automation specific rules
  /// (dump the UI first, prefer click_by_text/click_by_id, wait for page
  /// transitions, …). Auto-enabled by ChatPage when the first tool with
  /// name starting with `android_` is registered.
  final bool androidMode;

  /// 动态调整最大推理步数。
  void setMaxSteps(int steps) => maxSteps = steps.clamp(1, 100);

  @override
  void registerTool(Tool tool) => _tools[tool.name] = tool;

  @override
  void unregisterTool(String name) => _tools.remove(name);

  @override
  Stream<AgentEvent> run(String userInput) async* {
    final conversation = StringBuffer();

    // System prompt with tool descriptions.
    conversation.writeln(_buildSystemPrompt());
    conversation.writeln('用户: $userInput');

    for (var step = 0; step < maxSteps; step++) {
      conversation.writeln('\n助手:');

      final buffer = StringBuffer();
      var toolCallDetected = false;

      try {
        await for (final chunk in _session.chatStream(conversation.toString())) {
          buffer.write(chunk);

          // Check for tool call in the accumulated buffer.
          final parsed = _tryParseToolCall(buffer.toString());
          if (parsed.json != null) {
            // Emit any text before the tool call tag.
            final beforeTool = buffer.toString().substring(0,
                buffer.toString().indexOf(_kToolCallOpen));
            if (beforeTool.isNotEmpty) {
              yield AgentTokenEvent(beforeTool);
            }

            final toolInfo = _parseToolJson(parsed.json!);
            if (toolInfo != null) {
              yield AgentToolCallEvent(
                toolName: toolInfo.name,
                arguments: toolInfo.args,
              );

              final result = await executeTool(toolInfo.name, toolInfo.args);
              yield ToolExecutionEvent(
                toolName: toolInfo.name,
                result: result,
              );

              // Feed the tool result back into the conversation.
              conversation.write(buffer.toString().substring(0,
                  buffer.toString().indexOf(_kToolCallClose) +
                  _kToolCallClose.length));
              conversation.writeln(
                  '\n[工具结果] ${result.output}');

              toolCallDetected = true;
              break;
            } else {
              // Malformed tool call — emit as text.
              yield AgentTokenEvent(chunk);
            }
          } else if (parsed.remainder.length < buffer.length) {
            // Partial tool_call tag detected — emit the safe prefix.
            final safeLen = buffer.length - parsed.remainder.length;
            if (safeLen > 0) {
              final safe = buffer.toString().substring(0, safeLen);
              yield AgentTokenEvent(safe);
              buffer.clear();
              buffer.write(parsed.remainder);
            }
          } else {
            // Normal text — emit the chunk.
            yield AgentTokenEvent(chunk);
          }
        }
      } catch (e) {
        yield AgentErrorEvent('推理失败: $e');
        return;
      }

      if (!toolCallDetected) {
        // No tool call — this is the final answer.
        final answer = buffer.toString().trim();
        yield AgentDoneEvent(answer, steps: step + 1);
        return;
      }
    }

    yield AgentErrorEvent('达到最大推理步数 ($maxSteps)');
  }

  String _buildSystemPrompt() {
    if (_tools.isEmpty) {
      return '你是一个有用的助手。直接回答用户的问题。';
    }

    final hasAndroidTools =
        _tools.keys.any((k) => k.startsWith('android_')) || androidMode;

    final toolList = _tools.values.map((t) {
      final params = t.schema['properties'];
      final paramStr = params is Map
          ? params.keys.map((k) => '$k: ${(params[k] as Map?)?['description'] ?? ''}').join(', ')
          : '无';
      return '- ${t.name}: ${t.description}。参数: {$paramStr}';
    }).join('\n');

    return buildSystemPrompt(
      hasTools: _tools.isNotEmpty,
      hasAndroidTools: hasAndroidTools,
      toolList: toolList,
    );
  }

  @override
  Future<ToolResult> executeTool(String name, Map<String, dynamic> args) async {
    final tool = _tools[name];
    if (tool == null) {
      return ToolResult.error(
          toolError('未知工具: $name', advice: '用 skill_list 查看可用工具，或 skill_enable 启用对应技能。'));
    }
    final stopwatch = Stopwatch()..start();
    try {
      final result = await tool.handler(args).timeout(_defaultToolTimeout);
      stopwatch.stop();
      _logExecution(name, args, result, stopwatch.elapsedMilliseconds);
      // 检测权限相关错误，累计计数
      if (result.isError && _isPermissionError(result.output)) {
        _consecutivePermissionErrors++;
        if (_consecutivePermissionErrors >= 2) {
          _consecutivePermissionErrors = 0;
          return ToolResult.error(
              toolError('连续多次操作因权限失败',
                  code: ToolErrorCode.permission,
                  advice: '调用 android_permission_self_heal action=check_and_fix 自动修复权限。\n'
                      '或调用 android_shizuku_simplified action=check 查看权限状态。'));
        }
      } else {
        _consecutivePermissionErrors = 0;
      }
      return result;
    } on TimeoutException {
      stopwatch.stop();
      final err = ToolResult.error(
          toolError('工具执行超时 (${_defaultToolTimeout.inSeconds}秒): $name',
              code: ToolErrorCode.timeout, advice: '如果操作确实需要更长时间，可增大超时设置。'));
      _logExecution(name, args, err, stopwatch.elapsedMilliseconds);
      return err;
    } catch (e) {
      stopwatch.stop();
      final err = ToolResult.error(
          toolError('工具执行失败: $e',
              advice: '检查工具参数是否正确，或查看 agent_execution.log 获取详细错误信息。'));
      _logExecution(name, args, err, stopwatch.elapsedMilliseconds);
      return err;
    }
  }

  /// 检测错误信息是否与权限相关。支持 toolError 格式（🔒 前缀）和传统文本。
  bool _isPermissionError(String message) {
    final keywords = [
      '权限', 'permission', 'denied', 'WRITE_SECURE', 'ACCESS_',
      '拒绝', '未授权', 'forbidden', 'not granted',
      'Shizuku', 'shizuku', 'accessibility', '无障碍',
      '🔒',
    ];
    final lower = message.toLowerCase();
    return keywords.any((k) => lower.contains(k.toLowerCase()));
  }

  /// 记录工具执行日志到文件。
  void _logExecution(String toolName, Map<String, dynamic> args, ToolResult result, int ms) {
    try {
      final logPath = '/sdcard/Android/data/com.openagent.openagent/files/agent_execution.log';
      final file = File(logPath);
      final argSummary = args.toString().length > 80
          ? '${args.toString().substring(0, 80)}...'
          : args.toString();
      final line = '[${DateTime.now().toIso8601String()}] $toolName | $argSummary | ${result.isError ? "ERROR" : "OK"} | ${ms}ms\n';
      file.writeAsStringSync(line, mode: FileMode.append);
      // 控制日志大小：超过 5000 行时截断
      _trimLogIfNeeded(file);
    } catch (_) {
      // 日志写入失败不影响主流程
    }
  }

  /// 日志文件超过 5000 行时保留后 3000 行。
  void _trimLogIfNeeded(File file) {
    try {
      if (!file.existsSync()) return;
      final lines = file.readAsLinesSync();
      if (lines.length > _logMaxLines) {
        final trimmed = lines.sublist(lines.length - _logTrimTarget);
        file.writeAsStringSync('${trimmed.join('\n')}\n');
      }
    } catch (_) {}
  }

  @override
  Future<void> dispose() => _session.dispose();
}
