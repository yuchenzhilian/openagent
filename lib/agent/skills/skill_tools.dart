// skill_* Agent tools — enable / disable / list the skills managed by SkillManager.
//
// Design principle: these tools are the ONLY pathway for a skill to become
// enabled / disabled. We never toggle skills from UI code or first-launch
// logic — all skill lifecycle decisions are taken by the LLM model through
// these tools, aligned with "don't interfere with model judgment".
import '../agent_runtime.dart';
import 'skills.dart';

List<Tool> createSkillTools(SkillManager skillManager) => <Tool>[
  // -----------------------------------------------------------------
  // skill_list
  // -----------------------------------------------------------------
  Tool(
    name: 'skill_list',
    description:
        '【技能清单】列出当前所有可用的技能（built-in + 已动态注册），包括每个技能的 id / name / version / description / enabled 状态 / 依赖 deps / 已注册工具数量。⚠ 代码层不做任何"推荐启用"的排序或打标 — 你 (LLM) 自己基于用户任务判断应该启用哪几个。dependencies 里列出的 skill 必须先启用、再启用本 skill（否则 skill_enable 会返回错误列出缺失依赖）。',
    schema: const {
      'type': 'object',
      'properties': {
        'only_enabled': {
          'type': 'boolean',
          'description': '可选：true=只返回当前已启用的技能；false/空=返回全部。默认 false。',
        },
      },
    },
    handler: (args) async {
      final onlyEnabled = args['only_enabled'] == true;
      final all = skillManager.listAll();
      final shown = onlyEnabled ? all.where((e) => e['enabled'] == true).toList() : all;
      if (shown.isEmpty) {
        return const ToolResult.ok('(没有可用技能)');
      }
      final sb = StringBuffer();
      for (final s in shown) {
        sb.writeln('-------------------------------------------------------------');
        sb.writeln('id           : ${s['id']}');
        sb.writeln('name         : ${s['name']} (v${s['version']})');
        sb.writeln('enabled      : ${s['enabled']}  idempotent=${s['idempotent']}');
        if (s['dependencies'] is List && (s['dependencies'] as List).isNotEmpty) {
          sb.writeln('dependencies : ${(s['dependencies'] as List).join(', ')} (请先全部启用)');
        }
        sb.writeln('registered   : ${s['registeredTools']} tools');
        final desc = (s['description'] as String).replaceAll('\n', ' ');
        sb.writeln('description  : ${desc.length > 200 ? '${desc.substring(0, 200)}…' : desc}');
      }
      sb.writeln('-------------------------------------------------------------');
      return ToolResult.ok(sb.toString());
    },
  ),

  // -----------------------------------------------------------------
  // skill_enable
  // -----------------------------------------------------------------
  Tool(
    name: 'skill_enable',
    description:
        '【启用技能】按 skill_list 中的 id 启用某个技能：满足依赖后，该技能自己会注册 N 个工具到 Agent，Agent 接下来的 ReAct 步骤就能直接用这些工具。⚠ 代码层绝不自动启用任何技能，也不诱导 "你应该启用这个" —— 你自己判断当前用户任务需要哪些。如果该 skill 已经有启用状态 + idempotent=true 会直接返回 OK（不重复注册）。',
    schema: const {
      'type': 'object',
      'properties': {
        'skill_id': {
          'type': 'string',
          'description': 'skill id，例如 "android_rpa" / "builtin_math_time" / "mcp_gateway"。支持同时启用多个：传 "id1,id2,id3" 用英文逗号分隔，我们会按数组顺序逐个启用（前一个失败则后一个仍尝试，结果里逐个列出）。',
        },
      },
      'required': ['skill_id'],
    },
    handler: (args) async {
      final raw = (args['skill_id'] as String?).toString().trim();
      if (raw.isEmpty) return const ToolResult.error('skill_id 不能为空');
      final ids = raw.split(RegExp(r'[,,;\s]+')).where((s) => s.isNotEmpty).toList();
      final sb = StringBuffer();
      var allOk = true;
      for (final id in ids) {
        final r = await skillManager.enable(id);
        if (r.startsWith('ERROR')) allOk = false;
        sb.writeln(r);
      }
      return allOk ? ToolResult.ok(sb.toString()) : ToolResult.error(sb.toString());
    },
  ),

  // -----------------------------------------------------------------
  // skill_disable
  // -----------------------------------------------------------------
  Tool(
    name: 'skill_disable',
    description:
        '【停用技能】按 id 停用某个技能，调用它的 onDisable() 并反注册它注册过的全部工具（节省 System Prompt token）。⚠ 代码层不自动在任务结束时清场，你自己判断某个技能不再需要时调用。同样支持 "id1,id2,id3" 批量停用。',
    schema: const {
      'type': 'object',
      'properties': {
        'skill_id': {
          'type': 'string',
          'description': '单个或批量 skill_id（英文逗号分隔）。',
        },
      },
      'required': ['skill_id'],
    },
    handler: (args) async {
      final raw = (args['skill_id'] as String?).toString().trim();
      if (raw.isEmpty) return const ToolResult.error('skill_id 不能为空');
      final ids = raw.split(RegExp(r'[,,;\s]+')).where((s) => s.isNotEmpty).toList();
      final sb = StringBuffer();
      for (final id in ids) {
        sb.writeln(await skillManager.disable(id));
      }
      return ToolResult.ok(sb.toString());
    },
  ),
];
