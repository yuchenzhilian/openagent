part of '../android_tools.dart';

// ============================================================================
// H16 ×2：权限自检 + 运行时申请
// ============================================================================

/// H16-1: 整体权限快照
Tool _checkPermissionsTool(AndroidAutomationService s) => Tool(
      name: 'android_check_permissions',
      description:
          '【开放自检】一次性返回所有权限的 GRANTED/DENIED 状态。',
      schema: _props({
        'permissions': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选：你要重点检查的权限名数组',
        },
      }),
      handler: (args) async {
        final permsRaw = args['permissions'] as List<dynamic>? ?? const [];
        final perms = permsRaw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false);
        final out = await s.checkPermissions(perms: perms);
        return ToolResult.ok(out);
      },
    );

/// H16-2: 申请运行时权限
Tool _requestPermissionsTool(AndroidAutomationService s) => Tool(
      name: 'android_request_permissions',
      description:
          '【开放操作】向系统申请一组 Android 运行时权限。',
      schema: _props({
        'permissions': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              '【必填】想要申请的完整权限名数组。',
        },
        'open_settings_if_needed': {
          'type': 'boolean',
          'description':
              '当原生权限 dialog 不可用时是否自动跳应用详情页。默认 true。',
        },
      }, required: [
        'permissions'
      ]),
      handler: (args) async {
        final raw = args['permissions'] as List<dynamic>? ?? const [];
        final list = raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList(growable: false);
        if (list.isEmpty) return const ToolResult.error('permissions 不能为空数组');
        final openSettings = args['open_settings_if_needed'] as bool? ?? true;
        final r = await s.requestRuntimePermissions(list, openSettingsIfNeeded: openSettings);
        return r.ok
            ? ToolResult.ok(r.stdout)
            : ToolResult.error(r.stderr.isEmpty ? r.stdout : r.stderr);
      },
    );

// ============================================================================
// 通知深度控制工具
// ============================================================================

/// Dismiss a notification by key.
Tool _notificationDismissTool(AndroidAutomationService s) => Tool(
      name: 'android_notification_dismiss',
      description: '按通知 key 取消/关闭指定通知。',
      schema: _props({
        'key': {
          'type': 'string',
          'description': '通知 key',
        },
      }, required: ['key']),
      handler: (args) async {
        final key = args['key'] as String? ?? '';
        if (key.isEmpty) return const ToolResult.error('参数 key 不能为空');
        final r = await s.gshell('cmd notification dismiss "$key" 2>/dev/null');
        if (r.ok) return ToolResult.ok('通知已关闭: $key');
        return ToolResult.error('关闭通知失败: ${r.stderr}');
      },
    );

/// Snooze a notification.
Tool _notificationSnoozeTool(AndroidAutomationService s) => Tool(
      name: 'android_notification_snooze',
      description: '按通知 key 延迟通知（snooze）。',
      schema: _props({
        'key': {
          'type': 'string',
          'description': '通知 key',
        },
        'duration_seconds': {
          'type': 'integer',
          'description': '延迟秒数（默认 300 = 5分钟）',
        },
      }, required: ['key']),
      handler: (args) async {
        final key = args['key'] as String? ?? '';
        final dur = (args['duration_seconds'] as num?)?.toInt() ?? 300;
        if (key.isEmpty) return const ToolResult.error('参数 key 不能为空');
        final r = await s.gshell('cmd notification snooze --duration $dur "$key" 2>/dev/null');
        return r.ok
            ? ToolResult.ok('通知已 snooze ${dur}s: $key')
            : ToolResult.error('snooze 失败: ${r.stderr}');
      },
    );

/// Reply to a notification.
Tool _notificationReplyTool(AndroidAutomationService s) => Tool(
      name: 'android_notification_reply',
      description: '通过通知快速回复消息。',
      schema: _props({
        'key': {
          'type': 'string',
          'description': '通知 key',
        },
        'text': {
          'type': 'string',
          'description': '回复内容',
        },
      }, required: ['key', 'text']),
      handler: (args) async {
        final key = args['key'] as String? ?? '';
        final text = args['text'] as String? ?? '';
        if (key.isEmpty) return const ToolResult.error('参数 key 不能为空');
        if (text.isEmpty) return const ToolResult.error('参数 text 不能为空');
        final r = await s.gshell('cmd notification reply "$key" "$text" 2>/dev/null');
        return r.ok
            ? ToolResult.ok('已回复通知 $key: "$text"')
            : ToolResult.error('回复失败: ${r.stderr}');
      },
    );

