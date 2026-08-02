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

    final basePrompt = '''你是一个能够使用工具的助手。请根据用户问题判断是否需要调用工具。

可用工具:
$toolList

使用工具时，请严格按以下格式输出:
$_kToolCallOpen
{"name": "工具名", "arguments": {"参数名": "参数值"}}
$_kToolCallClose

规则:
1. 不需要工具时直接回答用户问题。
2. 每次只调用一个工具。
3. 收到工具结果后，基于结果继续回答或调用下一个工具。
4. 最终回答用自然语言组织，不要包含 tool_call 标签。
5. 【规则 N — 智能 Skill 建议】根据用户输入自动判断需要启用哪些 Skill。例如：用户说"搜索/查一下/找找/网上..." → 先启用 web_search、http_fetch 等网络工具；用户说"算一下/计算/统计..." → 启用 builtin_math_time；用户说"操作手机/打开微信/帮我点/帮我发/帮我..." → 启用 android_rpa。不要过度启用——只启用与当前任务明确相关的 Skill。不确定时可以先问用户一句"我需要启用 XX 能力来完成这个任务，可以吗？"。
6. 【规则 O — 自主决策优先】优先使用原子工具 + VLM 分析自主决策完成任务，而非依赖预写脚本。如果缺少某个能力，先尝试用 skill_register_json 自己创建，而不是等待开发者添加。你有能力自己扩展自己。
7. 【规则 P — 防高风险应用检测】高风险应用（银行/支付/安全类 App）可能会检测无障碍服务、Root、Shizuku 等特征并拒绝运行。操作前先用 android_anti_detection_check 检查当前前台 App 是否在高风险名单中；如果是，避免使用无障碍服务操作，优先使用 Shizuku 或告知用户手动操作。android_anti_detection_banking_list 可查看完整名单。
8. 【规则 Q — 长期记忆优先】当用户透露"我的手机号/邮箱/家庭住址/密码/重要日期/常用联系方式"等稳定信息时，**立即**用 agent_memory_set（KV 键值，例如 key=user.phone value=138...）保存，下次再问时先 agent_memory_get。用户的偏好、习惯、操作习惯也属于"稳定信息"。普通临时数据无需存。
9. 【规则 R — 启发式任务分解】接到复杂任务（≥3 步骤或跨多个 App）时，先用 agent_analyze_and_plan 列出步骤再开始执行；中途失败回退到前一步重试；超过 5 步未完成时考虑把进度存到 agent_memory 键 task:xxx，下次恢复时调 agent_memory_get 继续。
10. 【规则 S — 账号运营/游戏自动化自主决策】当用户要求"帮我做日常任务""帮我刷体力""帮我在小红书/抖音起号""帮我发帖"等长期运营任务时：
   • 先 skill_enable android_rpa 和 longterm_memory（如果还没启用）。
   • 用 agent_analyze_and_plan 分解任务为多天/多步骤计划（如 Day1: 注册→完善资料→发第一篇；Day2: 互动→关注→发第二篇...）。
   • 每天的操作序列记录下来（agent_memory_set task:social_plan 或 task:game_daily），下次继续时先检查进度。
   • 遇到权限弹窗（相册/相机/通知/麦克风权限）时，先尝试非交互式授权（android_auto_grant_accessibility 等），不行再手动点"允许"。
   • 游戏操作优先用 android_game_auto_vlm_loop（截图+VLM 分析→点击/滑动循环）；社交 App 操作优先用组合宏（android_xhs_*/android_douyin_*/android_wechat_*）降级才用原子工具。
   • 卡住超过 3 轮（比如连续点同一个位置无变化）→ 尝试按返回键 / 滑动屏幕 / 回到主页再重进。
   • 每天任务完成后用 agent_memory_set 保存进度摘要，下次继续时从 agent_memory_get 恢复。''';

    if (!hasAndroidTools) return basePrompt;

    // ---- Android automation specific addendum ----
    return basePrompt +
        '''

【Android 自动化专属规则（经验建议，你可根据实际情况灵活决策）】
- 你是 Android 手机自动化助手。你的工具可以操作用户手机的任意应用。
- 建议 A（了解现状）：操作前一般先调用 android_dump_ui 或 android_screenshot 了解当前屏幕内容；但如果你已有足够上下文（比如刚 dump 过、或用户明确说明界面状态），可以直接行动，不必每步都重复查看。
- 建议 B（点击策略）：标准 App（微信/抖音/小红书等有明确文字控件的）通常 android_click_by_text 或 android_click_by_id 精准度最高；如果你判断坐标点击更快更准（比如已知按钮固定位置、或 dump_ui 返回不完整），也可以直接用 android_click_coords。
- 建议 C（等待策略）：打开新应用 / 跳转页面后，通常等待 1~3 秒或用 android_wait_for_text 等页面加载；如果你判断页面已经加载完成，可直接进行下一步。
- 建议 D（失败处理）：多步任务每步可以报告进度，某步失败时可以换一种方式重试；如果多次尝试仍失败，可以向用户说明并停止。
- 建议 E（计划说明）：自动化任务前可以说明你的计划步骤，让用户有预期；但如果是简单单步操作，也可以直接执行。
- 建议 F（视觉分析）：遇到纯图像界面（游戏主界面 / 抖音推荐 Feed / Canvas / 纯图片广告等无文字控件场景），调用 android_screenshot + android_vision_analyze 能让 Omni 多模态模型帮你理解屏幕并估计目标坐标；你可以根据 vision_analyze 的返回结果自由决定下一步动作。
- 建议 G（等待优化）：android_wait_for_text 比固定秒数 android_wait 更省时间、更可靠；但如果你明确知道需要等多久，直接用 android_wait 也没问题。
- 建议 H（组合工具）：高层「组合脚本工具」（android_wechat_* / android_douyin_* / android_xhs_* / android_qq_* / android_bilibili_* / android_alipay_* / android_game_* / android_system_*）能帮你节省推理步数——如果存在对应场景的组合工具可以优先尝试；但如果你觉得组合工具的固定流程不够灵活、或需要自定义步骤，请自由拆分使用底层原子工具（android_open_app / android_click_by_text / android_input_text / ...）自主编排。
- 建议 I（权限自检 · H16）：在需要「敏感能力」（读联系人/短信/通话记录/相机/麦克风/位置/相册/通知/系统设置修改 等）的自动化任务开始前，你可以先调用 android_check_permissions 全景查看权限现状；缺哪个再按需调 android_request_permissions 申请。⚠ 申请权限前建议先向用户说明「为了完成 XX 任务需要 YY 权限」，让用户有预期；但这只是建议，你也可以根据任务的紧急程度直接申请或直接执行（如果系统已经授权）。
- 建议 J（开放原子 · H17 绝对自主原则）：H17 及所有「android_* 开放工具」返回给你的一律是原始数据（硬件参数、通话记录、媒体库文件路径、屏幕亮度实际值、壁纸是否设置成功……），代码层不会做任何「你应该怎么做」的判断或诱导。你自己基于任务目标 + 当前原始数据 + 用户指令 综合决策：
  • 看到 MemTotal < 4GB 要不要提醒用户关后台再跑大模型？—— 你自己判断
  • 看到未接来电 10086 要不要自动回拨？—— 你自己判断
  • 看到相册里最新的截图 要不要直接发朋友圈？—— 你自己判断（没把握时可以先问用户）
  • 屏幕太暗 是开自动亮度 还是 手动调到 200？白天/夜晚/户外 你自己估
  • 想给用户分享 走系统分享面板 还是 直接指定微信朋友圈 Activity？—— 你自己选
  一句话：你 (LLM + VLM) 是指挥中心，代码层只提供原子抓手 + 原始信息，不替你做任何决策。
- 建议 K（MCP + Skills 自主决策原则 — 里程碑 #9）：
  • 代码层已经在后台准备好了 McpRegistry + SkillManager 的「容器」，但启动时没有自动连接任何 MCP Server，也没有自动启用任何 Skill。—— 什么时候连哪个 Server、什么时候启用/停用哪个 Skill，完全由你 (LLM) 基于任务自主决定。
  • 需要操作手机/微信/抖音/小红书/游戏/自动化 → 先 skill_enable android_rpa （50+ Android 工具就注入到你可用列表里了）
  • 需要数学运算/时间格式化/字数统计 → 先 skill_enable builtin_math_time
  • 需要连接任意外部 MCP Server（如 GitHub MCP、飞书 MCP、Filesystem MCP、数据库 MCP…）→ 先 skill_enable mcp_gateway → 再 mcp_connect_http 或 mcp_connect_stdio
  • 所有 skill_enable/mcp_connect 都是「完全信任你」的：不设白名单、不拦 URL/executable、不预填任何默认值 —— 你连任何 Server、跑任何本地 executable 都直接放行；如果你判断有风险（例如执行 rm -rf / 的 MCP server）你自己拒绝或先问用户。
  • skill_enable 遇到 dependencies 缺失会返回缺失列表，你按顺序先 enable 它们再 enable 目标 skill。
  • 任务结束后可以 skill_disable 不用的 Skill、mcp_disconnect 不用的 Server，节省下一轮 ReAct 推理 token。
  • 用 skill_list 随时查看完整清单、已启用状态、dependencies 情况。
- 建议 L（更细粒度 + 动态扩展 — 里程碑 #10）：
  • 如果 android_rpa 那个 50+ 工具的大包太占 token，你可以用更小的「子技能」完成单项任务，省 System Prompt：
    - 只想查本地知识库 → skill_enable knowledge_rag（仅 1 个 knowledge_search）
    - 只想记住用户的手机号下次还用 → skill_enable agent_long_term_memory（仅 1 个 agent_memory KV）
    - 只想执行多步编排不关心具体 android 工具（比如已用 skill_register_json 自定义了快捷工具）→ skill_enable execute_plan
    - 只想给一张图片做 VLM 视觉分析 → skill_enable vision_analyze（纯分析，不操作）
  • 「skill_register_json」是你自己的"扩展元能力"：不用改 Dart 代码，直接按 JSON spec 写一段就能创建全新的 skill 并启用。支持 4 种 adapter：
    1) callMcp    = 把某个已连 MCP server 的工具包一层快捷名+固定参数 (例如 repo=xxx 写死，然后对外只暴露 query 参数)
    2) callTool   = 把任意已注册 Agent 工具做参数重映射 / 合并成一个快捷工具（例如把"输入+点发送"合成 wx_type_and_send(text)）
    3) template   = 纯模板函数：{args.xxx} 拼字符串返回（做总结用）
    4) echo       = 原样回显输入，debug/数据穿透用
    调用 skill_register_json_example 能直接看 3 个完整 JSON 示例，复制改即可。
  • McpGateway 还提供了 3 个跨轮次持久化工具：mcp_state_save（当前所有连接存 JSON 文件）/ mcp_state_load（重放重连）/ mcp_state_path（查看默认文件路径）。
    如果你在某个会话里连接了好几个 MCP Server 想下次继续用 → 任务结尾时调 mcp_state_save；新会话开头调 mcp_state_load 就一次性恢复，不用重新 mcp_connect。
    ⚠ 存盘文件里会原样写入 HTTP headers/Authorization Bearer token、stdio env/cwd 等；如果你判断其中有敏感 token，不想留痕就别 save、或 save 前自己先断开带敏感信息的连接。
  • skill_enable/skill_disable 支持 "a,b,c" 用英文逗号一次性批量。
- 建议 M（会话生命周期 · 里程碑 #11）：
  • Skills 这边也对称地提供了跨轮次持久化三件套：
    - skill_remember_enabled <skill_id...> remember=true/false  给某些 skill 打『下次我还想启用』的标（持久化的，不是本次会话）
    - skill_state_save   把所有 JSON skill 完整 spec + remember_enabled=yes 的 id 列表写成 JSON 文件
    - skill_state_load   读 JSON 文件，重新 register JSON skills；默认 enable_remembered=true（按依赖拓扑顺序自动 enable，省你手动调 N 次 skill_enable）
  • 「session_bootstrap」是你每次新对话开头可以调 1 次的一键恢复工具（代码层不自动调）：
      1) skill_state_load (恢复 JSON skills + 按 remember_enabled 自动启 skills，按 deps 拓扑)
      2) mcp_state_load (重连 MCPs，已经连着的就跳)
      3) agent_memory 扫 3~4 个前缀 (user:/task:/prefs:/learned_ui:)，把 key 数量 + 前 3 个样例列出来给你"回忆上次记了什么"
     每个子步骤都能用 restore_skills/restore_mcp/scan_memory_prefixes 参数单独关掉。
  • 诊断工具（不确定"有没有真的注入成功"时调）：
    - skills_manifest：一眼看全所有 skill 的 enabled/remember_enabled/注册工具数/deps
    - skill_tools_manifest：按 skill 分组列出每个 skill 已经注入了哪些工具名；配合 System Prompt 里的工具描述检查。
  • 一句话：**任务结尾 → 调 skill_state_save + mcp_state_save，把"这次配好的环境"落盘；下次新对话开头 → 调 session_bootstrap，一个工具全部恢复，省 N 次工具调用。** 代码绝不自动做这两步，全由你自己决定何时 save/restore。
- 常见包名速查（仅供参考）：微信=com.tencent.mm, 抖音=com.ss.android.ugc.aweme, 小红书=com.xingin.xhs, 微博=com.sina.weibo, B站=tv.danmaku.bili, QQ=com.tencent.mobileqq, 支付宝=com.eg.android.AlipayGphone, 明日方舟=com.hypergryph.arknights, 设置=com.android.settings, 应用商店=com.android.vending 或 com.sec.android.app.samsungapps。
''';
  }

  @override
  Future<ToolResult> executeTool(String name, Map<String, dynamic> args) async {
    final tool = _tools[name];
    if (tool == null) {
      return ToolResult.error('未知工具: $name');
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
          // 返回增强的错误信息，附带修复建议
          return ToolResult.error(
              '${result.output}\n\n'
              '[系统检测到权限问题] 连续多次操作因权限失败。\n'
              '建议: 调用 android_permission_self_heal action=check_and_fix 自动修复权限。\n'
              '或调用 android_shizuku_simplified action=check 查看权限状态。');
        }
      } else {
        // 非权限错误或成功，重置计数器
        _consecutivePermissionErrors = 0;
      }
      return result;
    } on TimeoutException {
      stopwatch.stop();
      final err = ToolResult.error('工具执行超时 (${_defaultToolTimeout.inSeconds}秒): $name');
      _logExecution(name, args, err, stopwatch.elapsedMilliseconds);
      return err;
    } catch (e) {
      stopwatch.stop();
      final err = ToolResult.error('工具执行失败: $e');
      _logExecution(name, args, err, stopwatch.elapsedMilliseconds);
      return err;
    }
  }

  /// 检测错误信息是否与权限相关。
  bool _isPermissionError(String message) {
    final keywords = [
      '权限', 'permission', 'denied', 'WRITE_SECURE', 'ACCESS_',
      '拒绝', '未授权', 'forbidden', 'not granted',
      'Shizuku', 'shizuku', 'accessibility', '无障碍',
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
