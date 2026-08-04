/// Vector memory backend with semantic search.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../../data/rag/embedding_service.dart';

class _MemoryValue {
  final String value; final DateTime createdAt, lastAccessAt; final int accessCount;
  _MemoryValue({required this.value, required this.createdAt, required this.lastAccessAt, required this.accessCount});
  _MemoryValue copyWith({DateTime? lastAccessAt}) => _MemoryValue(value: value, createdAt: createdAt, lastAccessAt: lastAccessAt ?? this.lastAccessAt, accessCount: accessCount);
}

class MemoryEntry { final String key; final String value; final DateTime createdAt, lastAccessedAt; final int accessCount; const MemoryEntry({required this.key, required this.value, required this.createdAt, required this.lastAccessedAt, required this.accessCount}); }

class MemoryScorer {
  double score(MemoryEntry entry) {
    double s = 0.3 * min(entry.accessCount / 100.0, 1.0);
    s += 0.4 * exp(-log(2) * DateTime.now().difference(entry.lastAccessedAt).inHours / 168);
    return s;
  }
}

class VectorMemoryBackend {
  VectorMemoryBackend({required String storagePath, EmbeddingService? embeddingService})
      : _storagePath = storagePath, _embeddingService = embeddingService ?? EmbeddingService();
  final String _storagePath;
  final EmbeddingService _embeddingService;
  final Map<String, _MemoryValue> _store = {};
  bool _loaded = false;
  final MemoryScorer _scorer = MemoryScorer();

  Future<void> initialize() async { if (_loaded) return; await _embeddingService.load(); await _loadFromFile(); _loaded = true; }

  Future<String?> get(String key) async {
    await initialize();
    if (_store.containsKey(key)) { _store[key] = _store[key]!.copyWith(lastAccessAt: DateTime.now()); return _store[key]!.value; }
    return null;
  }

  Future<void> set(String key, String value) async {
    await initialize();
    _store[key] = _MemoryValue(value: value, createdAt: DateTime.now(), lastAccessAt: DateTime.now(), accessCount: (_store[key]?.accessCount ?? 0) + 1);
    await _saveToFile();
  }

  Future<bool> delete(String key) async { await initialize(); final existed = _store.containsKey(key); _store.remove(key); if (existed) await _saveToFile(); return existed; }

  Future<List<({String key, String value, DateTime mtime})>> list({String prefix = '', int limit = 100}) async {
    await initialize();
    return _store.entries.where((e) => e.key.startsWith(prefix)).map((e) => (key: e.key, value: e.value.value, mtime: e.value.lastAccessAt)).toList()..sort((a, b) => b.mtime.compareTo(a.mtime))..take(limit);
  }

  Future<List<({String key, String value, double score})>> semanticSearch(String query, {int topK = 5}) async {
    await initialize(); if (_store.isEmpty) return [];
    final queryEmbedding = await _embeddingService.embed(query);
    final scored = <_ScoredEntry>[];
    for (final entry in _store.entries) {
      final valueEmbedding = await _embeddingService.embed(entry.value.value);
      final similarity = EmbeddingService.cosineSimilarity(queryEmbedding, valueEmbedding);
      scored.add(_ScoredEntry(entry.key, entry.value.value, similarity));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(topK).map((s) => (key: s.key, value: s.value, score: s.score)).toList();
  }

  Map<String, int> stats() => {'hot': _store.length, 'total': _store.length};

  Future<void> _loadFromFile() async {
    final file = File('$_storagePath/vector_memory.json'); if (!await file.exists()) return;
    try { final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      for (final entry in data.entries) { final v = entry.value as Map<String, dynamic>; _store[entry.key] = _MemoryValue(value: v['value'] as String? ?? '', createdAt: DateTime.tryParse(v['created_at'] as String? ?? '') ?? DateTime.now(), lastAccessAt: DateTime.tryParse(v['last_access_at'] as String? ?? '') ?? DateTime.now(), accessCount: v['access_count'] as int? ?? 0); }
    } catch (_) {}
  }

  Future<void> _saveToFile() async {
    final data = <String, dynamic>{};
    for (final entry in _store.entries) { data[entry.key] = {'value': entry.value.value, 'created_at': entry.value.createdAt.toIso8601String(), 'last_access_at': entry.value.lastAccessAt.toIso8601String(), 'access_count': entry.value.accessCount}; }
    await File('$_storagePath/vector_memory.json').writeAsString(jsonEncode(data));
  }

  void dispose() { _embeddingService.dispose(); }
}

class _ScoredEntry { final String key; final String value; final double score; _ScoredEntry(this.key, this.value, this.score); }