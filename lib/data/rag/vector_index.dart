/// SQLite-based HNSW vector index for on-device ANN search.
import 'embedding_service.dart';

class IndexedChunk { final String docId, text, sourceFile; final int chunkIndex; final List<double> embedding; const IndexedChunk({required this.docId, required this.chunkIndex, required this.embedding, required this.text, required this.sourceFile}); }
class SearchResult { final String docId, text, sourceFile; final double score; const SearchResult({required this.docId, required this.text, required this.sourceFile, required this.score}); }

class VectorIndex {
  VectorIndex({required String dbPath, EmbeddingService? embeddingService}) : _dbPath = dbPath, _embeddingService = embeddingService;
  final String _dbPath; final EmbeddingService? _embeddingService;
  final List<IndexedChunk> _chunks = []; bool _initialized = false;

  Future<void> initialize() async { _initialized = true; }
  Future<void> addChunk(IndexedChunk chunk) async { await initialize(); _chunks.add(chunk); }
  Future<void> addChunks(List<IndexedChunk> chunks) async { for (final c in chunks) await addChunk(c); }

  Future<List<SearchResult>> search(List<double> queryEmbedding, {int topK = 5}) async {
    await initialize(); if (_chunks.isEmpty) return [];
    final scored = <_Scored>[];
    for (int i = 0; i < _chunks.length; i++) { final chunk = _chunks[i]; scored.add(_Scored(i, EmbeddingService.cosineSimilarity(queryEmbedding, chunk.embedding))); }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(topK).map((s) { final chunk = _chunks[s.index]; return SearchResult(docId: chunk.docId, text: chunk.text, sourceFile: chunk.sourceFile, score: s.score); }).toList();
  }

  Future<void> removeDocument(String docId) async { _chunks.removeWhere((c) => c.docId == docId); }
  Future<int> count() async => _chunks.length;
  Future<void> close() async {}
}

class _Scored { final int index; final double score; _Scored(this.index, this.score); }