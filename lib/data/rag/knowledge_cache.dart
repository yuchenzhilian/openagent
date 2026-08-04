/// Knowledge base cache with hot/warm/cold tiering.
import 'dart:io';

class CachedDoc { final String docId, fileName; final int sizeBytes; final DateTime lastAccessed; final String? summary; final bool isHot; const CachedDoc({required this.docId, required this.fileName, required this.sizeBytes, required this.lastAccessed, this.summary, this.isHot = false}); }

class KnowledgeCache {
  KnowledgeCache({required String cacheDir}) : _cacheDir = Directory('$cacheDir/knowledge_cache');
  final Directory _cacheDir;
  final Map<String, CachedDoc> _hotCache = {};

  Future<void> initialize() async { if (!await _cacheDir.exists()) await _cacheDir.create(recursive: true); }
  Future<String?> get(String docId) async => _hotCache.containsKey(docId) ? docId : null;
  void addHot(CachedDoc doc) { _hotCache[doc.docId] = doc; if (_hotCache.length > 100) { final oldest = _hotCache.entries.first; _hotCache.remove(oldest.key); } }
  Map<String, int> stats() => {'hot': _hotCache.length};
  Future<void> clear() async { _hotCache.clear(); }
}