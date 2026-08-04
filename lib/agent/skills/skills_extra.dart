import 'dart:async';
import 'dart:io';

import '../agent_runtime.dart';
import '../android_tools.dart';
import '../builtin_tools.dart';
import '../mcp/mcp_client.dart';
import 'skills.dart';

// ============================================================================
// Fine-grained built-in skills (each adds ≤ 3 tools)
// ============================================================================

/// Skill: `knowledge_rag` — local txt knowledge-base search.
class KnowledgeRagSkill extends Skill {
  KnowledgeRagSkill(this.knowledgeBaseDir);
  final String knowledgeBaseDir;

  @override
  String get id => 'knowledge_rag';
  @override
  String get name => 'Local Knowledge Base (RAG / TXT search)';
  @override
  String get description =>
      '搜索本地知识库（.txt 文档），返回与查询最相关的前 3 个文本片段。纯词频匹配、无 embedding 依赖、离线可用。用户提问中提到"查知识库"/"查资料"/"从文档里找"时你可以先启用它。';

  @override
  Future<void> onEnable(void Function(Tool) registerTool) async {
    registerTool(knowledgeSearchTool(Directory(knowledgeBaseDir)));
  }
}

/// Skill: `agent_long_term_memory` — KV memory (set/get/delete/list/clear_prefix).
/// The model explicitly enables this whenever it wants "remember stuff across
/// sessions". Not bundled into android_rpa to keep android_rpa smaller.
class AgentLongTermMemorySkill extends Skill {
  AgentLongTermMemorySkill(this.backend);
  final AgentMemoryBackend backend;

  @override
  String get id => 'agent_long_term_memory';
  @override
  String get name => 'Agent Long Term Memory (KV store)';
  @override
  String get description =>
      '跨会话长期 KV 记忆（本地文件持久化）。操作：op=set/get/delete/list/clear_prefix。⚠ 代码层不做任何自动记笔记/自动摘要，全靠你 (LLM) 主动决定存什么。用户提到"记住我的手机号/姓名/常用地址/常用按钮坐标/下次要…"这类需要跨 session 保留的信息时启用。';

  @override
  Future<void> onEnable(void Function(Tool) registerTool) async {
    registerTool(buildAgentMemoryTool(backend));
  }
}

/// Skill: `android_execute_plan` — multi-step plan executor by itself.
/// Useful when the model only wants plan-orchestration without pulling in the
/// 50+ other android tools.
class ExecutePlanSkill extends Skill {
  ExecutePlanSkill(this.executor);
  final Future<ToolResult> Function(String name, Map<String, dynamic> args)
      executor;

  @override
  String get id => 'execute_plan';
  @override
  String get name => 'Multi-step Execute Plan (plan orchestrator)';
  @override
  String get description =>
      '多步编排工具：你 (LLM) 写 steps[] 数组 (最多 50 步)，代码 100% 按你写的顺序严格执行，不做任何修改/跳过/重试。配合 stop_on / step.expect_ok / stop_if_contains 自主决定流程控制。注：你想省 N 轮端侧推理时启用；如果只有 1~2 步直接调工具更快。';

  @override
  Future<void> onEnable(void Function(Tool) registerTool) async {
    registerTool(buildExecutePlanTool(executor));
  }
}

/// Skill: `vision_analyze` — wraps the VLM visionAnalyze callback (if provided)
/// as a standalone `vision_analyze` tool (does NOT require android_rpa).
class VisionAnalyzeSkill extends Skill {
  VisionAnalyzeSkill(this.visionAnalyze);
  final Future<String> Function(String imagePath, String question)?
      visionAnalyze;

  @override
  String get id => 'vision_analyze';
  @override
  String get name => 'VLM Vision Analyze (standalone)';
  @override
  String get description =>
      '把任意本地图片路径丢给多模态 VLM 模型分析，可以问 OCR 内容、这张图里有什么、某区域的大致坐标、UI 里某个按钮在哪等。⚠ 只做分析不做操作；要操作 Android UI 请同时启用 android_rpa。用户纯咨询图片内容时启用即可。';

