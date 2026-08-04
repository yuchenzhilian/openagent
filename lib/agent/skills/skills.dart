// OpenAgent Skills — composable, on-demand bundles of Agent tools.
//
// Design principle (strictly aligned with user rule: no code-level interference):
// - We NEVER auto-enable any skill. All skills start as "available but disabled".
// - The model (LLM+VLM) decides, per task and based on user's instruction,
//   which skill to enable/disable via skill_enable / skill_disable tools.
// - A Skill is the smallest re-usable unit: it exposes a list of Tool objects
//   plus optional metadata (id/name/description/version/dependencies).
//
//   SkillManager tracks per-skill "enabled" state and forward-registers each
//   tool into AgentRuntime.registerTool() when enabled; unregisters on disable.
//
//   We ship 3 built-in skills as examples. More skills can be added by the
//   model via mcp_connect (remote toolsets) or via hot-swapping Skill
//   subclasses in code — but for this code milestone, 3 built-in demonstrates
//   the abstraction works end-to-end.
//
//   Also in this file: `JsonSpecSkill` + `JsonSpecResolvers` (Milestone #10).
//   JsonSpecSkill is a Skill subclass described entirely by a JSON map, so the
//   model can create NEW skills at runtime without Dart source edits via
//   skill_register_json tool. The 4 tool adapters live here so SkillManager
//   can snapshot/restore JsonSpecSkills without circular imports.
import 'dart:async';
import 'dart:convert';

import '../agent_runtime.dart';
import '../android_tools.dart';
import '../builtin_tools.dart';
import '../../data/services/android_automation_service.dart';
import '../mcp/mcp_client.dart';

/// A Skill = an on-demand bundle of Agent tools.
abstract class Skill {
  String get id;
  String get name;
  String get description;
  String get version => '1.0.0';

  /// Skill ids that must be enabled BEFORE this skill can enable.
  /// Default = no deps. When deps are missing, skill_enable returns an error
  /// listing the missing deps — the model can then enable them first.
  List<String> get dependencies => const [];

  /// Whether the skill can be disabled/enabled repeatedly. Default true.
  /// Skills that should only ever be toggled once per app launch (rare) can
  /// override to false; SkillManager will reject second enable() calls.
  bool get idempotent => true;

  /// Register this skill's tools using [registerTool]. Implementation must not
  /// perform side effects beyond registering tools & initialising minimal state.
  Future<void> onEnable(void Function(Tool) registerTool);

  /// Optional cleanup (close streams, release resources). Default no-op.
  Future<void> onDisable() async {}
}

/// Tracks which skills are available + which are currently enabled.
///
/// Notifies via [onChanged] stream whenever a skill changes state. Primarily
/// used by the model-facing tools (skill_enable/skill_disable/skill_list);
/// the UI can also consume onChanged if it wants a skill gallery page.
class SkillManager {
  SkillManager({
    required this.registerAgentTool,
    required this.unregisterAgentTool,
    List<Skill> builtIns = const [],
  }) {
    for (final s in builtIns) {
      _available[s.id] = s;
    }
  }

  final void Function(Tool) registerAgentTool;
  final void Function(String) unregisterAgentTool;

  final _available = <String, Skill>{};
  final _enabled = <String, bool>{};
  final _remembered = <String, bool>{}; // remember_enabled flag
  final _toolIdsBySkill = <String, List<String>>{};
  final _changed = StreamController<String>.broadcast();

  Stream<String> get onChanged => _changed.stream;

  /// Register a new skill as "available". Does NOT enable it.
  ///
  /// Overwrites any previous skill with the same [id]. This is useful when the
  /// model (or a hot-reload developer) wants to replace a skill at runtime.
  void registerAvailable(Skill skill) {
    _available[skill.id] = skill;
    _changed.add('registered:${skill.id}');
  }

  List<Skill> get availableSkills => _available.values.toList(growable: false);

  bool isAvailable(String id) => _available.containsKey(id);
  bool isEnabled(String id) => _enabled[id] ?? false;
  bool isRemembered(String id) => _remembered[id] ?? false;

