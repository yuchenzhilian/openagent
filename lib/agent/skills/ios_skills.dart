// iOS Shortcuts Skill - exposes Siri Shortcuts integration tools.
//
// This skill is only available on iOS (Platform.isIOS). When enabled,
// it registers the Shortcuts-related tools so the Agent can donate,
// list, trigger, and delete Siri Shortcuts.
import '../agent_runtime.dart';
import '../ios_tools.dart';
import 'skills.dart';

/// Skill: `ios_shortcuts` - Siri Shortcuts integration on iOS.
///
/// The model enables this when the user task involves registering voice
/// commands, triggering system actions (call/SMS/maps), or managing
/// shortcuts. iOS has no AccessibilityService, so this is the primary
/// "system-level automation" surface.
class IosShortcutsSkill extends Skill {
  IosShortcutsSkill({this.service});

  final dynamic service;

  @override
  String get id => 'ios_shortcuts';
  @override
  String get name => 'iOS Shortcuts Integration';
  @override
  String get description => 'iOS 快捷指令集成：注册 Siri 语音快捷指令（shortcut_donate）、列出已注册指令'
      '（shortcut_list）、通过 URL scheme 触发系统操作如拨打电话/发送短信/打开地图'
      '（shortcut_trigger）、打开 URL 或第三方 App（open_url/open_app）。'
      'iOS 上 Agent 触发系统级自动化的主要方式。用户提到"Siri"、"快捷指令"、'
      '"打电话"、"发短信"、"打开 App"时可启用。';

  @override
  Future<void> onEnable(void Function(Tool) registerTool) async {
    final tools = createIosAutomationTools(service: service);
    final shortcutIds = {
      'ios_shortcut_donate',
      'ios_shortcut_list',
      'ios_shortcut_trigger',
      'ios_shortcut_delete',
      'ios_open_url',
      'ios_open_app',
    };
    for (final t in tools) {
      if (shortcutIds.contains(t.name)) registerTool(t);
    }
  }
}

/// Skill: `ios_live_activity` - Live Activities keep-alive UI on iOS 16.1+.
///
/// The model enables this to show a persistent status indicator in the
/// Lock Screen / Dynamic Island while the Agent is running. This is NOT
/// true background keep-alive (iOS strictly limits background execution),
/// but it provides a visible presence and interaction entry point.
class IosLiveActivitySkill extends Skill {
  IosLiveActivitySkill({this.service});

  final dynamic service;

  @override
  String get id => 'ios_live_activity';
  @override
  String get name => 'iOS Live Activities Keep-Alive';
  @override
  String get description => 'iOS Live Activities 保活：在锁屏和灵动岛显示 Agent 运行状态'
      '（live_activity_start/update/end）。Agent 开始执行任务时自动启动，'
      '每步更新状态文本，完成任务后结束。需要 iOS 16.1+。'
      '注意：这不是真正的后台保活，只是前台可见的状态指示。';

  @override
  Future<void> onEnable(void Function(Tool) registerTool) async {
    final tools = createIosAutomationTools(service: service);
    final liveActivityIds = {
      'ios_live_activity_start',
      'ios_live_activity_update',
      'ios_live_activity_end',
    };
    for (final t in tools) {
      if (liveActivityIds.contains(t.name)) registerTool(t);
    }
  }
}