  @override
  Future<void> onEnable(void Function(Tool) registerTool) async {
    final va = visionAnalyze;
    if (va == null) {
      registerTool(Tool(
        name: 'vision_analyze',
        description:
            '【占位】VLM 回调未初始化，实际不可用。先启用 android_rpa 或用正确的 visionAnalyze 初始化 skill_manager。',
        schema: const {'type': 'object', 'properties': {}},
        handler: (_) async => const ToolResult.error(
            'vision_analyze: VLM callback not initialized. Try enabling android_rpa instead.'),
      ));
      return;
    }
    registerTool(Tool(
      name: 'vision_analyze',
      description:
          '【VLM 视觉分析 · 独立】传入本地图片路径 image_path  + 你要问的问题 prompt，Omni 多模态模型会基于整张图回答。可用于：OCR 文字、描述图片内容、"这个按钮的坐标在哪"、"第几条朋友圈是广告" 等纯视觉问题。如需实际点击请同时启 android_rpa。',
      schema: const {
        'type': 'object',
        'properties': {
          'image_path': {
            'type': 'string',
            'description': '本地图片文件绝对路径（如 /sdcard/Pictures/x.png），不支持网络 URL。'
          },
          'prompt': {
            'type': 'string',
            'description':
                '你想问这张图的问题。如 "帮我把图里所有文字按行转录出来" 或 "绿色点赞按钮的中心坐标是？(用 x,y 百分比)"'
          },
        },
        'required': ['image_path', 'prompt'],
      },
      handler: (args) async {
        final p = (args['image_path'] as String?).toString().trim();
        final q = (args['prompt'] as String?).toString().trim();
        if (p.isEmpty || q.isEmpty)
          return const ToolResult.error('image_path / prompt 不能为空');
        try {
          final r = await va(p, q);
          return ToolResult.ok(r);
        } catch (e, st) {
          return ToolResult.error('vision_analyze failed: $e\n$st');
        }
      },
    ));
  }
}

// ============================================================================
// skill_register_json  —  runtime skill registration meta-tool (factory only)
//
// The JsonSpecSkill class + adapter dispatch logic live in skills.dart so
// SkillManager.snapshotState / restoreJsonSkills can use `s is JsonSpecSkill`
// without a circular import. We only create the Agent tools here.
// ============================================================================

