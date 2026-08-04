/// Cross-session memory graph.
import 'dart:convert';
import 'dart:io';

class MemoryNode {
  final String key;
  final String value;
  final DateTime timestamp;
  double importance;
  MemoryNode({required this.key, required this.value, required this.timestamp, this.importance = 0.5});

  Map<String, dynamic> toJson() => {'key': key, 'value': value, 'timestamp': timestamp.toIso8601String(), 'importance': importance};
  factory MemoryNode.fromJson(Map<String, dynamic> j) => MemoryNode(
    key: j['key'] as String, value: j['value'] as String? ?? '',
    timestamp: DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
    importance: (j['importance'] as num?)?.toDouble() ?? 0.5,
  );
}

enum EdgeType { reference, temporal, semantic }

class MemoryEdge {
  final String sourceKey;
  final String targetKey;
  final EdgeType type;
  final double weight;
  const MemoryEdge({required this.sourceKey, required this.targetKey, required this.type, this.weight = 1.0});
}

class MemoryGraph {
  final Map<String, MemoryNode> _nodes = {};
  final List<MemoryEdge> _edges = [];

  void addNode(MemoryNode node) { _nodes[node.key] = node; }
  MemoryNode? getNode(String key) => _nodes[key];
  void removeNode(String key) { _nodes.remove(key); _edges.removeWhere((e) => e.sourceKey == key || e.targetKey == key); }

  void addEdge(MemoryEdge edge) {
    if (!_nodes.containsKey(edge.sourceKey) || !_nodes.containsKey(edge.targetKey)) return;
    _edges.add(edge);
  }

  void addReferenceEdges() {
    for (final source in _nodes.values) {
      for (final target in _nodes.values) {
        if (source.key == target.key) continue;
        if (source.value.contains(target.key)) {
          addEdge(MemoryEdge(sourceKey: source.key, targetKey: target.key, type: EdgeType.reference));
        }
      }
    }
  }

  void addTemporalEdges({int windowMinutes = 5}) {
    final entries = _nodes.values.toList();
    for (int i = 0; i < entries.length; i++) {
      for (int j = i + 1; j < entries.length; j++) {
        final diff = entries[i].timestamp.difference(entries[j].timestamp).inMinutes.abs();
        if (diff <= windowMinutes) {
          addEdge(MemoryEdge(sourceKey: entries[i].key, targetKey: entries[j].key, type: EdgeType.temporal, weight: 1.0 - (diff / windowMinutes)));
        }
      }
    }
  }

  List<MemoryNode> findRelated(String query, {int maxDepth = 2, int maxResults = 10}) {
    final visited = <String>{};
    final results = <MemoryNode>[];
    if (_nodes.containsKey(query)) { _traverse(query, visited, results, maxDepth: maxDepth, maxResults: maxResults); return results; }
    final prefixMatches = _nodes.keys.where((k) => k.contains(query)).toList();
    for (final key in prefixMatches) { _traverse(key, visited, results, maxDepth: maxDepth, maxResults: maxResults); if (results.length >= maxResults) break; }
    results.sort((a, b) => b.importance.compareTo(a.importance));
    return results.take(maxResults).toList();
  }

  void _traverse(String key, Set<String> visited, List<MemoryNode> results, {required int maxDepth, required int maxResults, int depth = 0}) {
    if (depth > maxDepth || results.length >= maxResults || visited.contains(key)) return;
    visited.add(key);
    final node = _nodes[key]; if (node == null) return;
    results.add(node);
    for (final edge in _edges.where((e) => e.sourceKey == key)) { _traverse(edge.targetKey, visited, results, maxDepth: maxDepth, maxResults: maxResults, depth: depth + 1); }
    for (final edge in _edges.where((e) => e.targetKey == key)) { _traverse(edge.sourceKey, visited, results, maxDepth: maxDepth, maxResults: maxResults, depth: depth + 1); }
  }

  Map<String, dynamic> toJson() => {'nodes': _nodes.values.map((n) => n.toJson()).toList(), 'edges': _edges.map((e) => ({'source_key': e.sourceKey, 'target_key': e.targetKey, 'type': e.type.name, 'weight': e.weight})).toList()};

  factory MemoryGraph.fromJson(Map<String, dynamic> j) {
    final graph = MemoryGraph();
    for (final n in (j['nodes'] as List? ?? [])) { if (n is Map<String, dynamic>) graph.addNode(MemoryNode.fromJson(n)); }
    for (final e in (j['edges'] as List? ?? [])) { if (e is Map<String, dynamic>) graph._edges.add(MemoryEdge(sourceKey: e['source_key'] as String? ?? '', targetKey: e['target_key'] as String? ?? '', type: EdgeType.values.firstWhere((t) => t.name == e['type'], orElse: () => EdgeType.reference), weight: (e['weight'] as num?)?.toDouble() ?? 1.0)); }
    return graph;
  }

  Future<void> saveToFile(String path) async => File(path).writeAsString(jsonEncode(toJson()));
  static Future<MemoryGraph> loadFromFile(String path) async {
    final file = File(path); if (!await file.exists()) return MemoryGraph();
    return MemoryGraph.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
  }

  int get nodeCount => _nodes.length;
  int get edgeCount => _edges.length;
}