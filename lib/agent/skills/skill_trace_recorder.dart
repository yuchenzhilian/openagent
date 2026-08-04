/// Enhanced trace recorder for skill creation.
import 'dart:convert';

class TraceStep { final String toolName; final Map<String, dynamic> args; final int timestamp; final String result; final int durationMs; const TraceStep({required this.toolName, required this.args, required this.timestamp, required this.result, required this.durationMs}); }
class TraceContext { final String appPackage, screenName; final int screenWidth, screenHeight; const TraceContext({required this.appPackage, required this.screenName, this.screenWidth = 1080, this.screenHeight = 2400}); }
class ExecutionTrace { final String id, name, description; final TraceContext context; final List<TraceStep> steps; final DateTime createdAt; ExecutionTrace({required this.id, required this.name, this.description = '', required this.context, required this.steps, DateTime? createdAt}) : createdAt = createdAt ?? DateTime.now(); }

class SkillTraceRecorder {
  final List<ExecutionTrace> _traces = [];
  ExecutionTrace? _currentTrace;

  void startTrace({required String name, String description = '', required TraceContext context}) {
    _currentTrace = ExecutionTrace(id: 'trace_${DateTime.now().millisecondsSinceEpoch}', name: name, description: description, context: context, steps: []);
  }

  void recordStep(TraceStep step) {
    if (_currentTrace == null) return;
    _currentTrace = ExecutionTrace(id: _currentTrace!.id, name: _currentTrace!.name, description: _currentTrace!.description, context: _currentTrace!.context, steps: [..._currentTrace!.steps, step], createdAt: _currentTrace!.createdAt);
  }

  ExecutionTrace? stopTrace() { final trace = _currentTrace; if (trace != null) _traces.add(trace); _currentTrace = null; return trace; }
  List<ExecutionTrace> getTraces() => List.unmodifiable(_traces);
  List<ExecutionTrace> findTraces(String name) => _traces.where((t) => t.name.contains(name)).toList();
  void deleteTrace(String id) { _traces.removeWhere((t) => t.id == id); }
  void clear() { _traces.clear(); _currentTrace = null; }
}