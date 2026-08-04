/// Skill synthesizer that generalizes from multiple execution traces.
import 'skill_trace_recorder.dart';

class SkillParameter {
  final String name, type, description;
  final String? defaultValue;
  const SkillParameter(
      {required this.name,
      required this.type,
      this.description = '',
      this.defaultValue});
}

class SkillTemplate {
  final String name, description;
  final List<SkillParameter> parameters;
  final List<Map<String, dynamic>> steps;
  const SkillTemplate(
      {required this.name,
      required this.description,
      required this.parameters,
      required this.steps});
}

class SkillSynthesizer {
  SkillTemplate? synthesize(String name, List<ExecutionTrace> traces) {
    if (traces.length < 2) return null;
    final aligned = _alignTraces(traces);
    if (aligned.isEmpty) return null;
    final parameters = _extractParameters(aligned, traces);
    final steps = _generateSteps(aligned, parameters);
    return SkillTemplate(
        name: name,
        description: '从 ${traces.length} 条轨迹合成的技能: $name',
        parameters: parameters,
        steps: steps);
  }

  List<List<TraceStep>> _alignTraces(List<ExecutionTrace> traces) {
    final toolSequences =
        traces.map((t) => t.steps.map((s) => s.toolName).toList()).toList();
    final lcs = _longestCommonSubsequence(toolSequences);
    return traces.map((trace) {
      final aligned = <TraceStep>[];
      int lcsIdx = 0;
      for (final step in trace.steps) {
        if (lcsIdx < lcs.length && step.toolName == lcs[lcsIdx]) {
          aligned.add(step);
          lcsIdx++;
        }
      }
      return aligned;
    }).toList();
  }

  List<String> _longestCommonSubsequence(List<List<String>> sequences) {
    if (sequences.isEmpty) return [];
    var result = sequences.first;
    for (int i = 1; i < sequences.length; i++)
      result = _lcsTwo(result, sequences[i]);
    return result;
  }

  List<String> _lcsTwo(List<String> a, List<String> b) {
    final m = a.length, n = b.length;
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
    for (int i = 1; i <= m; i++)
      for (int j = 1; j <= n; j++)
        dp[i][j] = a[i - 1] == b[j - 1]
            ? dp[i - 1][j - 1] + 1
            : (dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1]);
    final result = <String>[];
    int i = m, j = n;
    while (i > 0 && j > 0) {
      if (a[i - 1] == b[j - 1]) {
        result.insert(0, a[i - 1]);
        i--;
        j--;
      } else if (dp[i - 1][j] > dp[i][j - 1])
        i--;
      else
        j--;
    }
    return result;
  }

  List<SkillParameter> _extractParameters(
      List<List<TraceStep>> aligned, List<ExecutionTrace> traces) {
    final params = <SkillParameter>[];
    final seen = <String>{};
    for (int stepIdx = 0; stepIdx < aligned.first.length; stepIdx++) {
      final argKeys =
          aligned.map((t) => t[stepIdx].args.keys).expand((k) => k).toSet();
      for (final key in argKeys) {
        final values = aligned
            .map((t) => t[stepIdx].args[key])
            .where((v) => v != null)
            .toSet();
        if (values.length > 1 && !seen.contains(key)) {
          params.add(SkillParameter(
              name: key,
              type: values.first is int
                  ? 'integer'
                  : values.first is double
                      ? 'number'
                      : values.first is bool
                          ? 'boolean'
                          : 'string',
              description: '参数 $key'));
          seen.add(key);
        }
      }
    }
    return params;
  }

  List<Map<String, dynamic>> _generateSteps(
      List<List<TraceStep>> aligned, List<SkillParameter> params) {
    if (aligned.isEmpty) return [];
    final paramNames = params.map((p) => p.name).toSet();
    return aligned.first.map((step) {
      final generalizedArgs = <String, dynamic>{};
      for (final entry in step.args.entries) {
        generalizedArgs[entry.key] =
            paramNames.contains(entry.key) ? '{{${entry.key}}}' : entry.value;
      }
      return {'tool_name': step.toolName, 'args': generalizedArgs};
    }).toList();
  }
}
