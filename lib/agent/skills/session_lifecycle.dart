// Milestone #11: session lifecycle meta-tools.
//
// All 4 capabilities here are OPT-IN by the model. Code NEVER calls any of
// them automatically — the LLM decides when it wants to restore state, when
// it wants to mark certain skills as "remembered for next session", etc.
//
// Tools:
//   * skill_remember_enabled       — flip "remember_enabled" flag on skills
//                                    (save/load will honour it)
//   * skill_state_save             — persist json-skill specs + remembered ids
//   * skill_state_load             — re-register json-skill specs, optionally
//                                    re-enable the remembered ids in
//                                    dependency order
//   * skill_tools_manifest         — diagnostic: list all currently-registered
//                                    tools, grouped by owning skill, with
//                                    trimmed description & schema hint
//   * session_bootstrap            — ONE tool call to run the full restore
//                                    dance: load MCP state → load skill state
//                                    + enable remembered → optionally list
//                                    agent_memory KV prefix (so the model can
//                                    "reacquaint" itself with saved memory)
import 'dart:convert';
import 'dart:io';

import '../agent_runtime.dart';
import '../android_tools.dart';
import '../mcp/mcp_client.dart';
import 'skills.dart';

/// skill_state_save + skill_state_load
List<Tool> createSkillPersistenceTools(
    SkillManager skillManager, String statePath) {
  File file() => File(statePath);
  final out = <Tool>[];

  out.add(Tool(
    name: 'skill_state_save',
    description:
        '【Skills 持久化 · 保存】把当前 SkillManager 的状态写入 JSON 文件：(1) 所有通过 skill_register_json 动态注册的 JSON Skill 的完整 spec (2) 所有你用 skill_remember_enabled 打过『记住』标的 skill id 列表。\n注意：Dart 写死的内置 skill（android_rpa/builtin_math_time/knowledge_rag/…）不需要保存，每次会话代码层都会重新注册为 available，所以我们不浪费磁盘写它们。',
    schema: const {
      'type': 'object',
      'properties': {
        'path': {
          'type': 'string',
          'description': '可选。写入路径；留空=默认路径 baseDir/skill_state.json'
        },
        'include_remembered': {
          'type': 'boolean',
          'description':
              '可选，默认 true：是否把 remember_enabled=true 的 id 列表存盘。false=只存 JSON skill 本体。'
        },
      },
    },
    handler: (args) async {
      final p = ((args['path'] as String?)?.trim().isNotEmpty == true)
          ? args['path'].toString()
          : statePath;
      final includeRem = args['include_remembered'] != false;
      try {
        final snap = skillManager.snapshotState();
        final payload = <String, dynamic>{
          'version': snap['version'],
          'json_skill_specs': snap['json_skill_specs'],
          if (includeRem) 'remember_enabled': snap['remember_enabled'],
        };
        final str = JsonEncoder.withIndent('  ').convert(payload);
        final f = file();
        await f.parent.create(recursive: true);
        await f.writeAsString(str, flush: true);
        final n = (payload['json_skill_specs'] as List).length;
        final rem = (payload['remember_enabled'] as List?)?.length ?? 0;
        return ToolResult.ok(
            'OK: skill_state_save path=$p\n  • json skills saved : $n\n  • remember_enabled : $rem\n\nFull JSON:\n$str');
      } catch (e, st) {
        return ToolResult.error('skill_state_save failed: $e\n$st');
      }
    },
  ));

  out.add(Tool(
    name: 'skill_state_load',
    description:
        '【Skills 持久化 · 加载】从默认/指定 JSON 文件恢复 SkillManager 状态：重新 registerAvailable 每个 JSON skill spec，把 remember_enabled 打标（也可直接立刻启用它们）。\n注意：内置 skill（android_rpa 等）已由代码层自动 available = true，无需再从这里注入。',
    schema: const {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': '可选。读取路径；留空=默认。'},
        'enable_remembered': {
          'type': 'boolean',
          'description':
              '可选，默认 true：加载后是否按 dependencies 顺序自动 enable 所有 remember_enabled=true 的 skill。注意：如果它们依赖了 mcp_gateway 之类的 skill，会先 enable dependency 再 enable 自己。'
        },
      },
    },
    handler: (args) async {
      final p = ((args['path'] as String?)?.trim().isNotEmpty == true)
          ? args['path'].toString()
          : statePath;
      final f = file();
      if (!f.existsSync())
        return ToolResult.error('skill_state file not found: $p');
      try {
        final snap = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final enable = args['enable_remembered'] != false;
        final report = await skillManager.restoreJsonSkills(snap,
            enableRemembered: enable);
        return ToolResult.ok(
            'skill_state_load from $p (enable_remembered=$enable):\n\n$report');
      } catch (e, st) {
        return ToolResult.error('skill_state_load failed: $e\n$st');
      }
    },
  ));

  out.add(Tool(
    name: 'skill_state_path',
    description: '打印 skill_state_save / skill_state_load 默认文件路径。',
    schema: const {'type': 'object', 'properties': {}},
    handler: (_) async => ToolResult.ok(
        'default_skill_state_path = $statePath\nFile exists = ${file().existsSync()}'),
  ));

  return out;
}

