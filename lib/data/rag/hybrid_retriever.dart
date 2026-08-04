/// Hybrid retriever combining semantic and keyword search via RRF fusion.
import 'vector_index.dart';

class HybridSearchResult {
  final String docId, text, sourceFile;
  final double semanticScore, keywordScore, combinedScore;
  const HybridSearchResult(
      {required this.docId,
      required this.text,
      required this.sourceFile,
      this.semanticScore = 0.0,
      this.keywordScore = 0.0,
      this.combinedScore = 0.0});
}

class KeywordIndex {
  final Map<String, List<_KWEntry>> _invertedIndex = {};
  void addChunk(String docId, String text, String sourceFile) {
    final tokens = _tokenize(text);
    final tf = <String, int>{};
    for (final token in tokens) tf[token] = (tf[token] ?? 0) + 1;
    for (final entry in tf.entries)
      _invertedIndex.putIfAbsent(entry.key, () => []).add(_KWEntry(
          docId: docId, text: text, sourceFile: sourceFile, freq: entry.value));
  }

  List<HybridSearchResult> search(String query, {int topK = 5}) {
    final tokens = _tokenize(query);
    final scores = <String, _KWS>{};
    for (final token in tokens) {
      final entries = _invertedIndex[token];
      if (entries == null) continue;
      for (final entry in entries) {
        scores.putIfAbsent(entry.docId, () => _KWS(entry.docId, 0.0, '', ''));
        scores[entry.docId]!.score += entry.freq.toDouble();
        scores[entry.docId]!.text = entry.text;
        scores[entry.docId]!.sourceFile = entry.sourceFile;
      }
    }
    final sorted = scores.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return sorted
        .take(topK)
        .map((s) => HybridSearchResult(
            docId: s.docId,
            text: s.text,
            sourceFile: s.sourceFile,
            keywordScore: s.score))
        .toList();
  }

  List<String> _tokenize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\u4e00-\u9fff]'), ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.length > 1)
      .toList();
}

class _KWEntry {
  final String docId, text, sourceFile;
  final int freq;
  _KWEntry(
      {required this.docId,
      required this.text,
      required this.sourceFile,
      required this.freq});
}

class _KWS {
  final String docId;
  double score;
  String text, sourceFile;
  _KWS(this.docId, this.score, this.text, this.sourceFile);
}

class HybridRetriever {
  HybridRetriever(
      {required VectorIndex vectorIndex,
      required KeywordIndex keywordIndex,
      this.rrfK = 60})
      : _vectorIndex = vectorIndex,
        _keywordIndex = keywordIndex;
  final VectorIndex _vectorIndex;
  final KeywordIndex _keywordIndex;
  final int rrfK;

  Future<List<HybridSearchResult>> search(String query,
      {List<double>? queryEmbedding, int topK = 5}) async {
    final semanticResults = queryEmbedding != null
        ? await _vectorIndex.search(queryEmbedding, topK: topK * 2)
        : <SearchResult>[];
    final keywordResults = _keywordIndex.search(query, topK: topK * 2);
    final docIds = <String>{};
    final fused = <HybridSearchResult>[];
    for (int i = 0; i < semanticResults.length; i++) {
      final r = semanticResults[i];
      final rr = 1.0 / (rrfK + i + 1);
      if (docIds.add(r.docId))
        fused.add(HybridSearchResult(
            docId: r.docId,
            text: r.text,
            sourceFile: r.sourceFile,
            semanticScore: rr,
            combinedScore: rr));
    }
    for (int i = 0; i < keywordResults.length; i++) {
      final r = keywordResults[i];
      final rr = 1.0 / (rrfK + i + 1);
      if (docIds.add(r.docId))
        fused.add(HybridSearchResult(
            docId: r.docId,
            text: r.text,
            sourceFile: r.sourceFile,
            keywordScore: rr,
            combinedScore: rr));
      else {
        final idx = fused.indexWhere((f) => f.docId == r.docId);
        if (idx >= 0)
          fused[idx] = HybridSearchResult(
              docId: r.docId,
              text: r.text,
              sourceFile: r.sourceFile,
              semanticScore: fused[idx].semanticScore,
              keywordScore: rr,
              combinedScore: fused[idx].semanticScore + rr);
      }
    }
    fused.sort((a, b) => b.combinedScore.compareTo(a.combinedScore));
    return fused.take(topK).toList();
  }
}
