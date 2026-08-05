/// Sliding window + summary cache for KV cache management.
class _CacheEntry {
  final String text;
  final DateTime timestamp;
  _CacheEntry({required this.text, required this.timestamp});
}

class SummaryEntry {
  final String summary;
  final DateTime timestamp;
  final int originalLength;
  const SummaryEntry({
    required this.summary,
    required this.timestamp,
    required this.originalLength,
  });
}

class SlidingWindowCache {
  SlidingWindowCache({this.windowSize = 2048, this.summaryCacheSize = 1024});

  /// Factory: create a cache sized for the device's memory capacity.
  /// Smaller windows reduce prefill latency on low-end devices.
  factory SlidingWindowCache.forDevice(int totalMemoryMb) {
    final windowSize = switch (totalMemoryMb) {
      >= 6144 => 2048,
      >= 4096 => 1024,
      _ => 512,
    };
    return SlidingWindowCache(windowSize: windowSize);
  }

  final int windowSize;
  final int summaryCacheSize;
  final List<_CacheEntry> _window = [];
  final List<SummaryEntry> _summaries = [];

  int _tokenEstimate(String text) => (text.length * 0.3).ceil();

  ({String windowText, String toSummarize}) add(String text) {
    final now = DateTime.now();
    _window.add(_CacheEntry(text: text, timestamp: now));
    int totalTokens = 0;
    for (final entry in _window) totalTokens += _tokenEstimate(entry.text);
    if (totalTokens <= windowSize) return (windowText: text, toSummarize: '');

    final toSummarize = StringBuffer();
    int removedTokens = 0;
    while (removedTokens < (totalTokens - windowSize) && _window.isNotEmpty) {
      final oldest = _window.removeAt(0);
      toSummarize.write(oldest.text);
      removedTokens += _tokenEstimate(oldest.text);
    }
    final summaryText = toSummarize.toString();
    _summaries.add(SummaryEntry(
      summary: summaryText.length > 200
          ? '${summaryText.substring(0, 200)}...'
          : summaryText,
      timestamp: now,
      originalLength: summaryText.length,
    ));
    while (_summaries.length > summaryCacheSize) _summaries.removeAt(0);
    return (
      windowText: _window.map((e) => e.text).join('\n'),
      toSummarize: summaryText
    );
  }

  String get windowContent => _window.map((e) => e.text).join('\n');
  List<SummaryEntry> get summaries => List.unmodifiable(_summaries);

  String get fullContext {
    final buf = StringBuffer();
    if (_summaries.isNotEmpty) {
      buf.writeln('[历史摘要]');
      for (final s in _summaries) buf.writeln(s.summary);
      buf.writeln('[/历史摘要]');
    }
    buf.write(windowContent);
    return buf.toString();
  }

  void reset() {
    _window.clear();
    _summaries.clear();
  }
}