/// skill_remember_enabled — flip the flag.
List<Tool> createSkillRememberTools(SkillManager skillManager) => [
      Tool(
        name: 'skill_remember_enabled',
        description:
            '给指定 skill id 打上『记住，下次会话 session_bootstrap 时我要你默认启用』的标记。注意：\n'
            '  • 标记是持久化的 (会写入 skill_state_save)，但只有你调用 skill_state_save 后才真正落盘；之后 session_bootstrap / skill_state_load(enable_remembered=true) 会按拓扑顺序自动启用它们。\n'
            '  • 传 remember=false 可取消标记。\n'
            '  • 支持 a,b,c 批量（英文逗号分隔）。\n'
            '这不是代码层的『自动启用』（违反我们的自主决策原则），而是你 (LLM) 显式告诉未来的你『这几个一般有用，下次先打开』——代码层只是尊重并执行你的历史决定。',
        schema: const {
          'type': 'object',
          'properties': {
            'skill_id': {
              'type': 'string',
              'description': '单个或批量 skill id（逗号分隔）。'
            },
            'remember': {
              'type': 'boolean',
              'description': 'true=打标记住；false=取消标记。默认 true。'
            },
          },
          'required': ['skill_id'],
        },
        handler: (args) async {
          final ids = (args['skill_id'] as String?)?.toString().trim() ?? '';
          final remember = args['remember'] != false;
          return ToolResult.ok(
              skillManager.setRemembered(ids, remember: remember));
        },
      ),
    ];