  /// remember_enabled toggle: model says "next session bootstrap, re-enable me".
  /// Multiple ids supported via "id1,id2,id3" comma-list. returns OK/ERROR per id.
  String setRemembered(String commaIds, {required bool remember}) {
    final ids = commaIds.split(RegExp(r'[,,;\s]+')).where((s) => s.isNotEmpty).toList();
    if (ids.isEmpty) return 'ERROR: no skill ids provided';
    final sb = StringBuffer();
    for (final id in ids) {
      if (!isAvailable(id)) {
        sb.writeln('[$id] ERROR: skill not available');
        continue;
      }
      _remembered[id] = remember;
      sb.writeln('[$id] OK: remember_enabled = $remember');
      _changed.add('remembered:$id:$remember');
    }
    return sb.toString();
  }

  /// Which skills are currently flagged "remember_enabled" — ordered by insert.
  List<String> get rememberedIds =>
      _remembered.entries.where((e) => e.value).map((e) => e.key).toList(growable: false);

  /// Enumerate all skills with their states, for the skill_list Agent tool.
  List<Map<String, dynamic>> listAll() => _available.values.map((s) {
        return {
          'id': s.id,
          'name': s.name,
          'version': s.version,
          'enabled': isEnabled(s.id),
          'remember_enabled': isRemembered(s.id),
          'description': s.description,
          'dependencies': s.dependencies,
          'idempotent': s.idempotent,
          'registeredTools': (_toolIdsBySkill[s.id] ?? const []).length,
        };
      }).toList(growable: false);

  /// Topologically sort skills respecting dependencies, for batch enable (used by
  /// skill_state_load(enable_remembered=true) and session_bootstrap).
  /// Returns skill ids in an enable-order such that all deps of each skill appear
  /// BEFORE the skill itself. Unknown ids are skipped (not in _available).
  List<String> orderForEnable(Iterable<String> ids) {
    final known = ids.where(isAvailable).toList();
    final inDegree = <String, int>{for (final id in known) id: 0};
    final dependents = <String, List<String>>{for (final id in known) id: []};
    for (final id in known) {
      final s = _available[id]!;
      for (final dep in s.dependencies) {
        if (inDegree.containsKey(dep)) {
          inDegree[id] = (inDegree[id] ?? 0) + 1;
          dependents[dep]!.add(id);
        }
      }
    }
    final order = <String>[];
    final q = [
      for (final k in known)
        if (inDegree[k] == 0) k
    ];
    while (q.isNotEmpty) {
      final id = q.removeAt(0);
      order.add(id);
      for (final d in dependents[id]!) {
        inDegree[d] = inDegree[d]! - 1;
        if (inDegree[d] == 0) q.add(d);
      }
    }
    // Any remaining (cycle / missing dep in known set) get appended in raw order.
    for (final id in known) {
      if (!order.contains(id)) order.add(id);
    }
    return order;
  }

  // -------------------------------------------------------------------------
  // Persistence snapshots (without materialising Skill objects — we only
  // snapshot JsonSpecSkill specs because built-in skills are re-created on
  // every agent run from code. Remember_enabled applies to all ids though.
  // -------------------------------------------------------------------------

  /// Produce a JSON-map snapshot suitable for skill_state_save.
  Map<String, dynamic> snapshotState() {
    final jsonSkills = <Map<String, dynamic>>[];
    for (final s in _available.values) {
      if (s is JsonSpecSkill) {
        jsonSkills.add(s.spec);
      }
    }
    return {
      'version': 1,
      'json_skill_specs': jsonSkills,
      'remember_enabled': rememberedIds,
    };
  }

