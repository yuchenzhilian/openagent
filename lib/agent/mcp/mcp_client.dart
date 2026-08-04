// MCP (Model Context Protocol) client abstraction.
//
// Design principle (aligned with user rule of "no code-level interference"):
// - We only expose raw primitives: connect/disconnect/listTools/callTool.
// - We NEVER auto-connect to any MCP server, NEVER pre-register MCP tools.
// - The model decides, on a per-task basis, which MCP server to connect to
//   and which tools to use, via the mcp_connect / mcp_disconnect Agent tools.
//
// Transport support:
//   - HTTP (POST JSON-RPC 2.0 to arbitrary endpoint): most common for remote MCP
//   - Stdio (spawn local subprocess, JSON-RPC over stdin/stdout): optional local
//   Both conform to MCP spec (https://spec.modelcontextprotocol.io/)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Metadata of an MCP tool discovered from an MCP server.
class McpToolInfo {
  McpToolInfo({
    required this.name,
    required this.description,
    this.inputSchema = const {},
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'input_schema': inputSchema,
      };
}

/// Result of calling an MCP tool.
class McpCallResult {
  const McpCallResult.ok(this.content, {this.isError = false});
  const McpCallResult.error(this.content) : isError = true;

  final String content;
  final bool isError;
}

/// Abstract MCP transport.
abstract class McpTransport {
  Future<Map<String, dynamic>> sendJsonRpc(Map<String, dynamic> request);
  Future<void> close();
}

/// HTTP(S) transport — POSTs JSON-RPC 2.0 payloads to [baseUrl].
class HttpMcpTransport implements McpTransport {
  HttpMcpTransport(String baseUrl,
      {this.headers = const {}, this.timeout = const Duration(seconds: 30)})
      : url = baseUrl,
        baseUrl = baseUrl;

  final String baseUrl;

  /// Alias of [baseUrl], for consistency with mcp_persistence tools which read
  /// the field name `url` when serialising.
  final String url;

  final Map<String, String> headers;
  final Duration timeout;
  final HttpClient _client = HttpClient();

  int _nextId = 1;

  @override
  Future<Map<String, dynamic>> sendJsonRpc(Map<String, dynamic> request) async {
    final id = request['id'] ?? _nextId++;
    final payload = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      ...request,
    };
    final uri =
        Uri.parse(baseUrl.endsWith('/') ? '${baseUrl}mcp' : '$baseUrl/mcp');
    final req = await _client.postUrl(uri).timeout(timeout);
    headers.forEach((k, v) => req.headers.set(k, v));
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('Accept', 'application/json');
    req.add(utf8.encode(jsonEncode(payload)));
    final resp = await req.close().timeout(timeout);
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return {
        'jsonrpc': '2.0',
        'id': id,
        'error': {
          'code': resp.statusCode,
          'message': 'HTTP ${resp.statusCode}: $body',
        }
      };
    }
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      return {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': -32700, 'message': 'Parse error: $e. raw=$body'}
      };
    }
  }

  @override
  Future<void> close() async => _client.close();
}

/// Stdio transport — spawns a local process, speaks JSON-RPC over stdin/stdout.
///
/// NOTE: Because this uses dart:io Process, it works on desktop (dev host) and
/// also on Android in release builds (for locally bundled MCP servers shipped
/// as assets / binaries). The model picks args + executable; we don't restrict.
class StdioMcpTransport implements McpTransport {
  StdioMcpTransport._(
    this._process,
    this._stdoutLines, {
    required this.executable,
    required this.args,
    this.environment,
    this.workingDirectory,
  });

  final Process _process;
  final Stream<String> _stdoutLines;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  int _nextId = 1;
  bool _closed = false;

  /// Spawn-time snapshot so mcp_state_save can re-spawn this server on load.
  final String executable;
  final List<String> args;
  final Map<String, String>? environment;
  final String? workingDirectory;

  static Future<StdioMcpTransport> spawn(
    String executable,
    List<String> args, {
    Map<String, String>? environment,
    String? workingDirectory,
  }) async {
    final process = await Process.start(
      executable,
      args,
      environment: environment,
      workingDirectory: workingDirectory,
    );
    final stdoutLines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();
    final transport = StdioMcpTransport._(
      process,
      stdoutLines,
      executable: executable,
      args: List.unmodifiable(args),
      environment: environment == null ? null : Map.unmodifiable(environment),
      workingDirectory: workingDirectory,
    );
    transport._listen();
    return transport;
  }

