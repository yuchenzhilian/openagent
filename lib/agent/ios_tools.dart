// iOS automation Agent tools - wrap [IosAutomationService] calls in the
// Agent [Tool] interface so the ReAct runtime can dispatch them.
//
// Since iOS has no AccessibilityService, these tools cover the limited
// automation surface available:
//   - Siri Shortcuts: donate / list / trigger / delete
//   - URL scheme deep-linking: open URL / open App
//   - Live Activities: start / update / end (for Agent keep-alive UI)
//
// Tool naming and descriptions use Chinese so the on-device model can
// learn to pick the right one, matching the Android tools convention.
import '../data/services/ios_automation_service.dart';
import 'agent_runtime.dart';

/// Factory: returns all iOS automation tools as a list ready for registerTool.
///
/// Returns an empty list on non-iOS platforms (the service gates on
/// `Platform.isIOS`), so this is safe to call unconditionally.
List<Tool> createIosAutomationTools({IosAutomationService? service}) {
  final s = service ?? IosAutomationService.instance;
  if (!s.isSupported) return const [];

  return [
    _shortcutDonateTool(s),
    _shortcutListTool(s),
    _shortcutTriggerTool(s),
    _shortcutDeleteTool(s),
    _openUrlTool(s),
    _openAppTool(s),
    _liveActivityStartTool(s),
    _liveActivityUpdateTool(s),
    _liveActivityEndTool(s),
  ];
}

// ---------------------------------------------------------------------------
// Shortcuts tools
// ---------------------------------------------------------------------------

Tool _shortcutDonateTool(IosAutomationService s) {
  return Tool(
    name: 'ios_shortcut_donate',
    description: '注册一个 Siri 快捷指令，让用户可以通过语音或快捷指令 App 触发 Agent 任务。'
        '参数: id(唯一标识), title(显示名称), description(描述), phrase(建议的语音短语, 可选)',
    schema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string', 'description': '快捷指令唯一标识，如 "search_files"'},
        'title': {'type': 'string', 'description': '显示名称，如 "用 OpenAgent 搜索文件"'},
        'description': {'type': 'string', 'description': '在快捷指令 App 中显示的描述'},
        'phrase': {
          'type': 'string',
          'description': '建议的 Siri 语音短语，如 "用 OpenAgent 搜索"'
        },
      },
      'required': ['id', 'title', 'description'],
    },
    handler: (args) async {
      final ok = await s.donateShortcut(
        id: args['id'] as String,
        title: args['title'] as String,
        description: args['description'] as String,
        phrase: args['phrase'] as String?,
      );
      return ToolResult.ok(ok ? '快捷指令已注册: ${args['title']}' : '注册失败');
    },
  );
}

Tool _shortcutListTool(IosAutomationService s) {
  return Tool(
    name: 'ios_shortcut_list',
    description: '列出所有已注册的 Siri 快捷指令',
    schema: {'type': 'object', 'properties': {}},
    handler: (args) async {
      final list = await s.listShortcuts();
      if (list.isEmpty) return const ToolResult.ok('暂无已注册的快捷指令');
      final buf = StringBuffer('已注册 ${list.length} 个快捷指令:\n');
      for (final sc in list) {
        buf.writeln('  - ${sc['id']}: ${sc['title']} (${sc['description']})');
      }
      return ToolResult.ok(buf.toString());
    },
  );
}

Tool _shortcutTriggerTool(IosAutomationService s) {
  return Tool(
    name: 'ios_shortcut_trigger',
    description: '通过 URL scheme 触发系统级操作（拨打电话、发送短信、打开地图等）。'
        '这是 iOS 上 Agent 触发系统 Intent 的主要方式。'
        '常用 scheme: tel:（电话）, sms:（短信）, maps:（地图）, '
        'mailto:（邮件）, appstore:（App Store）',
    schema: {
      'type': 'object',
      'properties': {
        'url': {
          'type': 'string',
          'description': 'URL scheme，如 "tel:10086" 或 "sms:10086"'
        },
      },
      'required': ['url'],
    },
    handler: (args) async {
      final url = args['url'] as String;
      final ok = await s.triggerShortcut(url);
      return ToolResult.ok(ok ? '已触发: $url' : '触发失败（URL 可能无效）');
    },
  );
}

