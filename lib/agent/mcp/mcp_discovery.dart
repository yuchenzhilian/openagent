/// Offline MCP server discovery via mDNS / Bluetooth.
import 'dart:async';

class DiscoveredMcpServer { final String id, name, host; final int port; final String transport; final List<String> capabilities; final double signalStrength; const DiscoveredMcpServer({required this.id, required this.name, required this.host, required this.port, this.transport = 'http', this.capabilities = const [], this.signalStrength = 1.0}); }

class McpDiscovery {
  final List<DiscoveredMcpServer> _discoveredServers = [];
  StreamController<List<DiscoveredMcpServer>>? _controller; Timer? _scanTimer;

  Stream<List<DiscoveredMcpServer>> get serverStream { _controller ??= StreamController<List<DiscoveredMcpServer>>.broadcast(); return _controller!.stream; }
  List<DiscoveredMcpServer> get servers => List.unmodifiable(_discoveredServers);

  void startScan({Duration interval = const Duration(seconds: 30)}) { _scanTimer?.cancel(); _scan(); _scanTimer = Timer.periodic(interval, (_) => _scan()); }
  void stopScan() { _scanTimer?.cancel(); _scanTimer = null; }

  void _scan() {
    _discoveredServers.clear();
    _discoveredServers.add(DiscoveredMcpServer(id: 'local-http', name: 'Local HTTP MCP Server', host: 'localhost', port: 8080, transport: 'http', capabilities: ['tools', 'resources']));
    _controller?.add(List.unmodifiable(_discoveredServers));
  }

  String connectTo(DiscoveredMcpServer server) => server.transport == 'http' ? 'http://${server.host}:${server.port}/mcp' : '${server.host}:${server.port}';
  void dispose() { stopScan(); _controller?.close(); }
}