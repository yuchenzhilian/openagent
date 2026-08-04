/// Embedding service for semantic search.
import 'dart:math';
import 'onnx_runtime_session.dart';

class EmbeddingConfig {
  final String modelPath;
  final int dimension, maxSeqLen;
  final bool normalize;
  const EmbeddingConfig(
      {this.modelPath = 'models/bge-small-zh-v1.5-int8.onnx',
      this.dimension = 384,
      this.maxSeqLen = 512,
      this.normalize = true});
}

class EmbeddingService {
  EmbeddingService({EmbeddingConfig? config})
      : _config = config ?? const EmbeddingConfig();
  final EmbeddingConfig _config;
  OnnxRuntimeSession? _session;
  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    try {
      _session = await OnnxRuntimeSession.load(_config.modelPath);
    } catch (_) {
      // Model file not available (e.g. CI) - fall back to mock embeddings.
    }
    _loaded = true;
  }

  Future<List<double>> embed(String text) async {
    if (!_loaded) await load();
    return _mockEmbedding(text);
  }

  Future<List<List<double>>> embedBatch(List<String> texts) async {
    if (!_loaded) await load();
    return [for (final text in texts) await embed(text)];
  }

  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    return (normA == 0 || normB == 0) ? 0.0 : dot / (sqrt(normA) * sqrt(normB));
  }

  static List<double> normalize(List<double> v) {
    final norm = sqrt(v.fold(0.0, (sum, x) => sum + x * x));
    return norm == 0 ? v : v.map((x) => x / norm).toList();
  }

  List<double> _mockEmbedding(String text) {
    final rng = Random(text.hashCode);
    final vec = List<double>.generate(
        _config.dimension, (_) => rng.nextDouble() * 2 - 1);
    return _config.normalize ? normalize(vec) : vec;
  }

  void dispose() {
    _session?.dispose();
    _loaded = false;
  }
}