  void _listen() {
    _stdoutLines.listen((line) {
      line = line.trim();
      if (line.isEmpty) return;
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        final id = json['id'];
        if (id is int) {
          final c = _pending.remove(id);
          c?.complete(json);
        }
      } catch (_) {
        // ignore non-JSON lines (e.g. server logging to stdout)
      }
    });
  }

  @override
  Future<Map<String, dynamic>> sendJsonRpc(Map<String, dynamic> request) async {
    if (_closed) {
      return {
        'jsonrpc': '2.0',
        'id': request['id'] ?? _nextId,
        'error': {'code': -32000, 'message': 'transport closed'}
      };
    }
    final id = request['id'] as int? ?? _nextId++;
    final payload = <String, dynamic>{'jsonrpc': '2.0', 'id': id, ...request};
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    try {
      _process.stdin.writeln(jsonEncode(payload));
      await _process.stdin.flush();
    } catch (e) {
      _pending.remove(id);
      return {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': -32000, 'message': 'stdin write failed: $e'}
      };
    }
    return completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        _pending.remove(id);
        return {
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': -32001, 'message': 'MCP call timed out (60s)'}
        };
      },
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final c in List.from(_pending.values)) {
      c.complete({
        'jsonrpc': '2.0',
        'id': 0,
        'error': {'code': -32000, 'message': 'transport closing'}
      });
    }
    _pending.clear();
    _process.stdin.close();
    _process.kill(ProcessSignal.sigterm);
    // ignore: unawaited_futures
    _process.exitCode.timeout(const Duration(seconds: 2), onTimeout: () {
      _process.kill(ProcessSignal.sigkill);
      return -1;
    });
  }
}

/// MCP client with initialize / tools/list / tools/call primitives.
class McpClient {
  McpClient(this.transport, {required this.serverId});

  final String serverId;
  final McpTransport transport;
  bool _initialized = false;

  /// Perform MCP initialize handshake. Required before other calls.
  /// Returns server info (name / version / capabilities) as raw map.
  Future<Map<String, dynamic>> initialize(
      {String clientName = 'openagent',
      String protocolVersion = '2024-11-05'}) async {
    final init = await transport.sendJsonRpc({
      'method': 'initialize',
      'params': {
        'protocolVersion': protocolVersion,
        'capabilities': {'tools': {}},
        'clientInfo': {'name': clientName, 'version': '1.0.0'},
      }
    });
    final err = init['error'];
    if (err != null) {
      return {'error': err.toString()};
    }
    final result = init['result'] as Map<String, dynamic>? ?? {};
    try {
      await transport.sendJsonRpc({'method': 'notifications/initialized'});
    } catch (_) {/* best-effort */}
    _initialized = true;
    return result;
  }

  bool get isInitialized => _initialized;

  /// tools/list — returns list of exposed tools.
  Future<List<McpToolInfo>> listTools() async {
    final resp = await transport
        .sendJsonRpc({'method': 'tools/list', 'params': <String, dynamic>{}});
    final err = resp['error'];
    if (err != null) return [];
    final result = resp['result'] as Map<String, dynamic>? ?? const {};
    final tools = result['tools'] as List<dynamic>? ?? const [];
    return tools
        .map((t) {
          final m = t as Map<String, dynamic>;
          return McpToolInfo(
            name: (m['name'] as String?) ?? '',
            description: (m['description'] as String?) ?? '',
            inputSchema:
                (m['inputSchema'] as Map<String, dynamic>?) ?? const {},
          );
        })
        .where((t) => t.name.isNotEmpty)
        .toList(growable: false);
  }

  /// tools/call — execute a tool.
  Future<McpCallResult> callTool(
      String toolName, Map<String, dynamic> arguments) async {
    final resp = await transport.sendJsonRpc({
      'method': 'tools/call',
      'params': {'name': toolName, 'arguments': arguments},
    });
    final err = resp['error'];
    if (err != null) {
      return McpCallResult.error('MCP error: ${err.toString()}');
    }
    final result = resp['result'] as Map<String, dynamic>? ?? const {};
    final isErr = result['isError'] == true;
    final content = (result['content'] as List<dynamic>? ?? const []).map((c) {
      if (c is Map) {
        final t = c['type'] as String?;
        if (t == 'text') return c['text']?.toString() ?? '';
        if (t == 'image')
          return '[image: ${(c['data'] as String?)?.substring(0, 20)}…]';
        if (t == 'resource')
          return c['text']?.toString() ?? c['uri']?.toString() ?? '';
      }
      return c.toString();
    }).join('\n');
    return isErr ? McpCallResult.error(content) : McpCallResult.ok(content);
  }

  Future<void> dispose() => transport.close();
}

/// In-memory registry: holds all currently-connected MCP clients.
///
/// The model adds/removes entries by calling mcp_connect / mcp_disconnect
/// Agent tools; we don't mutate this list on our own.
class McpRegistry {
  final _clients = <String, McpClient>{};

  Map<String, McpClient> get allClients => Map.unmodifiable(_clients);

  void register(McpClient client) => _clients[client.serverId] = client;

  McpClient? find(String serverId) => _clients[serverId];

  Future<McpClient?> unregister(String serverId) async {
    final c = _clients.remove(serverId);
    await c?.dispose();
    return c;
  }

  Future<void> disposeAll() async {
    for (final c in _clients.values.toList()) {
      await c.dispose();
    }
    _clients.clear();
  }
}