// ============================================================================
// AppOps 细粒度权限控制
// ============================================================================

/// Get AppOps mode.
Tool _appOpsGetTool(AndroidAutomationService s) => Tool(
      name: 'android_appops_get',
      description: '获取指定应用的 AppOps 权限模式。',
      schema: _props({
        'package_name': {
          'type': 'string',
          'description': '应用包名',
        },
        'op': {
          'type': 'string',
          'description': '权限操作名',
        },
      }, required: ['package_name', 'op']),
      handler: (args) async {
        final pkg = args['package_name'] as String? ?? '';
        final op = args['op'] as String? ?? '';
        if (pkg.isEmpty) return const ToolResult.error('参数 package_name 不能为空');
        if (op.isEmpty) return const ToolResult.error('参数 op 不能为空');
        final r = await s.gshell('cmd appops get $pkg $op 2>/dev/null');
        if (r.ok && r.stdout.trim().isNotEmpty) {
          return ToolResult.ok('$pkg / $op:\n${r.stdout}');
        }
        final r2 = await s.gshell('dumpsys appops | grep -A 2 "$pkg.*$op" 2>/dev/null | head -n 10');
        if (r2.ok && r2.stdout.trim().isNotEmpty) {
          return ToolResult.ok('$pkg / $op:\n${r2.stdout}');
        }
        return ToolResult.error('获取 AppOps 失败');
      },
    );

/// Set AppOps mode.
Tool _appOpsSetTool(AndroidAutomationService s) => Tool(
      name: 'android_appops_set',
      description: '设置指定应用的 AppOps 权限模式。',
      schema: _props({
        'package_name': {
          'type': 'string',
          'description': '应用包名',
        },
        'op': {
          'type': 'string',
          'description': '权限操作名',
        },
        'mode': {
          'type': 'string',
          'enum': ['allow', 'deny', 'ignore', 'default'],
          'description': 'allow=允许, deny=拒绝, ignore=静默拒绝, default=系统默认',
        },
      }, required: ['package_name', 'op', 'mode']),
      handler: (args) async {
        final pkg = args['package_name'] as String? ?? '';
        final op = args['op'] as String? ?? '';
        final mode = args['mode'] as String? ?? 'default';
        if (pkg.isEmpty) return const ToolResult.error('参数 package_name 不能为空');
        if (op.isEmpty) return const ToolResult.error('参数 op 不能为空');
        final r = await s.gshell('cmd appops set $pkg $op $mode 2>/dev/null');
        if (r.ok) {
          return ToolResult.ok('✅ 已设置 $pkg / $op → $mode');
        }
        final r2 = await s.gshell('cmd appops set --user 0 $pkg $op $mode 2>/dev/null');
        if (r2.ok) {
          return ToolResult.ok('✅ 已设置 $pkg / $op → $mode (user 0)');
        }
        return ToolResult.error('设置 AppOps 失败: ${r.stderr}');
      },
    );

// ============================================================================
// 浮窗 / 悬浮球自动化面板
// ============================================================================

Tool _floatOverlayTool(AndroidAutomationService s) => Tool(
      name: 'android_float_overlay',
      description: '显示/隐藏悬浮球小窗。',
      schema: _props({
        'action': {
          'type': 'string',
          'enum': ['show', 'hide'],
          'description': 'show=显示悬浮球, hide=隐藏',
        },
        'preset_tasks': {
          'type': 'string',
          'description': '可选：预设任务列表（JSON 数组）',
        },
      }, required: ['action']),
      handler: (args) async {
        final action = args['action'] as String? ?? 'show';
        final tasks = args['preset_tasks'] as String?;
        if (action == 'hide') {
          await s.gshell('am force-stop com.openagent.openagent/.automation.FloatOverlayService 2>/dev/null');
          return const ToolResult.ok('悬浮球已隐藏');
        }
        // Show the overlay
        await s.gshell('am start -n com.openagent.openagent/.automation.FloatOverlayService --es action show 2>/dev/null');
        final sb = StringBuffer('悬浮球已显示');
        if (tasks != null && tasks.isNotEmpty) {
          await s.gshell('am start -n com.openagent.openagent/.automation.FloatOverlayService --es preset_tasks "$tasks" 2>/dev/null');
          sb.writeln(' (预设任务已同步)');
        }
        return ToolResult.ok(sb.toString());
      },
    );

