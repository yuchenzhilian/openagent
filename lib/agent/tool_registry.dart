// Unified tool registry: abstracts platform-specific tool factories behind
// a common interface so chat_page.dart doesn't scatter platform conditionals.
//
// Design:
// - PlatformToolFactory: each platform (Android, iOS, Web) implements this.
//   The factory decides whether it's supported, builds its tools, and
//   provides graceful degradation stubs for the OTHER platform's tools.
// - ToolFactoryContext: carries shared dependencies (vision analyze, memory
//   backend, execute callback) so factory signatures stay uniform.
// - createPlatformTools(): the single entry point chat_page calls instead
//   of branching on Platform.isAndroid / isIOS.

import 'agent_runtime.dart';
import 'android_tools.dart';
import 'ios_tools.dart';
import '../data/services/android_automation_service.dart';
import '../data/services/ios_automation_service.dart';

/// Shared dependencies passed to all platform tool factories.
///
/// Android factories use all fields; iOS/Web factories use a subset.
/// This avoids 4-argument factory functions with different signatures.
class ToolFactoryContext {
  const ToolFactoryContext({
    this.androidService,
    this.iosService,
    this.visionAnalyze,
    this.executeCallback,
    this.memoryBackend,
  });

  final AndroidAutomationService? androidService;
  final IosAutomationService? iosService;
  final Future<String> Function(String imagePath, String prompt)? visionAnalyze;
  final Future<ToolResult> Function(String name, Map<String, dynamic> args)?
      executeCallback;
  final AgentMemoryBackend? memoryBackend;
}

/// A platform-specific tool factory.
///
/// Each platform implements this to:
/// 1. Report whether it's supported ([isSupported]).
/// 2. Build its native tools ([buildTools]).
/// 3. Provide degradation stubs for tools from OTHER platforms
///    ([buildDegradationTools]) so the Agent gets a helpful message
///    instead of a silent failure or missing tool.
abstract class PlatformToolFactory {
  /// Whether this factory's tools are available on the current platform.
  bool get isSupported;

  /// Human-readable platform name (e.g. "Android", "iOS").
  String get platformName;

  /// Build and return this platform's native tools.
  ///
  /// Returns an empty list if [isSupported] is false.
  List<Tool> buildTools(ToolFactoryContext ctx);

  /// Build degradation stubs for this platform's tools, to be registered
  /// on OTHER platforms so the Agent gets a "not available" message
  /// instead of a missing tool.
  ///
  /// Returns an empty list if [isSupported] is true (no stubs needed
  /// on the native platform).
  List<Tool> buildDegradationTools();
}

// ---------------------------------------------------------------------------
// Android factory
// ---------------------------------------------------------------------------

class AndroidToolFactory extends PlatformToolFactory {
  @override
  bool get isSupported =>
      androidService?.isSupported ??
      AndroidAutomationService.instance.isSupported;

  @override
  String get platformName => 'Android';

  @override
  List<Tool> buildTools(ToolFactoryContext ctx) {
    final s = ctx.androidService ?? AndroidAutomationService.instance;
    if (!s.isSupported) return const [];
    return createAndroidAutomationTools(
      service: s,
      visionAnalyze: ctx.visionAnalyze,
      executeCallback: ctx.executeCallback,
      memoryBackend: ctx.memoryBackend,
    );
  }

  @override
  List<Tool> buildDegradationTools() {
    if (isSupported) return const [];
    // On non-Android platforms, register stubs for the most commonly
    // attempted Android tools so the Agent gets a clear message.
    return [
      _unsupportedTool(
        name: 'android_open_app',
        description: '打开 Android App（仅 Android 可用）',
        platform: 'Android',
      ),
      _unsupportedTool(
        name: 'android_click_by_text',
        description: '点击屏幕文字（仅 Android 可用）',
        platform: 'Android',
      ),
      _unsupportedTool(
        name: 'android_screenshot',
        description: '截屏（仅 Android 可用）',
        platform: 'Android',
      ),
      _unsupportedTool(
        name: 'android_dump_ui',
        description: '获取 UI 层级（仅 Android 可用）',
        platform: 'Android',
      ),
    ];
  }

  AndroidAutomationService? get androidService =>
      AndroidAutomationService.instance;
}

// ---------------------------------------------------------------------------
// iOS factory
// ---------------------------------------------------------------------------

class IosToolFactory extends PlatformToolFactory {
  @override
  bool get isSupported =>
      iosService?.isSupported ?? IosAutomationService.instance.isSupported;

  @override
  String get platformName => 'iOS';

  @override
  List<Tool> buildTools(ToolFactoryContext ctx) {
    final s = ctx.iosService ?? IosAutomationService.instance;
    if (!s.isSupported) return const [];
    return createIosAutomationTools(service: s);
  }

  @override
  List<Tool> buildDegradationTools() {
    if (isSupported) return const [];
    return [
      _unsupportedTool(
        name: 'ios_shortcut_donate',
        description: '注册 Siri 快捷指令（仅 iOS 可用）',
        platform: 'iOS',
      ),
      _unsupportedTool(
        name: 'ios_open_app',
        description: '打开 iOS App（仅 iOS 可用）',
        platform: 'iOS',
      ),
      _unsupportedTool(
        name: 'ios_live_activity_start',
        description: '启动 Live Activity（仅 iOS 16.1+ 可用）',
        platform: 'iOS',
      ),
    ];
  }

  IosAutomationService? get iosService => IosAutomationService.instance;
}

// ---------------------------------------------------------------------------
// Helper: create a degradation stub tool
// ---------------------------------------------------------------------------

/// Creates a tool that always returns a "not available on this platform"
/// message. Registered on platforms where the real tool is unavailable so
/// the Agent gets actionable feedback instead of a missing-tool error.
Tool _unsupportedTool({
  required String name,
  required String description,
  required String platform,
}) {
  return Tool(
    name: name,
    description: description,
    schema: {'type': 'object', 'properties': {}},
    handler: (args) async {
      return ToolResult.error(
        '当前功能仅在 $platform 平台可用，当前平台不支持此操作。'
        '请考虑使用跨平台替代方案（如 web_automate 进行网页版自动化）。',
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Unified entry point
// ---------------------------------------------------------------------------

/// All registered platform tool factories, in priority order.
final List<PlatformToolFactory> platformToolFactories = [
  AndroidToolFactory(),
  IosToolFactory(),
];

/// Build all platform tools for the current runtime.
///
/// On Android: returns Android tools + iOS degradation stubs.
/// On iOS: returns iOS tools + Android degradation stubs.
/// On other: returns degradation stubs for both.
///
/// This is the single entry point chat_page.dart should call instead of
/// branching on Platform.isAndroid / isIOS.
List<Tool> createPlatformTools(ToolFactoryContext ctx) {
  final tools = <Tool>[];
  for (final factory in platformToolFactories) {
    tools.addAll(factory.buildTools(ctx));
    tools.addAll(factory.buildDegradationTools());
  }
  return tools;
}