/// skill_tools_manifest — diagnostic tool.
List<Tool> createSkillToolsManifestTools(
    SkillManager skillManager, AgentRuntime runtime) {
  // We need to enumerate the currently-registered TOOLS. AgentRuntime doesn't
  // expose a list, so we go through SkillManager.toolIdsBySkill (for skill-
  // registered tools) + we can't easily tell about legacy pre-registered
  // tools. The manifest will be "best effort": skill-owned tools + we list
  // "skills X provided Y tools, not sure about others".
  //
  // To make it actually useful, we patch the SkillManager register callback
  // wrapper to ALSO maintain a (toolName -> Tool) map. Simpler: we augment
  // the manifest tool by asking `runtime` (but it doesn't expose the map).
  //
  // Cheapest reliable approach: maintain a parallel mirror inside this
  // function's closure — every tool-name we know went through a SkillManager
  // (which is most of them after this milestone). For legacy auto-registered
  // tools we add a comment explaining.
  final nameToSkill = <String, String>{};
  for (final e in skillManager.toolIdsBySkill.entries) {
    for (final name in e.value) nameToSkill[name] = e.key;
  }
  return [
    Tool(
      name: 'skill_tools_manifest',
      description:
          '【诊断 · 工具清单】列出当前 SkillManager 所拥有的所有 skill 及其已经成功注入的工具列表（含每个工具的描述 1 行 + JSON schema 摘要）。当你不确定某个 skill_enable 是否真的生效、或者某个工具名属于哪个 skill、或者你想确认自己是不是忘了启用某个 skill 时调这个。\n注意：此工具无法列出非 skill 方式、在代码层直接注册的 legacy 工具（如 calculator/datetime/text_statistics/knowledge_search 等每次都默认注册的）——那些会单独列一个『Legacy always-on tools』章节说明。',
      schema: const {
        'type': 'object',
        'properties': {
          'schema_hint': {
            'type': 'boolean',
            'description':
                '可选：是否在每个工具后面附 JSON schema 的超简短摘要（required+props 前 3 个）。默认 true。'
          },
          'max_desc_len': {
            'type': 'integer',
            'description': '可选：每个工具描述截断到多少字符。默认 120。0=不截断。'
          },
        },
      },
      handler: (args) async {
        final sb = StringBuffer();
        final bySkill = skillManager.toolIdsBySkill;
        if (bySkill.isEmpty) {
          sb.writeln(
              '(no skill has enabled any tools yet; run skill_enable <id> first, or open legacy auto-registered tools list below)');
        } else {
          for (final e in bySkill.entries) {
            final skillId = e.key;
            final tools = e.value;
            final skillObj =
                skillManager.listAll().cast<Map<String, dynamic>?>().firstWhere(
                      (m) => m!['id'] == skillId,
                      orElse: () => null,
                    );
            sb.writeln('╔══════════════════════════════════════════════════');
            sb.writeln('║ Skill id : $skillId');
            sb.writeln('║ name     : ${skillObj?['name']}');
            sb.writeln(
                '║ enabled  : ${skillObj?['enabled']}   remember_enabled=${skillObj?['remember_enabled']}');
            sb.writeln('║ tool #   : ${tools.length}');
            sb.writeln('╠──────────────────────────────────────────────────');
            for (final tname in tools) {
              sb.writeln('  • $tname');
            }
            sb.writeln('╚══════════════════════════════════════════════════\n');
          }
        }
        sb.writeln(
            '--- Legacy always-on tools (auto-registered every run, not owned by any Skill) ---');
        sb.writeln(
            '通常包含：calculator / datetime / text_statistics / knowledge_search');
        sb.writeln('以及用户 UI 开关打开时整包注入的 android_rpa 60+ 工具（legacy 兼容路径）。');
        sb.writeln(
            '如果你想确认某个 legacy 工具的描述/schema：可以直接调它传 schema 错误参数看看工具的 400 报错，或查源码 builtin_tools.dart / android_tools.dart。');
        return ToolResult.ok(sb.toString());
      },
    ),
    Tool(
      name: 'skills_manifest',
      description:
          '【诊断 · 技能清单】等价于 skill_list，但把 remember_enabled + registeredTools 两列默认展开展示，一眼看清现在的 skill 状态。',
      schema: const {'type': 'object', 'properties': {}},
      handler: (_) async {
        final all = skillManager.listAll();
        if (all.isEmpty) return const ToolResult.ok('(no skills)');
        final sb = StringBuffer();
        for (final s in all) {
          sb.write(
              '[${s['enabled'] == true ? '✓ ENABLED' : ' available'}] id=${s['id']}  v${s['version']}  remember=${s['remember_enabled']}  tools=${s['registeredTools']}  deps=${(s['dependencies'] as List).join(',')}');
          sb.writeln();
          sb.write('  name: ${s['name']}');
          sb.writeln();
        }
        return ToolResult.ok(sb.toString());
      },
    ),
  ];
}

