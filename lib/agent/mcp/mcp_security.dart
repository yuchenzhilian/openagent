/// Capability-based MCP security model.
class McpCapability {
  final Set<String> allowedTools, allowedResources;
  final bool allowNetworkAccess, allowFileSystemAccess;
  final Duration maxExecutionTime; final int maxConcurrentCalls;
  const McpCapability({this.allowedTools = const {}, this.allowedResources = const {}, this.allowNetworkAccess = false, this.allowFileSystemAccess = false, this.maxExecutionTime = Duration(seconds: 30), this.maxConcurrentCalls = 1});
  bool allowsTool(String toolName) => allowedTools.isEmpty || allowedTools.contains(toolName);
  bool allowsResource(String resourceUri) => allowedResources.isEmpty || allowedResources.contains(resourceUri);
  McpCapability merge(McpCapability other) => McpCapability(allowedTools: {...allowedTools, ...other.allowedTools}, allowedResources: {...allowedResources, ...other.allowedResources}, allowNetworkAccess: allowNetworkAccess || other.allowNetworkAccess, allowFileSystemAccess: allowFileSystemAccess || other.allowFileSystemAccess, maxExecutionTime: maxExecutionTime > other.maxExecutionTime ? maxExecutionTime : other.maxExecutionTime, maxConcurrentCalls: maxConcurrentCalls > other.maxConcurrentCalls ? maxConcurrentCalls : other.maxConcurrentCalls);
}

class McpSecurityContext { final String serverId; final McpCapability capability; int _activeCalls = 0; McpSecurityContext({required this.serverId, required this.capability}); bool tryAcquireCall(String toolName) { if (!capability.allowsTool(toolName) || _activeCalls >= capability.maxConcurrentCalls) return false; _activeCalls++; return true; } void releaseCall() { if (_activeCalls > 0) _activeCalls--; } }

class McpSecurityManager {
  final Map<String, McpSecurityContext> _contexts = {};
  void registerServer(String serverId, McpCapability capability) { _contexts[serverId] = McpSecurityContext(serverId: serverId, capability: capability); }
  void unregisterServer(String serverId) { _contexts.remove(serverId); }
  bool checkAndAcquire(String serverId, String toolName) => _contexts[serverId]?.tryAcquireCall(toolName) ?? false;
  void releaseCall(String serverId) { _contexts[serverId]?.releaseCall(); }
  McpCapability? getCapability(String serverId) => _contexts[serverId]?.capability;
}