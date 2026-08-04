/// Skill version evolution and self-healing.
import 'dart:convert';
import 'dart:io';

class SkillVersion { final String version; final DateTime createdAt; final List<Map<String, dynamic>> steps; final double successRate; final int executionCount; const SkillVersion({required this.version, required this.createdAt, required this.steps, this.successRate = 1.0, this.executionCount = 0}); }

class SkillEvolution {
  final Map<String, List<SkillVersion>> _versions = {};

  void addVersion(String skillId, SkillVersion version) { _versions.putIfAbsent(skillId, () => []).add(version); }
  SkillVersion? getCurrentVersion(String skillId) { final versions = _versions[skillId]; return (versions == null || versions.isEmpty) ? null : versions.last; }
  List<SkillVersion> getVersions(String skillId) => List.unmodifiable(_versions[skillId] ?? []);

  SkillVersion? rollback(String skillId, String version) {
    final versions = _versions[skillId]; if (versions == null) return null;
    final idx = versions.indexWhere((v) => v.version == version); if (idx < 0) return null;
    _versions[skillId] = versions.sublist(0, idx + 1); return getCurrentVersion(skillId);
  }

  void recordSuccess(String skillId, String version) { _updateRate(skillId, version, true); }
  void recordFailure(String skillId, String version) { _updateRate(skillId, version, false); }

  void _updateRate(String skillId, String version, bool success) {
    final versions = _versions[skillId]; if (versions == null) return;
    final idx = versions.indexWhere((v) => v.version == version); if (idx < 0) return;
    final v = versions[idx]; final newCount = v.executionCount + 1;
    final newRate = ((v.successRate * v.executionCount) + (success ? 1.0 : 0.0)) / newCount;
    versions[idx] = SkillVersion(version: v.version, createdAt: v.createdAt, steps: v.steps, successRate: newRate, executionCount: newCount);
  }

  SkillVersion evolve(String skillId, List<Map<String, dynamic>> newSteps) {
    final current = getCurrentVersion(skillId);
    final versionNum = current != null ? '${double.parse(current.version) + 0.1}' : '1.0';
    final version = SkillVersion(version: versionNum, createdAt: DateTime.now(), steps: newSteps);
    addVersion(skillId, version); return version;
  }

  String? autoHeal(String skillId, {double threshold = 0.7}) {
    final current = getCurrentVersion(skillId); if (current == null || current.executionCount < 3 || current.successRate >= threshold) return null;
    final versions = _versions[skillId] ?? [];
    SkillVersion? best;
    for (final v in versions) { if (v.version == current.version) continue; if (best == null || v.successRate > best.successRate) best = v; }
    if (best != null && best.successRate > current.successRate) { rollback(skillId, best.version); return best.version; }
    return null;
  }

  Map<String, dynamic> toJson() => { for (final entry in _versions.entries) entry.key: entry.value.map((v) => ({'version': v.version, 'created_at': v.createdAt.toIso8601String(), 'steps': v.steps, 'success_rate': v.successRate, 'execution_count': v.executionCount})).toList() };

  Future<void> saveToFile(String path) async => File(path).writeAsString(jsonEncode(toJson()));

  static Future<SkillEvolution> loadFromFile(String path) async {
    final evolution = SkillEvolution(); final file = File(path); if (!await file.exists()) return evolution;
    try { final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>; for (final entry in data.entries) { for (final v in (entry.value as List).cast<Map<String, dynamic>>()) { evolution.addVersion(entry.key, SkillVersion(version: v['version'] as String? ?? '1.0', createdAt: DateTime.tryParse(v['created_at'] as String? ?? '') ?? DateTime.now(), steps: (v['steps'] as List?)?.cast<Map<String, dynamic>>() ?? [], successRate: (v['success_rate'] as num?)?.toDouble() ?? 1.0, executionCount: v['execution_count'] as int? ?? 0)); } } } catch (_) {}
    return evolution;
  }
}