  /// Load remembered list (returns ids re-registered for JSON skills + set
  /// remembered for every id that matches an available skill). Also returns
  /// per-item results in a String.
  Future<String> restoreJsonSkills(Map<String, dynamic> snapshot, {
    bool enableRemembered = false,
    bool Function(String id)? shouldRegisterJsonSkill,
  }) async {
    final sb = StringBuffer();
    final jsonSkills = snapshot['json_skill_specs'] as List<dynamic>? ?? const [];
    var registered = 0, skipped = 0;
    for (final s in jsonSkills) {
      if (s is! Map<String, dynamic>) { skipped++; continue; }
      final id = (s['id'] as String?).toString().trim();
      if (id.isEmpty) { skipped++; continue; }
      if (shouldRegisterJsonSkill != null && !shouldRegisterJsonSkill(id)) {
        sb.writeln('[json:$id] SKIP (filter rejected)');
        skipped++;
        continue;
      }
      try {
        final skill = JsonSpecSkill(s);
        registerAvailable(skill);
        registered++;
      } catch (e) {
        sb.writeln('[json:$id] ERROR: $e');
        skipped++;
      }
    }
    sb.writeln('JSON skills: restored $registered, skipped $skipped');

    final rememberIds = (snapshot['remember_enabled'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
    var remOk = 0;
    for (final id in rememberIds) {
      if (isAvailable(id)) {
        _remembered[id] = true;
        remOk++;
      }
    }
    sb.writeln('remember_enabled: marked $remOk/${rememberIds.length} ids');

    if (enableRemembered && rememberIds.isNotEmpty) {
      final order = orderForEnable(rememberIds);
      sb.writeln('--- enable_remembered (${order.length}) ---');
      for (final id in order) {
        if (isEnabled(id)) {
          sb.writeln('[$id] already enabled');
        } else {
          sb.writeln('[$id] ${await enable(id)}');
        }
      }
    }
    return sb.toString();
  }

  // Expose tool-ids-per-skill map to diagnostic tools (e.g. skill_tools_manifest)
  Map<String, List<String>> get toolIdsBySkill => Map.unmodifiable(_toolIdsBySkill);

  /// Enable a skill, including:
  /// - check deps are satisfied (fail fast with list of missing deps)
  /// - check non-idempotent skill is not already enabled
  /// - call skill.onEnable(registerTool) and remember which tool names it added
  /// - mark enabled + fire event
  Future<String> enable(String id) async {
    final skill = _available[id];
    if (skill == null) return 'ERROR: skill not found: $id (call skill_list to see available)';
    if (isEnabled(id)) {
      if (!skill.idempotent) {
        return 'ERROR: skill $id is non-idempotent and already enabled';
      }
      return 'OK: skill $id already enabled';
    }
    final missing = <String>[];
    for (final dep in skill.dependencies) {
      if (!isEnabled(dep)) missing.add(dep);
    }
    if (missing.isNotEmpty) {
      return 'ERROR: skill $id has unmet dependencies: ${missing.join(', ')}. Enable them first.';
    }
    final registered = <String>[];
    void wrap(Tool tool) {
      registerAgentTool(tool);
      registered.add(tool.name);
    }
    try {
      await skill.onEnable(wrap);
    } catch (e, st) {
      // roll back any tools registered before the error
      for (final name in registered) {
        try { unregisterAgentTool(name); } catch (_) {
          // 工具注销失败不影响主流程
        }
      }
      return 'ERROR: skill $id failed onEnable: $e\nStack:\n$st';
    }
    _toolIdsBySkill[id] = registered;
    _enabled[id] = true;
    _changed.add('enabled:$id');
    return 'OK: enabled skill $id (${registered.length} tools: ${registered.take(10).join(', ')}${registered.length > 10 ? '…' : ''})';
  }

  /// Disable a skill: call onDisable, unregister all tools, clear flag.
  Future<String> disable(String id) async {
    final skill = _available[id];
    if (skill == null) return 'ERROR: skill not found: $id';
    if (!isEnabled(id)) return 'OK: skill $id was not enabled';
    try {
      await skill.onDisable();
    } catch (e) {
      // continue with tool unregistration regardless
    }
    final tools = _toolIdsBySkill.remove(id) ?? const [];
    for (final name in tools) {
      try { unregisterAgentTool(name); } catch (_) {
        // 工具注销失败不影响主流程
      }
    }
    _enabled[id] = false;
    _changed.add('disabled:$id');
    return 'OK: disabled skill $id (unregistered ${tools.length} tools)';
  }

  Future<void> dispose() async {
    for (final id in List.from(_enabled.keys)) {
      await disable(id);
    }
    await _changed.close();
  }
}

// ============================================================================
// JsonSpecSkill + JsonSpecResolvers (Milestone #10, dynamic skill registration)
//
// Placed in this file alongside SkillManager because:
//   - SkillManager.snapshotState() does `if (s is JsonSpecSkill)` — needs the
//     type defined in the same import scope to avoid circular deps.
//   - restoreJsonSkills constructs JsonSpecSkill instances — same reason.
// ============================================================================

/// Global-ish resolver pair for JsonSpecSkill adapters (callMcp / callTool).
/// We mutate these at `skill_register_json` time so adapters can find the
/// runtime without a Zone reimplementation. Short-lived + single-agent-run =
/// safe enough for this code milestone.
class JsonSpecResolvers {
  static McpRegistry? mcpRegistry;
  static AgentRuntime? agentRuntime;
}

/// Skill built from a JSON map. The model (or user via chat) passes the JSON
/// spec at runtime; no Dart code change required. Supports 4 tool adapters:
///   * callMcp    → forward this tool to an already-connected MCP tool
///   * callTool   → forward to a different already-registered Agent tool,
///                  with argument re-mapping & template interpolation
///   * template   → pure string-interpolation return value
///   * echo       → echo the raw call args as indented JSON
class JsonSpecSkill extends Skill {
  JsonSpecSkill(this.spec) : _parsedTools = _parse(spec);

  final Map<String, dynamic> spec;
  final List<Tool> _parsedTools;
  int get registeredToolCount => _parsedTools.length;

  static List<Tool> _parse(Map<String, dynamic> spec) {
    final tools = spec['tools'] as List<dynamic>? ?? const [];
    final out = <Tool>[];
    for (int i = 0; i < tools.length; i++) {
      final t = tools[i] as Map<String, dynamic>;
      final name = (t['name'] as String?).toString().trim();
      final desc = (t['description'] as String?)?.toString() ?? '';
      final schema = (t['schema'] as Map<String, dynamic>?) ??
          const {'type': 'object', 'properties': {}};
      if (name.isEmpty) continue;
      out.add(Tool(
        name: name,
        description: desc.isEmpty ? '(JSON-specified tool #$i)' : desc,
        schema: schema,
        handler: (args) => _dispatchToolAdapter(t, args, null),
      ));
    }
    return out;
  }

  static Future<ToolResult> _dispatchToolAdapter(
    Map<String, dynamic> toolSpec,
    Map<String, dynamic> callArgs,
    AgentRuntime? runtime,
  ) async {
    // 1) callMcp adapter
    final callMcp = toolSpec['callMcp'] as Map<String, dynamic>?;
    if (callMcp != null) {
      final sid = (callMcp['server_id'] as String?).toString().trim();
      final tname = (callMcp['tool_name'] as String?).toString().trim();
      final overrides = callMcp['arguments'] as Map<String, dynamic>?;
      final finalArgs = overrides == null
          ? callArgs
          : _applyTemplateMap(overrides, callArgs);
      final reg = JsonSpecResolvers.mcpRegistry;
      if (reg == null) {
        return const ToolResult.error(
            'JsonSpecSkill: no McpRegistry attached. First skill_enable mcp_gateway + mcp_connect a server.');
      }
      final client = reg.find(sid);
      if (client == null) {
        return ToolResult.error('JsonSpecSkill.callMcp: MCP server_id=$sid not connected. First mcp_connect it.');
      }
      final r = await client.callTool(tname, finalArgs);
      return r.isError ? ToolResult.error(r.content) : ToolResult.ok(r.content);
    }
    // 2) callTool adapter
    final callTool = toolSpec['callTool'] as Map<String, dynamic>?;
    if (callTool != null) {
      final tname = (callTool['tool_name'] as String?).toString().trim();
      final mapping = callTool['argsMapping'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final finalArgs = _applyTemplateMap(mapping, callArgs);
      final rt = runtime ?? JsonSpecResolvers.agentRuntime;
      if (rt == null) {
        return const ToolResult.error(
            'JsonSpecSkill: no AgentRuntime attached to resolve callTool.');
      }
      return rt.executeTool(tname, finalArgs);
    }
    // 3) template adapter
    final template = toolSpec['template'] as Map<String, dynamic>?;
    if (template != null) {
      final returns = (template['returns'] as String?)?.toString() ?? '';
      return ToolResult.ok(_applyTemplate(returns, callArgs));
    }
    // 4) echo (identity) adapter
    final echo = toolSpec['echo'] as bool? ?? false;
    if (echo) {
      return ToolResult.ok(const JsonEncoder.withIndent('  ').convert(callArgs));
    }
    return const ToolResult.error(
        'JsonSpecSkill tool has no callMcp/callTool/template/echo adapter — nothing to do.');
  }

  /// Recursive `{args.path.to.value}` string interpolation across strings /
  /// maps / lists.
  static dynamic _applyTemplate(dynamic value, Map<String, dynamic> args) {
    if (value is String) {
      if (!value.contains('{args.')) return value;
      return value.replaceAllMapped(
          RegExp(r'\{args\.([a-zA-Z_][\w.]*)\}'), (m) {
        final path = m.group(1)!;
        final parts = path.split('.');
        dynamic cur = args;
        for (final p in parts) {
          if (cur is Map) {
            cur = cur[p];
          } else {
            cur = null;
            break;
          }
        }
        return cur?.toString() ?? '';
      });
    }
    if (value is Map<String, dynamic>) return _applyTemplateMap(value, args);
    if (value is List) {
      return value.map((e) => _applyTemplate(e, args)).toList();
    }
    return value;
  }

  static Map<String, dynamic> _applyTemplateMap(
    Map<String, dynamic> map,
    Map<String, dynamic> args,
  ) =>
      map.map((k, v) => MapEntry(k.toString(), _applyTemplate(v, args)));

  // ---- Skill interface overrides ----
  @override
  String get id => (spec['id'] as String?).toString().trim();
  @override
  String get name =>
      (spec['name'] as String?)?.toString().isEmpty != false
          ? id
          : spec['name'].toString();
  @override
  String get version =>
      (spec['version'] as String?)?.toString().isNotEmpty == true
          ? spec['version'].toString()
          : '0.1.0';
  @override
  List<String> get dependencies {
    final d = spec['dependencies'];
    if (d is List) return d.map((e) => e.toString()).toList();
    return const [];
  }

  @override
  bool get idempotent => spec['idempotent'] != false;

  @override
  String get description =>
      (spec['description'] as String?)?.toString() ??
      '(JSON-registered skill $id with ${_parsedTools.length} tools)';

  @override
  Future<void> onEnable(void Function(Tool) registerTool) async {
    _parsedTools.forEach(registerTool);
  }
}

// ============================================================================
// Built-in skills — 3 to demonstrate the pattern.
// ============================================================================

/// Skill: `android_rpa` — wraps the 50+ Android automation tools that ship as
/// part of OpenAgent. The model enables this when the user task mentions
/// "操作微信/抖音/小红书/游戏/自动化手机" etc.
class AndroidRpaSkill extends Skill {
  AndroidRpaSkill({
    this.androidService,
    this.visionAnalyze,
    this.executeCallback,
    this.memoryBackend,
  });

  final AndroidAutomationService? androidService;
  final Future<String> Function(String screenshotPath, String prompt)? visionAnalyze;
  final Future<ToolResult> Function(String toolName, Map<String, dynamic> args)? executeCallback;
  final AgentMemoryBackend? memoryBackend;

  @override
  String get id => 'android_rpa';
  @override
  String get name => 'Android RPA Automation';
  @override
  String get version => '1.0.0';
  @override
  List<String> get dependencies => const [];
  @override
  String get description =>
      'Android 手机自动化能力：操作任意 App（微信/抖音/小红书/QQ/B站/支付宝/游戏等）；三层权限架构（Accessibility + Shizuku Shell + Root 预留）；50+ 原子/开放工具，20+ 组合宏脚本，多步执行编排 (execute_plan) + KV 长期记忆 (agent_memory) + VLM 视觉分析 (game_vlm_auto_pilot)。用户下达自动化任务时你应启用此 skill。';

  @override
  Future<void> onEnable(void Function(Tool) registerTool) async {
    final tools = createAndroidAutomationTools(
      service: androidService,
      visionAnalyze: visionAnalyze,
      executeCallback: executeCallback,
      memoryBackend: memoryBackend,
    );
    tools.forEach(registerTool);
  }
}

/// Skill: `builtin_math_time` — calculator + datetime + text_statistics unit_tools.
/// The model enables this for arithmetic/datetime/text-count style questions.
///
/// NOTE: We deliberately keep this small — 3 tools. The model can turn it off
/// to save system prompt tokens when not needed.
class BuiltinMathTimeSkill extends Skill {
  BuiltinMathTimeSkill();

  @override
  String get id => 'builtin_math_time';
  @override
  String get name => 'Built-in Calculator / DateTime / Text Statistics';
  @override
  String get description => '3 个基础工具：计算器（任意数学表达式）、当前时间（按任意时区格式化）、文本统计（字数/行数/字符数）。日常算术/时间类问题直接可启用。';

  @override
  Future<void> onEnable(void Function(Tool) registerTool) async {
    final list = builtinTools();
    final ids = {'calculator', 'datetime', 'text_statistics'};
    for (final t in list) {
      if (ids.contains(t.name)) registerTool(t);
    }
  }
}

/// Skill: `mcp_gateway` — exposes the raw mcp_* Agent tools (connect/list/call/
/// disconnect) so the model can wire in arbitrary MCP servers.
///
/// Think of it as the "meta-skill" that gives you the ability to add skills.
/// We provide it as a Skill so that — like everything else — the model opts
/// into the capability instead of it being forced.
class McpGatewaySkill extends Skill {
  McpGatewaySkill(this.registry);

  final McpRegistry registry;

  @override
  String get id => 'mcp_gateway';
  @override
  String get name => 'MCP Gateway (connect external MCP servers)';
  @override
  String get description => '连接任意 MCP (Model Context Protocol) Server，动态引入外部工具能力。支持 HTTP JSON-RPC 远程端点 和 本地子进程 stdio 模式两种 transport。模型根据任务需求自主判断要连哪个 Server、何时断开。';

  @override
  Future<void> onEnable(void Function(Tool) registerTool) async {
    // The actual mcp_* tools are defined in mcp_tools.dart; we import and
    // register them here. Import deferred-invocation pattern:
    createMcpTools(registry).forEach(registerTool);
  }
}

// Declared in mcp_tools.dart (avoid circular import). Defined below as local.
List<Tool> createMcpTools(McpRegistry registry) {
  final out = <Tool>[];

  // mcp_connect: HTTP endpoint
  out.add(Tool(
    name: 'mcp_connect_http',
    description: '【MCP 连接】连接一个远程 HTTP(S) MCP Server，完成 initialize 握手后自动 tools/list 发现工具并返回清单。⚠ 代码层不做任何白名单/黑名单 — 你 (LLM) 自主判断该 URL 是否可信、是否符合用户意图。成功后可用 mcp_list_tools 看清单、mcp_call 调具体工具；用完记得 mcp_disconnect 释放资源。',
    schema: const {
      'type': 'object',
      'properties': {
        'server_id': {'type': 'string', 'description': '给这个连接起个唯一 id，后续 mcp_disconnect/mcp_list_tools/mcp_call 都用它来引用。比如 "github-mcp"、"filesystem-local"。重复 id 会先自动断开旧连接。'},
        'url': {'type': 'string', 'description': 'MCP Server 的 HTTP(S) 基地址。实际 JSON-RPC POST 会发送到 <url>/mcp。支持 http://localhost:<port> 本地调试。'},
        'headers': {'type': 'object', 'description': '可选。附加的 HTTP 请求头，例如 {"Authorization":"Bearer xxx"}、{"x-api-key":"yyy"}。留空=不传。'},
        'timeout_sec': {'type': 'integer', 'description': '可选。单次 HTTP 调用超时秒数 (1~300)。默认 30。'},
      },
      'required': ['server_id', 'url'],
    },
    handler: (args) async {
      final sid = (args['server_id'] as String?).toString().trim();
      final url = (args['url'] as String?).toString().trim();
      if (sid.isEmpty || url.isEmpty) return const ToolResult.error('server_id 和 url 不能为空');
      final headersRaw = args['headers'] as Map<String, dynamic>? ?? const {};
      final headers = headersRaw.map((k, v) => MapEntry(k.toString(), v.toString()));
      final timeoutSec = (args['timeout_sec'] as int? ?? 30).clamp(1, 300);
      // Disconnect old if exists
      if (registry.find(sid) != null) {
        await registry.unregister(sid);
      }
      try {
        final transport = HttpMcpTransport(url, headers: headers, timeout: Duration(seconds: timeoutSec));
        final client = McpClient(transport, serverId: sid);
        final info = await client.initialize();
        if (info.containsKey('error')) {
          await client.dispose();
          return ToolResult.error('MCP initialize 失败：${info['error']}');
        }
        final tools = await client.listTools();
        registry.register(client);
        final infoStr = info.entries.map((e) => '${e.key}: ${e.value}').join('\n');
        return ToolResult.ok('OK: MCP connected id=$sid\nserver_info:\n$infoStr\n\ndiscovered tools (${tools.length}):\n${tools.map((t) => '- ${t.name}  ${t.description.substring(0, t.description.length > 80 ? 80 : t.description.length)}').join('\n')}');
      } catch (e, st) {
        return ToolResult.error('mcp_connect_http failed: $e\n$st');
      }
    },
  ));

  // mcp_connect: stdio
  out.add(Tool(
    name: 'mcp_connect_stdio',
    description: '【MCP 连接 · 本地】启动一个本地可执行文件作为 MCP Server，通过 stdin/stdout 交换 JSON-RPC 2.0。适用于随 App 打包的本地 MCP、或手机上已有可执行的 MCP server。⚠ 和 HTTP 模式一样：不做白名单，你自己判断 executable+args 是否合法。',
    schema: const {
      'type': 'object',
      'properties': {
        'server_id': {'type': 'string', 'description': '连接 id（后续引用用）'},
        'executable': {'type': 'string', 'description': '可执行文件路径，如 "python3"、"/data/local/tmp/mcp-server"、"node"。'},
        'args': {'type': 'array', 'items': {'type': 'string'}, 'description': '命令行参数数组，如 ["-m","mcp_server.filesystem","/sdcard"]。留空=无参数。'},
        'env': {'type': 'object', 'description': '可选。附加环境变量，如 {PATH: /data/local/bin/\$PATH}。'},
        'cwd': {'type': 'string', 'description': '可选。工作目录。'},
      },
      'required': ['server_id', 'executable'],
    },
    handler: (args) async {
      final sid = (args['server_id'] as String?).toString().trim();
      final exe = (args['executable'] as String?).toString().trim();
      if (sid.isEmpty || exe.isEmpty) return const ToolResult.error('server_id 和 executable 不能为空');
      final argsList = (args['args'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList();
      final envRaw = args['env'] as Map<String, dynamic>? ?? const {};
      final env = envRaw.map((k, v) => MapEntry(k.toString(), v.toString()));
      final cwd = args['cwd'] as String?;
      if (registry.find(sid) != null) {
        await registry.unregister(sid);
      }
      try {
        final transport = await StdioMcpTransport.spawn(exe, argsList, environment: env, workingDirectory: cwd);
        final client = McpClient(transport, serverId: sid);
        final info = await client.initialize();
        if (info.containsKey('error')) {
          await client.dispose();
          return ToolResult.error('MCP initialize 失败：${info['error']}');
        }
        final tools = await client.listTools();
        registry.register(client);
        final infoStr = info.entries.map((e) => '${e.key}: ${e.value}').join('\n');
        return ToolResult.ok('OK: MCP stdio connected id=$sid\nserver_info:\n$infoStr\n\ndiscovered tools (${tools.length}):\n${tools.map((t) => '- ${t.name}  ${t.description.substring(0, t.description.length > 80 ? 80 : t.description.length)}').join('\n')}');
      } catch (e, st) {
        return ToolResult.error('mcp_connect_stdio failed: $e\n$st');
      }
    },
  ));

  // mcp_list
  out.add(Tool(
    name: 'mcp_list_connected',
    description: '列出当前已连接的所有 MCP Server，包括每个 server 下发现的工具数量清单。',
    schema: const {'type': 'object', 'properties': {}},
    handler: (_) async {
      if (registry.allClients.isEmpty) return const ToolResult.ok('(没有已连接的 MCP server)');
      final sb = StringBuffer();
      for (final e in registry.allClients.entries) {
        sb.writeln('=== server_id=${e.key}  initialized=${e.value.isInitialized} ===');
        try {
          final tools = await e.value.listTools();
          for (final t in tools) {
            sb.writeln('  - ${t.name}: ${t.description.substring(0, t.description.length > 120 ? 120 : t.description.length)}');
          }
        } catch (e2) {
          sb.writeln('  (tools/list failed: $e2)');
        }
        sb.writeln('');
      }
      return ToolResult.ok(sb.toString());
    },
  ));

  // mcp_call
  out.add(Tool(
    name: 'mcp_call',
    description: '调用某个已连接 MCP Server 的具体工具。参数中指定 server_id + tool_name + arguments。MCP spec 要求 arguments 必须是 JSON object；我们透传不做校验，所有校验由 server 返回。',
    schema: const {
      'type': 'object',
      'properties': {
        'server_id': {'type': 'string', 'description': '已连接的 MCP server id (由 mcp_connect_* 创建)。'},
        'tool_name': {'type': 'string', 'description': '要调用的工具名，由 mcp_list_connected 或 mcp_connect_* 的返回给出。'},
        'arguments': {'type': 'object', 'description': '传给该工具的参数对象，完全按 MCP server 要求填写。'},
      },
      'required': ['server_id', 'tool_name', 'arguments'],
    },
    handler: (args) async {
      final sid = (args['server_id'] as String?).toString().trim();
      final name = (args['tool_name'] as String?).toString().trim();
      final arguments = args['arguments'] as Map<String, dynamic>? ?? const <String, dynamic>{};
      final client = registry.find(sid);
      if (client == null) return ToolResult.error('未找到 server_id=$sid 的连接，先 mcp_connect');
      if (name.isEmpty) return const ToolResult.error('tool_name 不能为空');
      final r = await client.callTool(name, arguments);
      return r.isError ? ToolResult.error(r.content) : ToolResult.ok(r.content);
    },
  ));

  // mcp_disconnect
  out.add(Tool(
    name: 'mcp_disconnect',
    description: '断开某个 MCP 连接并释放资源（HTTP client close / stdio process kill）。断开后 mcp_call 将无法再用。',
    schema: const {
      'type': 'object',
      'properties': {'server_id': {'type': 'string', 'description': '要断开的连接 id'}},
      'required': ['server_id'],
    },
    handler: (args) async {
      final sid = (args['server_id'] as String?).toString().trim();
      final removed = await registry.unregister(sid);
      return removed == null
          ? ToolResult.error('没有 id=$sid 的连接')
          : ToolResult.ok('OK: disconnected $sid');
    },
  ));

  return out;
}
