/// Finite state machine for App UI flows.
class ScreenState {
  final String name;
  final String? activity;
  final List<String> uiElements;
  const ScreenState(
      {required this.name, this.activity, this.uiElements = const []});
}

class Transition {
  final String from, to, action;
  final double probability;
  const Transition(
      {required this.from,
      required this.to,
      required this.action,
      this.probability = 1.0});
}

class AppStateMachine {
  AppStateMachine({required this.appPackage});
  final String appPackage;
  final Map<String, ScreenState> _screens = {};
  final List<Transition> _transitions = [];
  ScreenState? currentState;

  void addScreen(ScreenState screen) {
    _screens[screen.name] = screen;
  }

  void addTransition(Transition transition) {
    _transitions.add(transition);
  }

  Future<ScreenState?> inferCurrentState(
      {String? currentActivity, List<String>? visibleElements}) async {
    for (final screen in _screens.values) {
      if (screen.activity != null &&
          currentActivity != null &&
          !currentActivity.contains(screen.activity!)) continue;
      if (screen.uiElements.isNotEmpty && visibleElements != null) {
        final matches = screen.uiElements
            .where((e) => visibleElements.any((v) => v.contains(e)))
            .length;
        if (matches < (screen.uiElements.length * 0.5)) continue;
      }
      currentState = screen;
      return screen;
    }
    return null;
  }

  List<String> pathTo(ScreenState target) {
    if (currentState == null) return ['回到桌面', '重新打开 $appPackage'];
    final visited = <String>{currentState!.name};
    final queue = [currentState!.name];
    final parent = <String, String>{};
    final action = <String, String>{};
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (current == target.name) {
        final path = <String>[];
        var node = target.name;
        while (node != currentState!.name) {
          path.insert(0, action[node]!);
          node = parent[node]!;
        }
        return path;
      }
      for (final t in _transitions) {
        if (t.from == current && !visited.contains(t.to)) {
          visited.add(t.to);
          queue.add(t.to);
          parent[t.to] = current;
          action[t.to] = t.action;
        }
      }
    }
    return ['尝试返回桌面', '重新打开 $appPackage'];
  }

  List<Transition> possibleTransitions() => currentState == null
      ? []
      : _transitions.where((t) => t.from == currentState!.name).toList();
  void learnTransition(String from, String to, String action) {
    _transitions.removeWhere((t) => t.from == from && t.to == to);
    _transitions.add(Transition(from: from, to: to, action: action));
  }

  List<String> get screenNames => _screens.keys.toList();
  List<Transition> get transitions => List.unmodifiable(_transitions);
}