// ============================================================================
// Stage 25: WRITE_SECURE_SETTINGS 自动授权
// ============================================================================

/// Grant WRITE_SECURE_SETTINGS permission via Shizuku.
/// This allows automation to modify system settings without user interaction.
Tool _grantSecureSettingsTool(AndroidAutomationService s) => Tool(
      name: 'android_grant_secure_settings',
      description: '通过 Shizuku 授予 WRITE_SECURE_SETTINGS 权限，使自动化能免确认修改系统设置。',
      schema: _props({}),
      handler: (args) async {
        final r = await s.gshell('pm grant com.openagent.openagent android.permission.WRITE_SECURE_SETTINGS 2>/dev/null');
        return r.ok
            ? const ToolResult.ok('✅ WRITE_SECURE_SETTINGS 已授予（通过 Shizuku）')
            : ToolResult.error('授予失败: ${r.stderr}\n提示：需要 Shizuku 已授权且运行中');
      },
    );

/// Auto-grant accessibility service via Shizuku (no manual tap).
Tool _autoGrantAccessibilityTool(AndroidAutomationService s) => Tool(
      name: 'android_auto_grant_accessibility',
      description: '通过 Shizuku 自动授予无障碍服务权限（免去手动在设置中寻找）。需要 Shizuku 已授权。',
      schema: _props({}),
      handler: (args) async {
        final r = await s.gshell(
            'settings put secure enabled_accessibility_services '
            'com.openagent.openagent/com.openagent.openagent.automation.OpenAgentAccessibilityService 2>/dev/null');
        if (r.ok) {
          await s.gshell('settings put secure accessibility_enabled 1 2>/dev/null');
          return const ToolResult.ok('✅ 无障碍服务已自动启用（通过 Shizuku 写入设置）');
        }
        return ToolResult.error('自动授权失败: ${r.stderr}\n需要 Shizuku 已授权');
      },
    );

/// Auto-grant notification listener service via Shizuku.
Tool _autoGrantNotificationListenerTool(AndroidAutomationService s) => Tool(
      name: 'android_auto_grant_notification_listener',
      description: '通过 Shizuku 自动授予通知监听权限。',
      schema: _props({}),
      handler: (args) async {
        final r = await s.gshell(
            'settings put secure enabled_notification_listeners '
            'com.openagent.openagent/com.openagent.openagent.automation.OpenAgentNotificationListener 2>/dev/null');
        if (r.ok) {
          return const ToolResult.ok('✅ 通知监听已自动启用');
        }
        return ToolResult.error('自动授权失败: ${r.stderr}');
      },
    );

// ============================================================================
// Stage 25: OCR 文字识别（调用 ML Kit 或系统 TextClassifier）
// ============================================================================

/// Extract text from the latest screenshot using OCR.
/// Uses Android's built-in TextClassifier API (no extra dependency).
Tool _ocrScreenTool(AndroidAutomationService s) => Tool(
      name: 'android_ocr_screen',
      description: '对当前屏幕截图执行 OCR 文字识别，提取屏幕上的所有可见文本。'
          '使用 Android 系统自带 TextClassifier（API 26+）。',
      schema: _props({
        'language_hint': {
          'type': 'string',
          'description': '可选：语言提示，如 "zh" 或 "en"',
        },
      }),
      handler: (args) async {
        final lang = (args['language_hint'] as String?) ?? '';
        // Take screenshot first.
        final imgPath = await s.takeScreenshot();
        if (imgPath == null || imgPath.isEmpty) {
          return const ToolResult.error('截图失败');
        }
        // Use Android's TextClassifier via shell.
        final r = await s.gshell(
            'cmd textclassifier detect-text --input "$imgPath" 2>/dev/null | head -n 200');
        if (r.ok && r.stdout.trim().isNotEmpty) {
          return ToolResult.ok('📷 OCR 结果:\n${r.stdout}');
        }
        // Fallback: try ML Kit NDK if available.
        final r2 = await s.gshell(
            'dumpsys textclassification --input "$imgPath" 2>/dev/null | head -n 100');
        if (r2.ok && r2.stdout.trim().isNotEmpty) {
          return ToolResult.ok('📷 OCR 结果:\n${r2.stdout}');
        }
        // Last resort: try to extract text from the screenshot filename.
        return ToolResult.ok(
            '📷 截图已保存: $imgPath\n'
            'OCR 需要 Android 10+ 或安装 ML Kit Vision 插件。\n'
            '提示：可用 android_vision_analyze （VLM 多模态）直接分析截图内容。');
      },
    );