List<Tool> createSkillRegisterJsonTools({
  required SkillManager skillManager,
  McpRegistry? mcpRegistry,
  AgentRuntime? agentRuntime,
}) {
  final out = <Tool>[];

  out.add(Tool(
    name: 'skill_register_json',
    description:
        '【扩展 · 运行时注册新 Skill】不用改 Dart 代码，直接传一段 JSON 就能注册一个全新的可用 skill，之后可以 skill_enable 启用。⚠ 代码层不做任何校验：你 (LLM) 自己保证 JSON schema 正确、自己判断这个新 skill 有没有危险（它的底层 adapter 能转发任意已存在的工具或任意已连接 MCP 工具，所以能力和现有工具一样强 —— 你是唯一的安全边界）。\n'
        'JSON spec 结构：\n'
        '  {"id":"my_skill","name":"…","description":"…","version":"1.0.0","dependencies":["android_rpa"],"idempotent":true,"tools":[...tool_specs...]}\n'
        '每个 tool_spec 里必须包含：name + description + schema(optional, default any) + 至少一个 adapter:\n'
        '  A. callMcp: {"server_id":"github-mcp","tool_name":"search_issues","arguments":{"q":"{args.query} is:open"}}  把本工具调用转发到已连接的某个 MCP server 的 tool，arguments 支持 {args.xxx} 模板\n'
        '  B. callTool: {"tool_name":"android_click_by_text","argsMapping":{"target":"{args.btn_text}","timeout_ms":"3000"}}   把本工具转发到任意已注册的 Agent 工具，支持参数重映射/模板插值\n'
        '  C. template: {"returns":"结果：{args.a} + {args.b} = {args.c}"}   纯模板工具，原样做字符串替换然后返回\n'
        '  D. echo: true   不加任何处理，原样返回输入参数（常用于 debug / 数据穿透）\n'
        '注册成功后 skill_list 就能看到，接着 skill_enable <id> 即可使用。重复注册同一个 id 会覆盖旧的。',
    schema: const {
      'type': 'object',
      'properties': {
        'spec': {
          'type': 'object',
          'description': 'JSON Skill spec。结构见上面说明。',
        },
      },
      'required': ['spec'],
    },
    handler: (args) async {
      final s = args['spec'];
      if (s is! Map<String, dynamic> || s.isEmpty) {
        return const ToolResult.error('spec 必须是非空 object');
      }
      final id = (s['id'] as String?).toString().trim();
      if (id.isEmpty) return const ToolResult.error('spec.id 不能为空');
      JsonSpecSkill newSkill;
      try {
        newSkill = JsonSpecSkill(s);
      } catch (e, st) {
        return ToolResult.error('skill_register_json 解析失败：$e\n$st');
      }
      // Bind global resolvers so JsonSpecSkill.callMcp / .callTool adapters
      // can find the runtime + mcp registry for this agent invocation.
      JsonSpecResolvers.mcpRegistry = mcpRegistry;
      JsonSpecResolvers.agentRuntime = agentRuntime;

      skillManager.registerAvailable(newSkill);
      final n = newSkill.registeredToolCount;
      return ToolResult.ok(
          'OK: registered JSON skill id=$id (${newSkill.name} v${newSkill.version}, $n tools, deps=${newSkill.dependencies}). Use skill_enable $id to enable.');
    },
  ));

  out.add(Tool(
    name: 'skill_register_json_example',
    description:
        '输出 3 个典型 JSON skill 示例（callMcp / callTool 参数重映射 / template），直接复制改几个字段就能用 skill_register_json 注册。',
    schema: const {'type': 'object', 'properties': {}},
    handler: (_) async {
      const ex1 = '''
示例 1 — callMcp：把"已连接的 GitHub MCP server"的 search_issues 包装成一个叫"找我提的 bug"的快捷工具，自动加 repo=我固定的仓库 + is:open。注册后 skill_enable 就可以直接传 query 用：
{
  "id":"gh_my_bugs",
  "name":"Search My Open GitHub Issues",
  "description":"快捷：搜我在某个仓库提的 open issue",
  "dependencies":["mcp_gateway"],
  "tools":[{
    "name":"gh_find_my_bug",
    "description":"传 query 返回匹配的 open issue 列表",
    "schema":{"type":"object","properties":{"query":{"type":"string"}}, "required":["query"]},
    "callMcp":{
      "server_id":"github-mcp",
      "tool_name":"search_issues",
      "arguments":{
        "q":"repo:yuchenzhilian/openagent is:open {args.query}"
      }
    }
  }]
}
''';
      const ex2 = '''
示例 2 — callTool 参数重映射：把 android_click_by_text 包装成一个"点一下『发送』按钮"的零参数工具，不用每次都写 target="发送"：
{
  "id":"wechat_shortcuts",
  "name":"WeChat Shortcuts",
  "dependencies":["android_rpa"],
  "tools":[
    {"name":"wx_click_send","description":"点击当前界面上的『发送』文字按钮",
     "schema":{"type":"object","properties":{}},
     "callTool":{"tool_name":"android_click_by_text","argsMapping":{"target":"发送","timeout_ms":2500}}},
    {"name":"wx_type_and_send","description":"输入文字然后点发送",
     "schema":{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]},
     "callTool":{"tool_name":"android_execute_plan",
       "argsMapping":{
         "steps":[
           {"tool":"android_input_text","args":{"text":"{args.text}","clear_first":true}},
           {"tool":"android_click_by_text","args":{"target":"发送"}}
         ],
         "stop_on":"first_error"
       }
     }}
  ]
}
''';
      const ex3 = '''
示例 3 — template：纯函数工具，把输入按格式拼好返回（常用于做"给用户看的 report"）：
{
  "id":"report_builder",
  "name":"Report Builder Templates",
  "tools":[{
    "name":"fmt_summary",
    "description":"把任务名+耗时+结论格式化成一个漂亮的总结文本",
    "schema":{"type":"object","properties":{
      "task":{"type":"string"},"duration_sec":{"type":"integer"},"conclusion":{"type":"string"}
    },"required":["task","duration_sec","conclusion"]},
    "template":{"returns":"📋 任务总结\\n——任务：{args.task}\\n——耗时：{args.duration_sec} s\\n——结论：{args.conclusion}\\n"}
  }]
}
''';
      return const ToolResult.ok('$ex1\n\n$ex2\n\n$ex3');
    },
  ));

  return out;
}

// ============================================================================
// skill_create_from_trace  —  save a tool-call trace as a reusable Skill
//
// The agent calls this after completing a multi-step task to persist the
// sequence as a JsonSpecSkill that can be enabled later with one click.
// ============================================================================

