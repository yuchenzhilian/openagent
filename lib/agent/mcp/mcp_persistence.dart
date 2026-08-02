// MCP connection persistence — optional meta-tools so the model can save and
// restore MCP connection ACROSS agent runs. Without these tools, every agent
// invocation (every user message) creates a new McpRegistry that dies at the
// end of the run.
//
// Two tools are provided:
//   * mcp_state_save  — snapshot all current MCP connections (server id +
//     transport kind + parameters) to a JSON file on disk. NOTE: this does
//     NOT pickle live sockets! stdio child processes are re-spawned on load;
//     HTTP endpoints are re-initialised.
//   * mcp_state_load  — read the JSON file, reconnect every server by
//     re-running initialize + tools/list, register the clients into the
//     current registry, and return a list of results (success/failure per
//     server).
//
// The model is the decision-maker for when to save/load; the code never does
// either automatically.
import 'dart:convert';
import 'dart:io';

import '../agent_runtime.dart';
import '../mcp/mcp_client.dart';

List<Tool> createMcpPersistenceTools(McpRegistry registry, String stateFilePath) {
  final file = () => File(stateFilePath);
  final out = <Tool>[];

  out.add(Tool(
    name: 'mcp_state_save',
    description: '【MCP 持久化 · 保存】把当前已连接的所有 MCP server 的连接参数（server_id + HTTP url/headers/timeout 或 stdio executable/args/env/cwd）写入一个本地 JSON 文件，下次新会话可用 mcp_state_load 重连。⚠ 不会保存 socket 句柄、也不保留已初始化之外的任何状态，load 时会重新跑 initialize + tools/list。⚠ 注意 stdio 模式下的可执行文件路径 + env/cwd 是原样落盘的，你自己判断是否包含敏感路径。',
    schema: const {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': '可选。保存的 JSON 文件绝对路径；留空=默认路径（由 app 初始化时指定，一般在 filesDir/mcp_state.json）。'},
      },
    },
    handler: (args) async {
      final p = ((args['path'] as String?)?.trim().isNotEmpty == true
          ? args['path'].toString()
          : stateFilePath);
      try {
        final servers = <Map<String, dynamic>>[];
        for (final e in registry.allClients.entries) {
          final t = e.value.transport;
          Map<String, dynamic> tp;
          if (t is HttpMcpTransport) {
            tp = {
              'kind': 'http',
              'url': t.url,
              'headers': t.headers,
              'timeout_sec': t.timeout.inSeconds,
            };
          } else if (t is StdioMcpTransport) {
            tp = {
              'kind': 'stdio',
              'executable': t.executable,
              'args': t.args,
              'env': t.environment,
              'cwd': t.workingDirectory,
            };
          } else {
            continue; // unknown transport — skip silently; this is why we have
            // explicit type checks instead of "else {}"
          }
          servers.add({
            'server_id': e.key,
            'transport': tp,
          });
        }
        final out = JsonEncoder.withIndent('  ').convert({'version': 1, 'servers': servers});
        final f = File(p);
        await f.parent.create(recursive: true);
        await f.writeAsString(out, flush: true);
        return ToolResult.ok('OK: saved ${servers.length} MCP connections to $p\n\n$out');
      } catch (e, st) {
        return ToolResult.error('mcp_state_save failed: $e\n$st');
      }
    },
  ));

  out.add(Tool(
    name: 'mcp_state_load',
    description: '【MCP 持久化 · 加载】从本地 JSON 文件里重放全部 MCP 连接（先断开当前同名连接 → 重新 create transport → initialize 握手 → tools/list → 注册进 McpRegistry）。逐个服务器返回成功/失败。',
    schema: const {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': '可选。读取的 JSON 文件路径；留空=默认路径。'},
        'only': {'type': 'array', 'items': {'type': 'string'}, 'description': '可选。只加载指定 server_id 列表；留空=全部加载。'},
        'disconnect_existing': {'type': 'boolean', 'description': '可选：true=遇到相同 server_id 先断开老的再重连（默认）；false=遇到重复 id 跳过老连接，使用当前已有的。'},
      },
    },
    handler: (args) async {
      final p = ((args['path'] as String?)?.trim().isNotEmpty == true
          ? args['path'].toString()
          : stateFilePath);
      final onlyRaw = args['only'] as List<dynamic>?;
      final only = onlyRaw == null ? null : Set<String>.from(onlyRaw.map((e) => e.toString()));
      final disconnectExisting = args['disconnect_existing'] != false;
      final f = file();
      if (!f.existsSync()) {
        return ToolResult.error('MCP state file not found: $p\n(Hint: call mcp_state_save at the end of a run first)');
      }
      final sb = StringBuffer();
      try {
        final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final servers = json['servers'] as List<dynamic>? ?? const [];
        var n = 0, ok = 0;
        for (final s in servers) {
          final m = s as Map<String, dynamic>;
          final sid = (m['server_id'] as String?).toString().trim();
          if (sid.isEmpty) continue;
          if (only != null && !only.contains(sid)) continue;
          n++;
          if (registry.find(sid) != null) {
            if (disconnectExisting) {
              await registry.unregister(sid);
              sb.writeln('[$sid] 断开旧连接');
            } else {
              sb.writeln('[$sid] SKIP (已存在同名连接且 disconnect_existing=false)');
              continue;
            }
          }
          final tp = m['transport'] as Map<String, dynamic>? ?? const {};
          final kind = (tp['kind'] as String?)?.toString();
          try {
            McpClient client;
            if (kind == 'http') {
              final url = (tp['url'] as String?).toString().trim();
              if (url.isEmpty) throw StateError('http url missing');
              final hRaw = tp['headers'] as Map<String, dynamic>? ?? const {};
              final headers = hRaw.map((k, v) => MapEntry(k.toString(), v.toString()));
              final ts = (tp['timeout_sec'] as int?) ?? 30;
              final transport = HttpMcpTransport(url, headers: headers, timeout: Duration(seconds: ts.clamp(1, 300)));
              client = McpClient(transport, serverId: sid);
            } else if (kind == 'stdio') {
              final exe = (tp['executable'] as String?).toString().trim();
              if (exe.isEmpty) throw StateError('stdio executable missing');
              final args2 = (tp['args'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList();
              final envRaw = tp['env'] as Map<String, dynamic>? ?? const {};
              final env = envRaw.map((k, v) => MapEntry(k.toString(), v.toString()));
              final cwd = tp['cwd'] as String?;
              final transport = await StdioMcpTransport.spawn(exe, args2, environment: env, workingDirectory: cwd);
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
            registry.register(client);
            ok++;
            sb.writeln('[$sid] OK: discovered ${tools.length} tools (${tools.map((e) => e.name).take(5).join(', ')}${tools.length > 5 ? '…' : ''})');
          } catch (e, st) {
            sb.writeln('[$sid] FAIL: $e');
            sb.writeln('    stack: $st');
          }
        }
        sb.writeln('\n总结：尝试 $n 个，成功 $ok 个，失败 ${n - ok} 个');
        return ToolResult.ok(sb.toString());
      } catch (e, st) {
        return ToolResult.error('mcp_state_load failed: $e\n$st\n\nPartial log:\n$sb');
      }
    },
  ));

  out.add(Tool(
    name: 'mcp_state_path',
    description: '打印当前 mcp_state_save/mcp_state_load 使用的默认文件路径，方便你检查文件位置或传给 path 参数覆盖。',
    schema: const {'type': 'object', 'properties': {}},
    handler: (_) async => ToolResult.ok('default_mcp_state_path = $stateFilePath\nFile exists = ${file().existsSync()}'),
  ));

  return out;
}