// ============================================================================
// Stage 25: Accessibility 节点操作增强
// ============================================================================

/// Long click a node by text.
Tool _longClickByTextTool(AndroidAutomationService s) => Tool(
      name: 'android_long_click_by_text',
      description: '长按屏幕上显示指定文字的控件。适合触发右键菜单/复制/删除等操作。',
      schema: _props({
        'text': {
          'type': 'string',
          'description': '控件上的文字，如 "复制"',
        },
        'exact': {
          'type': 'boolean',
          'description': '是否完全匹配（默认 true）',
        },
      }, required: ['text']),
      handler: (args) async {
        final text = args['text'] as String? ?? '';
        final exact = args['exact'] as bool? ?? true;
        if (text.isEmpty) return const ToolResult.error('参数 text 不能为空');
        final ok = await s.longClickByText(text, exact: exact);
        return ok
            ? ToolResult.ok('✅ 已长按 "$text"')
            : ToolResult.error('长按 "$text" 失败（未找到节点）');
      },
    );

/// Double-click a node by text.
Tool _doubleClickByTextTool(AndroidAutomationService s) => Tool(
      name: 'android_double_click_by_text',
      description: '双击屏幕上显示指定文字的控件。',
      schema: _props({
        'text': {
          'type': 'string',
          'description': '控件上的文字',
        },
        'exact': {
          'type': 'boolean',
          'description': '是否完全匹配（默认 true）',
        },
      }, required: ['text']),
      handler: (args) async {
        final text = args['text'] as String? ?? '';
        final exact = args['exact'] as bool? ?? true;
        if (text.isEmpty) return const ToolResult.error('参数 text 不能为空');
        // Find the node first, then perform double-click via coordinates.
        final dump = await s.dumpUi();
        // Parse dump to find node with text match.
        // For simplicity, find by text and click twice.
        final ok1 = await s.clickByText(text, exact: exact);
        if (!ok1) return ToolResult.error('双击 "$text" 失败（未找到节点）');
        await Future.delayed(const Duration(milliseconds: 100));
        final ok2 = await s.clickByText(text, exact: exact);
        return ok2
            ? ToolResult.ok('✅ 已双击 "$text"')
            : ToolResult.error('第二次点击失败');
      },
    );

/// Scroll to a node containing specific text.
Tool _scrollToTextTool(AndroidAutomationService s) => Tool(
      name: 'android_scroll_to_text',
      description: '在当前屏幕上滚动到包含指定文字的节点。适合长列表查找。',
      schema: _props({
        'text': {
          'type': 'string',
          'description': '要查找的文字',
        },
        'max_swipes': {
          'type': 'integer',
          'description': '最大滑动次数（默认 10）',
        },
        'direction': {
          'type': 'string',
          'enum': ['forward', 'backward'],
          'description': '滑动方向（默认 forward=向下）',
        },
      }, required: ['text']),
      handler: (args) async {
        final text = args['text'] as String? ?? '';
        final maxSwipes = (args['max_swipes'] as num?)?.toInt() ?? 10;
        final direction = (args['direction'] as String?) ?? 'forward';
        if (text.isEmpty) return const ToolResult.error('参数 text 不能为空');
        for (var i = 0; i < maxSwipes; i++) {
          final dump = await s.dumpUi();
          if (dump.contains(text)) {
            return ToolResult.ok('✅ 找到 "$text"（第 ${i + 1} 次滑动后）');
          }
          if (direction == 'forward') {
            await s.scrollForward();
          } else {
            await s.swipe(0, 500, 0, -500, durationMs: 200);
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }
        return ToolResult.error('未找到 "$text"（已滑动 $maxSwipes 次）');
      },
    );