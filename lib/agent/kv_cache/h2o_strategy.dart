/// H2O (Heavy Hitter Oracle) KV cache eviction strategy.
import 'dart:math';

class H2OConfig {
  final int checkInterval;
  final int maxHeavyHitters;
  final int slidingWindowSize;
  const H2OConfig({
    this.checkInterval = 5,
    this.maxHeavyHitters = 1024,
    this.slidingWindowSize = 512,
  });
}

class H2OStrategy {
  H2OStrategy({H2OConfig? config}) : _config = config ?? H2OConfig();
  final H2OConfig _config;
  int _round = 0;
  final List<int> _heavyHitterIndices = [];

  List<int> selectTokensToKeep(List<double> attentionScores, int totalTokens) {
    _round++;
    if (_round % _config.checkInterval != 0) {
      return _getCurrentKeepSet(totalTokens);
    }
    final scored = <_IndexedScore>[];
    for (int i = 0; i < attentionScores.length && i < totalTokens; i++) {
      final score = attentionScores[i];
      final recencyBonus = (i > totalTokens - _config.slidingWindowSize) ? 0.5 : 0.0;
      scored.add(_IndexedScore(i, score + recencyBonus));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    final keepSet = <int>{};
    for (int i = 0; i < _config.maxHeavyHitters && i < scored.length; i++) {
      keepSet.add(scored[i].index);
    }
    for (int i = totalTokens - _config.slidingWindowSize; i < totalTokens; i++) {
      if (i >= 0) keepSet.add(i);
    }
    final sorted = keepSet.toList()..sort();
    _heavyHitterIndices.clear();
    _heavyHitterIndices.addAll(sorted);
    return sorted;
  }

  List<int> _getCurrentKeepSet(int totalTokens) {
    final keepSet = <int>{..._heavyHitterIndices};
    for (int i = totalTokens - _config.slidingWindowSize; i < totalTokens; i++) {
      if (i >= 0) keepSet.add(i);
    }
    return keepSet.toList()..sort();
  }

  void reset() { _round = 0; _heavyHitterIndices.clear(); }
}

class _IndexedScore {
  final int index;
  final double score;
  _IndexedScore(this.index, this.score);
}