/// Creates a meta-tool that lets the agent save a trace of tool calls as a
/// reusable JSON Skill, registered via [skillManager] and immediately enabled.
Tool createSkillFromTraceTool(SkillManager skillManager) {
  return Tool(
    name: 'skill_create_from_trace',
    description:
        '【从工具调用轨迹创建可复用 Skill】把你刚刚执行过的一系列工具调用保存为一个可复用的新 Skill，之后 skill_enable 就能一键重放。'
        '用法：在完成一个多步任务后，把每一步的 {tool, args} 按顺序写在 steps 数组里，给一个 skill_name 和 skill_description，'
        '代码会帮你打包成一个 JsonSpecSkill（底层用 callTool adapter 实现），注册到 skill 列表并立即启用。'
        '创建后你可以用 skill_list 查看，也可以 skill_disable 关掉。'
        '如果要覆盖旧的 skill_id，传相同的 skill_name 即可。',
    schema: const {
      'type': 'object',
      'properties': {
        'skill_name': {
          'type': 'string',
          'description':
              '新 Skill 的唯一 ID（也是名字，简短如 wechat_auto_like、daily_report）。',
        },
        'skill_description': {
          'type': 'string',
          'description': 'Skill 的描述，让下次使用时能看懂这是干什么的。',
        },
        'steps': {
          'type': 'array',
          'description': '工具调用轨迹数组，按执行顺序排列。每个元素必须包含 tool（工具名）和 args（参数字典）。',
          'items': {
            'type': 'object',
            'properties': {
              'tool': {
                'type': 'string',
                'description': '工具名，如 android_click_by_text、web_search 等。'
              },
              'args': {
                'type': 'object',
                'description':
                    '传给该工具的参数，key-value 对。支持 {args.xxx} 模板占位符，让重用时能传不同参数。'
              },
            },
            'required': ['tool', 'args'],
          },
        },
      },
      'required': ['skill_name', 'skill_description', 'steps'],
    },
    handler: (args) async {
      final name = (args['skill_name'] as String?).toString().trim();
      final desc = (args['skill_description'] as String?).toString().trim();
      final stepsRaw = args['steps'];
      if (name.isEmpty || desc.isEmpty) {
        return const ToolResult.error('skill_name 和 skill_description 不能为空');
      }
      if (stepsRaw is! List || stepsRaw.isEmpty) {
        return const ToolResult.error('steps 必须是非空数组');
      }

      // Build tool specs: each step becomes a callTool adapter.
      final toolSpecs = <Map<String, dynamic>>[];
      for (var i = 0; i < stepsRaw.length; i++) {
        final step = stepsRaw[i];
        if (step is! Map) {
          return ToolResult.error('steps[$i] 必须是 object，包含 tool 和 args');
        }
        final toolName = (step['tool'] as String?).toString().trim();
        final stepArgs = step['args'];
        if (toolName.isEmpty) {
          return ToolResult.error('steps[$i].tool 不能为空');
        }
        if (stepArgs is! Map<String, dynamic>) {
          return ToolResult.error('steps[$i].args 必须是 object');
        }

        // Generate a unique tool name for this step inside the skill.
        final safeToolName = toolName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
        final stepToolName = 'step${i + 1}_$safeToolName';

        // Build argsMapping: if args values contain {args.xxx} templates,
        // keep them as-is so the skill becomes parameterizable.
        final argsMapping = <String, dynamic>{};
        for (final entry in stepArgs.entries) {
          argsMapping[entry.key] = entry.value;
        }

        toolSpecs.add({
          'name': stepToolName,
          'description': '步骤 ${i + 1}: 调用 $toolName',
          'schema': {
            'type': 'object',
            'properties': {},
          },
          'callTool': {
            'tool_name': toolName,
            'argsMapping': argsMapping,
          },
        });
      }

      // Build the JSON skill spec.
      final spec = <String, dynamic>{
        'id': name,
        'name': name,
        'description': desc,
        'version': '1.0.0',
        'idempotent': false,
        'tools': toolSpecs,
      };

      // Register as JsonSpecSkill.
      JsonSpecSkill newSkill;
      try {
        newSkill = JsonSpecSkill(spec);
      } catch (e, st) {
        return ToolResult.error('skill_create_from_trace 创建失败：$e\n$st');
      }

      skillManager.registerAvailable(newSkill);

      // Enable immediately.
      try {
        await skillManager.enable(name);
      } catch (e, st) {
        return ToolResult.error(
            'Skill 已注册但启用失败：$e\n$st。可用 skill_enable $name 手动启用。');
      }

      return ToolResult.ok(
        '✅ 已创建并启用 Skill「$name」（$desc），共 ${toolSpecs.length} 步工具调用。\n'
        '下次使用 skill_enable $name 即可启用，或 skill_disable $name 停用。\n'
        '用 skill_list 查看详情。',
      );
    },
  );
}