Tool _shortcutDeleteTool(IosAutomationService s) {
  return Tool(
    name: 'ios_shortcut_delete',
    description: '删除一个已注册的 Siri 快捷指令',
    schema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string', 'description': '要删除的快捷指令 ID'},
      },
      'required': ['id'],
    },
    handler: (args) async {
      final ok = await s.deleteShortcut(args['id'] as String);
      return ToolResult.ok(ok ? '已删除快捷指令: ${args['id']}' : '删除失败（ID 可能不存在）');
    },
  );
}

// ---------------------------------------------------------------------------
// URL / App opening tools
// ---------------------------------------------------------------------------

Tool _openUrlTool(IosAutomationService s) {
  return Tool(
    name: 'ios_open_url',
    description: '在系统浏览器中打开 URL（http/https），或通过 deeplink/通用链接打开内容。'
        '示例: "https://www.baidu.com", "https://maps.apple.com/?q=餐厅"',
    schema: {
      'type': 'object',
      'properties': {
        'url': {'type': 'string', 'description': '要打开的 URL'},
      },
      'required': ['url'],
    },
    handler: (args) async {
      final ok = await s.openUrl(args['url'] as String);
      return ToolResult.ok(ok ? '已打开: ${args['url']}' : '打开失败');
    },
  );
}

Tool _openAppTool(IosAutomationService s) {
  return Tool(
    name: 'ios_open_app',
    description: '通过 URL scheme 打开第三方 App。常用 scheme: '
        '微信=weixin://, 抖音=snssdk1128://, 支付宝=alipay://, '
        '淘宝=taobao://, QQ=mqq://, 微博=sinaweibo://, 知乎=zhihu://',
    schema: {
      'type': 'object',
      'properties': {
        'scheme': {
          'type': 'string',
          'description': 'App 的 URL scheme，如 "weixin://"'
        },
      },
      'required': ['scheme'],
    },
    handler: (args) async {
      final ok = await s.openApp(args['scheme'] as String);
      return ToolResult.ok(
          ok ? '已打开 App: ${args['scheme']}' : '打开失败（App 可能未安装）');
    },
  );
}

// ---------------------------------------------------------------------------
// Live Activities tools
// ---------------------------------------------------------------------------

Tool _liveActivityStartTool(IosAutomationService s) {
  return Tool(
    name: 'ios_live_activity_start',
    description: '启动 Live Activity 保活 UI（锁屏/灵动岛显示 Agent 运行状态）。'
        '在 Agent 开始执行任务时自动调用。'
        '参数: title(标题，如 "Agent 运行中"), content(状态文本，如 "正在思考...")',
    schema: {
      'type': 'object',
      'properties': {
        'title': {'type': 'string', 'description': 'Live Activity 标题'},
        'content': {'type': 'string', 'description': '当前状态文本'},
      },
      'required': ['title', 'content'],
    },
    handler: (args) async {
      final ok = await s.startActivity(
        title: args['title'] as String,
        content: args['content'] as String,
      );
      return ToolResult.ok(ok ? 'Live Activity 已启动' : '启动失败（可能需要 iOS 16.1+）');
    },
  );
}

Tool _liveActivityUpdateTool(IosAutomationService s) {
  return Tool(
    name: 'ios_live_activity_update',
    description: '更新 Live Activity 状态文本（如 "正在执行工具: calculator"）。'
        '在 Agent 每步 ReAct 循环时调用以保持用户可见的状态更新。',
    schema: {
      'type': 'object',
      'properties': {
        'content': {'type': 'string', 'description': '更新后的状态文本'},
      },
      'required': ['content'],
    },
    handler: (args) async {
      final ok = await s.updateActivity(args['content'] as String);
      return ToolResult.ok(ok ? '状态已更新: ${args['content']}' : '更新失败');
    },
  );
}

Tool _liveActivityEndTool(IosAutomationService s) {
  return Tool(
    name: 'ios_live_activity_end',
    description: '结束 Live Activity（在 Agent 完成任务时调用）',
    schema: {'type': 'object', 'properties': {}},
    handler: (args) async {
      final ok = await s.endActivity();
      return ToolResult.ok(ok ? 'Live Activity 已结束' : '结束失败');
    },
  );
}