/// session_bootstrap — the "start a new session and restore everything
/// I (the LLM) told myself last time I would want" single-call entry point.
List<Tool> createSessionBootstrapTools({
  required SkillManager skillManager,
  required McpRegistry mcpRegistry,
  required String mcpStatePath,
  required String skillStatePath,
  AgentMemoryBackend? memoryBackend,
  Map<String, dynamic>? extraInfo,
}) {
  final out = <Tool>[];
  // These tools are built to be composed; we expose each sub-step plus the
  // aggregate bootstrap entry.
  out.add(Tool(
    name: 'session_bootstrap',
    description: '【会话启动 · 一键恢复】把「我上次说想记住的 MCP/Skills/KV 前缀」都按顺序恢复：\n'
        '1) skill_state_load（重新注册 JSON skills + 按拓扑序 enable 所有 remember_enabled 的 skills）\n'
        '2) mcp_state_load（重新连接之前存盘的 MCP servers；如果某 server 已经连着就跳过）\n'
        '3) 可选：agent_memory list_keys，让你重新扫一眼自己存了哪些记忆 key（默认前缀 user: / task: / prefs:）\n'
        '⚠ 代码层不会在任何新会话自动调用这个工具，全靠你自己判断什么时候该恢复。\n⚠ 如果上一次你忘了调用 skill_state_save / mcp_state_save 落盘，那 restore 可能是空的 —— 正常的。',
    schema: const {
      'type': 'object',
      'properties': {
        'restore_mcp': {
          'type': 'boolean',
          'description': '默认 true：跑 mcp_state_load。false=跳过（如果你这次不想花时间重连 MCP）。'
        },
        'restore_skills': {
          'type': 'boolean',
          'description': '默认 true：跑 skill_state_load + enable_remembered。'
        },
        'enable_remembered': {
          'type': 'boolean',
          'description':
              '默认 true：restore_skills=true 时是否把 remember_enabled=true 的 skills 按依赖序自动启用。false=只重新打标，不启用。'
        },
        'scan_memory_prefixes': {
          'type': 'boolean',
          'description':
              '默认 true：扫 agent_memory 里的 3 类前缀，把它们的数量 / 前 2 个 key 列出来给你看，方便你回忆上次存了什么。',
        },
        'memory_prefixes': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              '可选。自定义要扫的 key 前缀。默认 ["user:","task:","prefs:","learned_ui:"]。',
        },
      },
    },
    handler: (args) async {
      final sb = StringBuffer();
      sb.writeln('╔═══════════════════════════════════════════════════');
      sb.writeln('║ session_bootstrap — restore start');
      sb.writeln('╚═══════════════════════════════════════════════════\n');

      final restoreSkills = args['restore_skills'] != false;
      final restoreMcp = args['restore_mcp'] != false;
      final enableRem = args['enable_remembered'] != false;
      final scanMem = args['scan_memory_prefixes'] != false;

      if (restoreSkills) {
        sb.writeln(
            '── step 1: skill_state_load (enable_remembered=$enableRem) ──');
        final f = File(skillStatePath);
        if (!f.existsSync()) {
          sb.writeln('SKIP: skill_state file not found: $skillStatePath');
        } else {
          try {
            final snap =
                jsonDecode(await f.readAsString()) as Map<String, dynamic>;
            sb.writeln(await skillManager.restoreJsonSkills(
              snap,
              enableRemembered: enableRem,
            ));
          } catch (e, st) {
            sb.writeln('ERROR: $e\n$st');
          }
        }
        sb.writeln('');
      }

      if (restoreMcp) {
        sb.writeln('── step 2: mcp_state_load (disconnect_existing=false) ──');
        final f = File(mcpStatePath);
        if (!f.existsSync()) {
          sb.writeln('SKIP: mcp_state file not found: $mcpStatePath');
        } else {
          try {
            // Re-use createMcpPersistenceTools 注册的 handler? Easier to copy
            // the minimal logic since tools here aren't registered yet for
            // callback access — just replay via the same code path.
            final json =
                jsonDecode(await f.readAsString()) as Map<String, dynamic>;
            final servers = json['servers'] as List<dynamic>? ?? const [];
            var n = 0, ok = 0;
            for (final s in servers) {
              final m = s as Map<String, dynamic>;
              final sid = (m['server_id'] as String?).toString().trim();
              if (sid.isEmpty) continue;
              n++;
              if (mcpRegistry.find(sid) != null) {
                sb.writeln('[$sid] SKIP: already connected');
                continue;
              }
              final tp = m['transport'] as Map<String, dynamic>? ?? const {};
              final kind = (tp['kind'] as String?)?.toString();
              try {
                McpClient client;
                if (kind == 'http') {
                  final url = (tp['url'] as String?).toString().trim();
                  if (url.isEmpty) throw StateError('http url missing');
                  final hRaw =
                      tp['headers'] as Map<String, dynamic>? ?? const {};
                  final headers =
                      hRaw.map((k, v) => MapEntry(k.toString(), v.toString()));
                  final ts = (tp['timeout_sec'] as int?) ?? 30;
                  final transport = HttpMcpTransport(url,
                      headers: headers,
                      timeout: Duration(seconds: ts.clamp(1, 300)));
                  client = McpClient(transport, serverId: sid);
                } else if (kind == 'stdio') {
                  final exe = (tp['executable'] as String?).toString().trim();
                  if (exe.isEmpty) throw StateError('stdio executable missing');
                  final args2 = (tp['args'] as List<dynamic>? ?? const [])
                      .map((e) => e.toString())
                      .toList();
                  final envRaw = tp['env'] as Map<String, dynamic>? ?? const {};
                  final env = envRaw
                      .map((k, v) => MapEntry(k.toString(), v.toString()));
                  final cwd = tp['cwd'] as String?;
                  final transport = await StdioMcpTransport.spawn(exe, args2,
                      environment: env, workingDirectory: cwd);
                  client = McpClient(transport, serverId: sid);
                } else {
                  sb.writeln('[$sid] SKIP unknown transport kind=$kind');
                  continue;
                }
                final info = await client.initialize();
                if (info.containsKey('error')) {
                  await client.dispose();
                  sb.writeln('[$sid] FAIL initialize: ${info['error']}');
                  continue;
                }
                final tools = await client.listTools();
                mcpRegistry.register(client);
                ok++;
                sb.writeln(
                    '[$sid] OK: discovered ${tools.length} tools (${tools.map((e) => e.name).take(5).join(', ')}${tools.length > 5 ? '…' : ''})');
              } catch (e, st) {
                sb.writeln('[$sid] FAIL: $e');
                sb.writeln('    stack: $st');
              }
            }
            sb.writeln('\nMCP 总结：尝试 $n 个，成功 $ok 个，失败 ${n - ok} 个');
          } catch (e, st) {
            sb.writeln('ERROR mcp_state_load inline: $e\n$st');
          }
        }
        sb.writeln('');
      }

      if (scanMem) {
        sb.writeln('── step 3: agent_memory prefix scan ──');
        final mem = memoryBackend;
        if (mem == null) {
          sb.writeln('SKIP: no memoryBackend supplied to bootstrap tools.');
        } else {
          final prefixes = (args['memory_prefixes'] as List<dynamic>? ??
                  const ['user:', 'task:', 'prefs:', 'learned_ui:'])
              .map((e) => e.toString())
              .toList();
          for (final p in prefixes) {
            final list = await mem.list(prefix: p, limit: 3);
            sb.writeln('  * prefix "$p" => ${list.length} keys (sample 3):');
            for (final x in list) {
              sb.writeln(
                  '      - ${x.key}  (last_modified=${x.mtime.toIso8601String()}  value preview=${x.value.substring(0, x.value.length > 60 ? 60 : x.value.length).replaceAll('\n', ' ')})');
            }
          }
        }
      }

      if (extraInfo != null && extraInfo.isNotEmpty) {
        sb.writeln('\n── extra runtime hints (passed by caller) ──');
        for (final e in extraInfo.entries) {
          sb.writeln('  ${e.key}: ${e.value}');
        }
      }

      sb.writeln('\n╔═══════════════════════════════════════════════════');
      sb.writeln('║ session_bootstrap — done. Now proceed with user task.');
      sb.writeln('╚═══════════════════════════════════════════════════');
      return ToolResult.ok(sb.toString());
    },
  ));
  return out;
}
