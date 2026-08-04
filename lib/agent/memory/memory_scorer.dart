/// Memory importance scorer.
import 'dart:math';

class MemoryScorerConfig {
  final double frequencyWeight;
  final double recencyWeight;
  final double semanticWeight;
  final int recencyHalfLifeHours;
  const MemoryScorerConfig({
    this.frequencyWeight = 0.3,
    this.recencyWeight = 0.4,
    this.semanticWeight = 0.3,
    this.recencyHalfLifeHours = 168,
  });
}

class MemoryEntry {
  final String key;
  final String value;
  final DateTime createdAt;
  final DateTime lastAccessedAt;
  final int accessCount;
  const MemoryEntry({
    required this.key,
    required this.value,
    required this.createdAt,
    required this.lastAccessedAt,
    required this.accessCount,
  });
}

class MemoryScorer {
  MemoryScorer({MemoryScorerConfig? config})
      : _config = config ?? MemoryScorerConfig();
  final MemoryScorerConfig _config;

  double score(MemoryEntry entry) {
    return _config.frequencyWeight * _frequencyScore(entry) +
        _config.recencyWeight * _recencyScore(entry) +
        _config.semanticWeight * _semanticScore(entry);
  }

  double _frequencyScore(MemoryEntry entry) {
    final hoursSinceCreation =
        DateTime.now().difference(entry.createdAt).inHours;
    if (hoursSinceCreation < 1) return 1.0;
    final freqPerHour = entry.accessCount / hoursSinceCreation;
    return min(freqPerHour / 4.0, 1.0);
  }

  double _recencyScore(MemoryEntry entry) {
    final hoursSinceAccess =
        DateTime.now().difference(entry.lastAccessedAt).inHours;
    return exp(-log(2) * hoursSinceAccess / _config.recencyHalfLifeHours);
  }

  double _semanticScore(MemoryEntry entry) {
    final lower = entry.value.toLowerCase();
    final keyLower = entry.key.toLowerCase();
    double score = 0.0;
    if (keyLower.startsWith('user:') || keyLower.startsWith('prefs:'))
      score += 0.3;
    if (keyLower.startsWith('learned_ui:')) score += 0.2;
    final importantKeywords = [
      'password',
      'token',
      'secret',
      'account',
      '密码',
      '账号'
    ];
    for (final kw in importantKeywords) {
      if (lower.contains(kw)) {
        score += 0.1;
        break;
      }
    }
    if (entry.value.length > 500) score += 0.1;
    return min(score, 1.0);
  }

  List<({MemoryEntry entry, double score})> scoreBatch(
      List<MemoryEntry> entries) {
    final scored = entries.map((e) => (entry: e, score: score(e))).toList();
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }
}
