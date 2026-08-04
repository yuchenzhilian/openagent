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
import 'package:path_provider/path_provider.dart';

import 'agent_constants.dart';
import 'agent_prompt.dart';
import 'constraint_decoder.dart';
import 'package:openagent/data/services/device_monitor_service.dart';
import 'inference_scheduler.dart';
import 'intent_classifier.dart';
import 'kv_cache/sliding_window.dart';
import 'tool_validator.dart';

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

/// Tries to extract a tool call from [buffer].
/// Returns (jsonString, remainder) if a complete tool_call block is found,
/// otherwise returns (null, buffer).
({String? json, String remainder}) _tryParseToolCall(String buffer) {
  final openIdx = buffer.indexOf(kToolCallOpen);
  if (openIdx < 0) return (json: null, remainder: buffer);

  final closeIdx = buffer.indexOf(kToolCallClose, openIdx);
  if (closeIdx < 0) {
    // Tag opened but not closed yet — keep buffering.
    // Emit text before the tag so the user sees partial output.
    return (json: null, remainder: buffer.substring(openIdx));
  }

  final jsonStr = buffer
      .substring(openIdx + kToolCallOpen.length, closeIdx)
      .trim();
  final remainder = buffer.substring(closeIdx + kToolCallClose.length);
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
  LocalMnnAgentRuntime(this._session, {this.maxSteps = 5, this.androidMode = false}) {
    _slidingWindow = SlidingWindowCache();
    _scheduler = InferenceScheduler(monitor: DeviceMonitorService());
    _scheduler.start();
  }

  final MnnLlmSession _session;
  final Map<String, Tool> _tools = {};
  int maxSteps;
  static const Duration _defaultToolTimeout = kDefaultToolTimeout;
  static const int _logMaxLines = 5000;
  static const int _logTrimTarget = 3000;
  int _consecutivePermissionErrors = 0;

  // KV Cache management.
  late final SlidingWindowCache _slidingWindow;

  // Adaptive inference scheduling.
  late final InferenceScheduler _scheduler;

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
    // 0. Adaptive profile — adjust inference parameters based on device state.
    final profile = _scheduler.currentProfile;
    maxSteps = profile.maxSteps;

    // 0. Intent classification — skip unnecessary ReAct for simple requests.
    final classifier = IntentClassifier();
    final intent = classifier.classify(userInput);
    if (intent.confidence == 'high' && intent.suggestedTool != null) {
      // Direct tool call for simple intents.
      final result = await executeTool(intent.suggestedTool!, {});
      if (!result.isError) {
        yield AgentDoneEvent(result.output, steps: 0);
        return;
      }
      // Fall through to ReAct loop if the direct call fails.
    }

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
                buffer.toString().indexOf(kToolCallOpen));
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
                  buffer.toString().indexOf(kToolCallClose) +
                  kToolCallClose.length));
              conversation.writeln(
                  '\n[工具结果] ${result.output}');

              toolCallDetected = true;

              // KV Cache management: feed conversation into sliding window
              // to keep context within memory budget.
              _slidingWindow.add(conversation.toString());
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

    // 1. Schema validation (fast path — reject invalid args early).
    {
      final validator = ToolValidator();
      final validation = validator.validate(tool, args);
      if (!validation.isValid) {
        return validator.toErrorResult(validation);
      }
    }

    // 2. Self-correcting retry loop with exponential backoff.
    const maxRetries = 2;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      final stopwatch = Stopwatch()..start();
      try {
        final result = await tool.handler(args).timeout(_defaultToolTimeout);
        stopwatch.stop();
        await _logExecution(name, args, result, stopwatch.elapsedMilliseconds);

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

        // If the result is OK, return immediately.
        if (!result.isError) return result;

        // If the error is retryable, attempt a retry.
        if (attempt < maxRetries && _isRetryableError(result.output)) {
          final delay = Duration(milliseconds: 500 * (1 << attempt)); // 500ms, 1s
          await _logExecution(name, args, ToolResult.ok('等待重试 #${attempt + 1} ($delay)'),
              stopwatch.elapsedMilliseconds);
          await Future.delayed(delay);
          continue; // Retry
        }

        // Non-retryable error or max retries exceeded.
        return result;
      } on TimeoutException {
        stopwatch.stop();
        if (attempt < maxRetries) {
          final delay = Duration(milliseconds: 500 * (1 << attempt));
          await _logExecution(name, args, ToolResult.ok('超时重试 #${attempt + 1} ($delay)'),
              stopwatch.elapsedMilliseconds);
          await Future.delayed(delay);
          continue; // Retry with increased timeout
        }
        final err = ToolResult.error(
            toolError('工具执行超时 (${_defaultToolTimeout.inSeconds}秒): $name',
                code: ToolErrorCode.timeout, advice: '如果操作确实需要更长时间，可增大超时设置。'));
        await _logExecution(name, args, err, stopwatch.elapsedMilliseconds);
        return err;
      } catch (e) {
        stopwatch.stop();
        if (attempt < maxRetries && _isRetryableException(e)) {
          final delay = Duration(milliseconds: 500 * (1 << attempt));
          await _logExecution(name, args, ToolResult.ok('异常重试 #${attempt + 1} ($delay)'),
              stopwatch.elapsedMilliseconds);
          await Future.delayed(delay);
          continue;
        }
        final err = ToolResult.error(
            toolError('工具执行失败: $e',
                advice: '检查工具参数是否正确，或查看 agent_execution.log 获取详细错误信息。'));
        await _logExecution(name, args, err, stopwatch.elapsedMilliseconds);
        return err;
      }
    }
    // Should never reach here.
    return ToolResult.error(toolError('工具执行异常: 重试耗尽'));
  }

  /// 判断错误是否可重试。
  bool _isRetryableError(String message) {
    final lower = message.toLowerCase();
    // 网络/超时/资源竞争类错误可重试
    if (lower.contains('timeout') || lower.contains('超时')) return true;
    if (lower.contains('network') || lower.contains('网络')) return true;
    if (lower.contains('not found') || lower.contains('找不到')) return true;
    if (lower.contains('busy') || lower.contains('忙')) return true;
    if (lower.contains('try again') || lower.contains('重试')) return true;
    return false;
  }

  /// 判断异常是否可重试。
  bool _isRetryableException(Object e) {
    if (e is TimeoutException) return true;
    if (e is SocketException) return true;
    if (e is HttpException) return true;
    return false;
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
  Future<void> _logExecution(String toolName, Map<String, dynamic> args, ToolResult result, int ms) async {
    try {
      final logDir = await getApplicationDocumentsDirectory();
      final logFile = File('${logDir.path}/agent_execution.log');
      final argSummary = args.toString().length > kLogArgMaxLen
          ? '${args.toString().substring(0, kLogArgMaxLen)}...'
          : args.toString();
      final line = '[${DateTime.now().toIso8601String()}] $toolName | $argSummary | ${result.isError ? "ERROR" : "OK"} | ${ms}ms\n';
      await logFile.writeAsString(line, mode: FileMode.append);
      // 控制日志大小：超过 5000 行时截断
      await _trimLogIfNeeded(logFile);
    } catch (_) {
      // 日志写入失败不影响主流程
    }
  }

  /// 日志文件超过 5000 行时保留后 3000 行。
  Future<void> _trimLogIfNeeded(File file) async {
    try {
      if (!await file.exists()) return;
      final lines = await file.readAsLines();
      if (lines.length > _logMaxLines) {
        final trimmed = lines.sublist(lines.length - _logTrimTarget);
        await file.writeAsString('${trimmed.join('\n')}\n');
      }
    } catch (_) {
      // 日志截断失败不影响主流程
    }
  }

  @override
  Future<void> dispose() {
    _scheduler.dispose();
    return _session.dispose();
  }
}
