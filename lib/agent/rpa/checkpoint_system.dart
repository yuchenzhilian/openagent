/// Checkpoint system for RPA operation chains.
class Checkpoint {
  final int stepIndex;
  final String description;
  final String? fallback;
  final List<String> onError;
  const Checkpoint(
      {required this.stepIndex,
      required this.description,
      this.fallback,
      this.onError = const []});
}

enum CheckpointResult { passed, failed, timeout }

class CheckpointSystem {
  final List<Checkpoint> _checkpoints = [];
  final Map<int, CheckpointResult> _results = {};

  void addCheckpoint(Checkpoint cp) {
    _checkpoints.add(cp);
  }

  void addCheckpointsForPlan(List<Map<String, dynamic>> steps) {
    for (int i = 0; i < steps.length; i++) {
      addCheckpoint(Checkpoint(
          stepIndex: i,
          description: 'Step ${i + 1}: ${steps[i]['name'] ?? 'unknown'}',
          fallback: 'retry_step_$i'));
    }
  }

  Future<CheckpointResult> verify(int stepIndex,
      {Future<String> Function()? getCurrentActivity,
      Future<List<String>> Function()? getVisibleElements}) async {
    final cp = _checkpoints.where((c) => c.stepIndex == stepIndex).lastOrNull;
    if (cp == null) return CheckpointResult.passed;
    try {
      final activity =
          getCurrentActivity != null ? await getCurrentActivity() : null;
      if (cp.fallback != null &&
          activity != null &&
          !activity.contains(cp.fallback!)) {
        _results[stepIndex] = CheckpointResult.failed;
        return CheckpointResult.failed;
      }
      _results[stepIndex] = CheckpointResult.passed;
      return CheckpointResult.passed;
    } catch (_) {
      _results[stepIndex] = CheckpointResult.timeout;
      return CheckpointResult.timeout;
    }
  }

  String? getFallback(int stepIndex) =>
      _checkpoints.where((c) => c.stepIndex == stepIndex).lastOrNull?.fallback;
  Map<int, CheckpointResult> get results => Map.unmodifiable(_results);
  void clear() {
    _checkpoints.clear();
    _results.clear();
  }
}
