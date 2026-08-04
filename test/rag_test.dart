// Tests for Direction 11: On-device RAG.
import 'package:flutter_test/flutter_test.dart';
import 'package:openagent/data/rag/embedding_service.dart';
import 'package:openagent/data/rag/vector_index.dart';
import 'package:openagent/data/rag/hybrid_retriever.dart';
import 'package:openagent/data/rag/knowledge_cache.dart';

void main() {
  group('EmbeddingService', () {
    test('embed returns correct dimension', () async {
      final s = EmbeddingService(config: const EmbeddingConfig(dimension: 384, normalize: true));
      expect((await s.embed('hello')).length, 384); s.dispose();
    });
    test('cosineSimilarity', () { expect(EmbeddingService.cosineSimilarity([1.0, 0.0], [1.0, 0.0]), closeTo(1.0, 0.001)); });
    test('cosineSimilarity orthogonal', () { expect(EmbeddingService.cosineSimilarity([1.0, 0.0], [0.0, 1.0]), closeTo(0.0, 0.001)); });
  });

  group('VectorIndex', () {
    test('empty index', () async { final idx = VectorIndex(dbPath: ':memory:'); await idx.initialize(); expect(await idx.search([0.1], topK: 5), isEmpty); await idx.close(); });
    test('add and search', () async {
      final idx = VectorIndex(dbPath: ':memory:'); await idx.initialize();
      await idx.addChunk(IndexedChunk(docId: 'd1', chunkIndex: 0, embedding: [0.1, 0.2], text: 'hello', sourceFile: 'a.txt'));
      expect(await idx.count(), 1); await idx.close();
    });
  });

  group('KeywordIndex', () {
    test('finds by keyword', () { final idx = KeywordIndex(); idx.addChunk('d1', 'machine learning', 'a.txt'); expect(idx.search('machine'), isNotEmpty); });
    test('no match', () { final idx = KeywordIndex(); idx.addChunk('d1', 'hello', 'a.txt'); expect(idx.search('xyz'), isEmpty); });
  });

  group('HybridRetriever', () {
    test('fuses results', () async {
      final vi = VectorIndex(dbPath: ':memory:'); await vi.initialize();
      await vi.addChunk(IndexedChunk(docId: 'd1', chunkIndex: 0, embedding: [0.1, 0.2], text: 'ml basics', sourceFile: 'a.txt'));
      final ki = KeywordIndex(); ki.addChunk('d1', 'ml basics', 'a.txt');
      final r = HybridRetriever(vectorIndex: vi, keywordIndex: ki);
      expect((await r.search('ml', topK: 5)).length, 1);
      await vi.close();
    });
  });

  group('KnowledgeCache', () {
    test('addHot', () async { final c = KnowledgeCache(cacheDir: '/tmp'); await c.initialize(); c.addHot(CachedDoc(docId: 'd1', fileName: 't.txt', sizeBytes: 100, lastAccessed: DateTime(2024, 1, 1), isHot: true)); expect(c.stats()['hot'], 1); await c.clear(); });
  });
}