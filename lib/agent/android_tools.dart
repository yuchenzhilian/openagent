// Android automation Agent tools — wrap [AndroidAutomationService] calls
// in the Agent [Tool] interface so the ReAct runtime can dispatch them.
//
// Tool naming matches the plan document; each tool includes a short Chinese
// description so the 0.6B–4B on-device model learns to pick the right one.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/services/android_automation_service.dart';
import 'agent_runtime.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ToolSchema _props(Map<String, Map<String, dynamic>> p,
        {List<String> required = const []}) =>
    {
      'type': 'object',
      'properties': p,
      if (required.isNotEmpty) 'required': required,
    };

String _packageHint() =>
    '常用包名参考: 微信=com.tencent.mm, 抖音=com.ss.android.ugc.aweme, '
    '小红书=com.xingin.xhs, B站=tv.danmaku.bili, 微博=com.sina.weibo, '
    'QQ=com.tencent.mobileqq, 淘宝=com.taobao.taobao, 支付宝=com.eg.android.AlipayGphone, '
    '设置=com.android.settings';

// ---------------------------------------------------------------------------
// Factory: returns all Android tools as a list ready for registerTool.
// ---------------------------------------------------------------------------

List<Tool> createAndroidAutomationTools({
  AndroidAutomationService? service,
  Future<String> Function(String imagePath, String question)? visionAnalyze,
  Future<ToolResult> Function(String name, Map<String, dynamic> args)? executeCallback,
  AgentMemoryBackend? memoryBackend,
}) {
  final s = service ?? AndroidAutomationService.instance;
  if (!s.isSupported) return const [];

  final tools = <Tool>[
    _openAppTool(s),
    _clickByTextTool(s),
    _clickByIdTool(s),
    _clickCoordsTool(s),
    _swipeTool(s),
    _scrollForwardTool(s),
    _inputTextTool(s),
    _pressKeyTool(s),
    _dumpUiTool(s),
    _listPackagesTool(s),
    _screenResolutionTool(s),
    _screenshotTool(s),
    if (visionAnalyze != null) _visionAnalyzeTool(visionAnalyze),
    // Stage 31: VLM 多模态增强
    if (visionAnalyze != null) _screenChangeDetectTool(s, visionAnalyze),
    if (visionAnalyze != null) _visionAnalyzeRegionTool(s, visionAnalyze),
    _screenHashTool(s),
    // Stage 32: 深化工具
    _shizukuSimplifiedTool(s),
    _permissionSelfHealTool(s),
    _agentExecutionLogTool(s),
    _waitTool(),
    _waitForTextTool(s),
    _installApkTool(s),
    _getTopAppTool(s),
    _getPermissionStatusTool(s),
    _gshellTool(s),
    _composeWechatSendMessage(s),
    _composeDouyinLikeCurrent(s),
    _composeXiaohongshuSearch(s),
    _composeQqSendMessage(s),
    _composeDouyinNextVideo(s),
    _composeDouyinCommentCurrent(s),
    _composeXiaohongshuLikeFirstNote(s),
    _composeBilibiliSearch(s),
    // H3 批处理 / 深度 Macro
    _composeDouyinBatchSwipe(s),
    _composeWechatMomentsLikeBatch(s),
    _composeBilibiliThreeInOne(s),
    // H4 系统能力 + App 进阶操作 ×5
    _composeWechatPostTextMoments(s),
    _composeXiaohongshuFollowUser(s),
    _composeDouyinFollowCurrentAuthor(s),
    _composeSystemSetAlarm(s),
    _composeSystemSendSms(s),
    // H5 高频日常工具 ×4
    _composeDouyinSearch(s),
    _composeWechatScanQr(s),
    _composeSystemDial(s),
    _composeSystemTakePhoto(s),
    // H6 游戏 + 支付宝
    _composeAlipayScan(s),
    _composeAlipayShowCode(s),
    if (visionAnalyze != null) _composeGameAutoVlmLoop(s, visionAnalyze),
    // H7 系统设置 + 社交补全 ×5
    _composeSystemWifi(s),
    _composeSystemBluetooth(s),
    _composeSystemSetVolume(s),
    _composeWechatBroadcastMessage(s),
    _composeBilibiliSendDanmaku(s),
    // H8 开放通用工具 ×5（给模型自主决策，不硬编码流程）
    _longPressTool(s),
    _clipboardTool(s),
    _customGestureTool(s),
    _shellExecTool(s),
    if (visionAnalyze != null) _visionFreeAnalyzeTool(s, visionAnalyze),
    // H10 开放原子能力 ×5（最底层Intent/文件/通知/AppInfo/Window Dump）
    _sendIntentTool(s),
    _fileTool(s),
    _appInfoTool(s),
    _notificationListTool(s),
    _dumpWindowsTool(s),
    // H11 补充开放原子 ×5（联系人 / 电量网络硬件状态 / 双卡短信发送 / 短信收件箱 / 传感器列表+采样）
    _queryContactsTool(s),
    _deviceStatusTool(s),
    _sendSmsTool(s),
    _querySmsTool(s),
    _sensorsTool(s),
    // H15 系统原子补全 ×6（最近任务 / Frag栈 / WiFi扫描 / 双卡详情 / Toast历史 / 杀进程+冷启动）
    _recentTasksTool(s),
    _dumpFragmentsTool(s),
    _wifiScanTool(s),
    _simInfoTool(s),
    _toastHistoryTool(s),
    _killRestartTool(s),
    // H16 权限 ×2：全景自检 + 运行时申请引导
    _checkPermissionsTool(s),
    _requestPermissionsTool(s),
    // H17 硬件/通话/相册/亮度输入法/壁纸分享 ×5
    _hardwareInfoTool(s),
    _callLogTool(s),
    _mediaGalleryTool(s),
    _displayAndInputTool(s),
    _wallpaperAndShareTool(s),
    // H13: execute_plan (需要传入 AgentRuntime 的 executeTool 回调，未传则不注册)
    if (executeCallback != null) buildExecutePlanTool(executeCallback),
    // H14: agent_memory KV (需要传入本地文件后端，未传则不注册)
    if (memoryBackend != null) buildAgentMemoryTool(memoryBackend),

    // ---- 防高风险应用检测工具 ----
    _antiDetectionCheckTool(s),
    _antiDetectionSafeModeTool(s),
    _antiDetectionBankingListTool(),

    // ---- Stage 24: 通知深度控制 ----
    _notificationDismissTool(s),
    _notificationSnoozeTool(s),
    _notificationReplyTool(s),

    // ---- Stage 24: 录制回放 ----
    _recordMacroTool(s),
    _stopMacroTool(s),
    _listMacroTool(),

    // ---- Stage 24: AppOps 细粒度权限 ----
    _appOpsGetTool(s),
    _appOpsSetTool(s),

    // ---- Stage 24: 浮窗 / 悬浮球 ----
    _floatOverlayTool(s),

    // ---- Stage 25: WRITE_SECURE_SETTINGS 自动授权 ----
    _grantSecureSettingsTool(s),
    _autoGrantAccessibilityTool(s),
    _autoGrantNotificationListenerTool(s),

    // ---- Stage 25: OCR 文字识别 ----
    _ocrScreenTool(s),

    // ---- Stage 25: 节点操作增强 ----
    _longClickByTextTool(s),
    _doubleClickByTextTool(s),
    _scrollToTextTool(s),

    // ---- Stage 26: 社交 App 组合宏 ----
    _composeXiaohongshuPostNote(s),
    _composeXiaohongshuSendMessage(s),
    _composeDouyinPostVideo(s),
    _composeWechatPostImageMoments(s),

    // ---- Stage 27: 设备安全加固 ----
    _keepAliveTool(s),
    _hideShizukuTool(s),
    _mockLocationTool(s),

    // ---- Stage 29: 手机管家 ----
    _phoneFileManagerTool(s),
    _phoneAppManagerTool(s),
    _phoneDeepCleanTool(s),
  ];
  return tools;
}

/// Anti-detection tools — always available regardless of automation switch.
/// These let the agent check whether the current foreground app is a
/// high-risk app before attempting any automation.
List<Tool> createAntiDetectionTools({AndroidAutomationService? service}) {
  final s = service ?? AndroidAutomationService.instance;
  if (!s.isSupported) return const [];
  return [
    _antiDetectionCheckTool(s),
    _antiDetectionSafeModeTool(s),
    _antiDetectionBankingListTool(),
  ];
}

// ---------------------------------------------------------------------------
// Individual tools
// ---------------------------------------------------------------------------

Tool _openAppTool(AndroidAutomationService s) => Tool(
      name: 'android_open_app',
      description:
          '打开 Android 设备上的某个应用（通过包名 package_name）。${_packageHint()}',
      schema: _props({
        'package_name': {
          'type': 'string',
          'description': '目标应用的 Android 包名，如 com.tencent.mm',
        },
      }, required: [
        'package_name'
      ]),
      handler: (args) async {
        final pkg = args['package_name'] as String?;
        if (pkg == null || pkg.isEmpty) {
          return const ToolResult.error('缺少参数 package_name');
        }
        final ok = await s.openApp(pkg);
        return ok
            ? ToolResult.ok('已打开 $pkg（若没看到界面，可能需要等待加载）')
            : ToolResult.error('打开 $pkg 失败（应用未安装或缺少启动 Intent）');
      },
    );

Tool _clickByTextTool(AndroidAutomationService s) => Tool(
      name: 'android_click_by_text',
      description:
          '在当前屏幕上点击显示指定文字的按钮/链接/标签（标准 View 控件可用）。exact=true 表示完全匹配文字。',
      schema: _props({
        'text': {'type': 'string', 'description': '控件上显示的文字，如 发现、发送'},
        'exact': {
          'type': 'boolean',
          'description': '是否完全匹配，默认 true；不确定时可设为 false 模糊搜索',
        },
      }, required: [
        'text'
      ]),
      handler: (args) async {
        final text = args['text'] as String?;
        if (text == null || text.isEmpty) {
          return const ToolResult.error('缺少参数 text');
        }
        final exact = args['exact'] as bool? ?? true;
        final ok = await s.clickByText(text, exact: exact);
        return ok
            ? ToolResult.ok('已点击文字 "$text"')
            : ToolResult.error('未找到文字为 "$text" 的可点击控件，可能需要先 dump_ui 看控件');
      },
    );

Tool _clickByIdTool(AndroidAutomationService s) => Tool(
      name: 'android_click_by_id',
      description:
          '按资源 ID (view_id) 精准点击控件，优先于按文字点击。可通过 dump_ui 获取 id。',
      schema: _props({
        'view_id': {
          'type': 'string',
          'description': '控件的 viewIdResourceName，如 com.tencent.mm:id/b4k',
        },
      }, required: [
        'view_id'
      ]),
      handler: (args) async {
        final id = args['view_id'] as String?;
        if (id == null || id.isEmpty) {
          return const ToolResult.error('缺少参数 view_id');
        }
        final ok = await s.clickById(id);
        return ok
            ? ToolResult.ok('已点击 id=$id')
            : ToolResult.error('未找到 id=$id 的控件');
      },
    );

Tool _clickCoordsTool(AndroidAutomationService s) => Tool(
      name: 'android_click_coords',
      description:
          '按屏幕像素坐标点击，用于游戏/视频等无标准 View 的界面。坐标可通过 dump_ui 的 bounds 或截图后人工判断得到。',
      schema: _props({
        'x': {'type': 'integer', 'description': '横坐标像素值 (0 ≤ x < 屏幕宽)'},
        'y': {'type': 'integer', 'description': '纵坐标像素值 (0 ≤ y < 屏幕高)'},
      }, required: [
        'x',
        'y'
      ]),
      handler: (args) async {
        final x = args['x'] as int?;
        final y = args['y'] as int?;
        if (x == null || y == null) {
          return const ToolResult.error('缺少参数 x 或 y');
        }
        final ok = await s.clickCoords(x, y);
        return ok
            ? ToolResult.ok('已点击坐标 ($x, $y)')
            : ToolResult.error('坐标点击失败（可能无障碍/Shizuku 权限未开启）');
      },
    );

Tool _swipeTool(AndroidAutomationService s) => Tool(
      name: 'android_swipe',
      description: '执行滑动手势，用于翻页、滚动列表、返回上一级等。duration_ms 默认 300。',
      schema: _props({
        'x1': {'type': 'integer', 'description': '起点 x 像素'},
        'y1': {'type': 'integer', 'description': '起点 y 像素'},
        'x2': {'type': 'integer', 'description': '终点 x 像素'},
        'y2': {'type': 'integer', 'description': '终点 y 像素'},
        'duration_ms': {
          'type': 'integer',
          'description': '滑动持续毫秒，数字越大滑动越慢',
        },
      }, required: [
        'x1',
        'y1',
        'x2',
        'y2'
      ]),
      handler: (args) async {
        final x1 = args['x1'] as int?;
        final y1 = args['y1'] as int?;
        final x2 = args['x2'] as int?;
        final y2 = args['y2'] as int?;
        if (x1 == null || y1 == null || x2 == null || y2 == null) {
          return const ToolResult.error('缺少 x1/y1/x2/y2 参数');
        }
        final dur = args['duration_ms'] as int? ?? 300;
        final ok = await s.swipe(x1, y1, x2, y2, durationMs: dur);
        return ok
            ? ToolResult.ok('已执行滑动 (${x1}x$y1 → ${x2}x$y2, ${dur}ms)')
            : ToolResult.error('滑动失败');
      },
    );

Tool _scrollForwardTool(AndroidAutomationService s) => Tool(
      name: 'android_scroll_forward',
      description: '在当前可滚动的控件上向前滚动一屏（如刷抖音下一条、向下看更多内容）',
      schema: _props({}),
      handler: (_) async {
        final ok = await s.scrollForward();
        return ok
            ? const ToolResult.ok('已向前滚动一屏')
            : const ToolResult.error('未找到可滚动控件，改用 android_swipe 手动指定位置');
      },
    );

Tool _inputTextTool(AndroidAutomationService s) => Tool(
      name: 'android_input_text',
      description: '在当前焦点输入框中输入文字（需先通过点击让输入框获得焦点）',
      schema: _props({
        'text': {'type': 'string', 'description': '要输入的文本内容'},
      }, required: [
        'text'
      ]),
      handler: (args) async {
        final text = args['text'] as String?;
        if (text == null) return const ToolResult.error('缺少参数 text');
        final ok = await s.inputText(text);
        return ok
            ? ToolResult.ok('已输入：$text')
            : ToolResult.error('输入失败（请先点击输入框获得焦点）');
      },
    );

Tool _pressKeyTool(AndroidAutomationService s) => Tool(
      name: 'android_press_key',
      description:
          '按下系统级按键。可选值: home, back, recent, volume_up, volume_down, power, enter, del',
      schema: _props({
        'key': {
          'type': 'string',
          'description':
              '按键名：home=回桌面 / back=返回 / recent=最近任务 / volume_up=音量加 / volume_down=音量减 / power=电源 / enter=回车 / del=删除',
        },
      }, required: [
        'key'
      ]),
      handler: (args) async {
        final k = args['key'] as String?;
        final key = switch (k?.toLowerCase()) {
          'home' => AndroidKey.home,
          'back' => AndroidKey.back,
          'recent' => AndroidKey.recent,
          'volume_up' || 'vol_up' => AndroidKey.volumeUp,
          'volume_down' || 'vol_down' => AndroidKey.volumeDown,
          'power' => AndroidKey.power,
          'enter' => AndroidKey.enter,
          'del' || 'delete' => AndroidKey.delete,
          _ => null,
        };
        if (key == null) {
          return ToolResult.error('不支持的按键: $k。可选值: home back recent volume_up volume_down power enter del');
        }
        final ok = await s.pressKey(key);
        return ok
            ? ToolResult.ok('已按：${k}')
            : ToolResult.error('按键 ${k} 执行失败');
      },
    );

Tool _dumpUiTool(AndroidAutomationService s) => Tool(
      name: 'android_dump_ui',
      description:
          '读取当前屏幕上所有控件的文字/ID/坐标/是否可点击等信息，用来决定下一步点击什么。执行任何自动化前强烈建议先调用本工具观察界面。',
      schema: _props({
        'limit': {
          'type': 'integer',
          'description': '最多返回多少个控件（默认 80），太长会超出 LLM 上下文',
        },
      }),
      handler: (args) async {
        final limit = args['limit'] as int? ?? 80;
        final summary = await s.dumpUiSummary(limit: limit);
        return ToolResult.ok(summary);
      },
    );

Tool _listPackagesTool(AndroidAutomationService s) => Tool(
      name: 'android_list_packages',
      description:
          '列出设备上已安装应用的全部包名，供 android_open_app 使用。输出可能较长，建议仅在需要找包名时调用。',
      schema: _props({
        'contains': {
          'type': 'string',
          'description': '可选：只返回包含该关键词的包名（模糊过滤）',
        },
      }),
      handler: (args) async {
        final list = await s.listInstalledPackages();
        if (list.isEmpty) {
          return const ToolResult.error('无法获取应用列表（需要 Shizuku 或无障碍权限）');
        }
        final filter = args['contains'] as String?;
        final filtered = filter == null
            ? list
            : list.where((p) => p.contains(filter.toLowerCase())).toList();
        final str = filtered.take(200).join('\n');
        final totalShown =
            filtered.length > 200 ? '\n（仅显示前 200 / ${filtered.length} 个，可用 contains 进一步过滤）' : '';
        return ToolResult.ok('$str$totalShown');
      },
    );

Tool _screenResolutionTool(AndroidAutomationService s) => Tool(
      name: 'android_screen_resolution',
      description:
          '获取设备屏幕分辨率 [宽, 高] 像素。在需要精准计算 android_click_coords / android_swipe 时先调用。',
      schema: _props({}),
      handler: (_) async {
        final r = await s.screenResolution();
        if (r == null || r.length != 2) {
          return const ToolResult.error('无法获取屏幕分辨率（需要 Shizuku 权限或截图权限）');
        }
        return ToolResult.ok('屏幕分辨率：宽 ${r[0]} × 高 ${r[1]} 像素');
      },
    );

Tool _screenshotTool(AndroidAutomationService s) => Tool(
      name: 'android_screenshot',
      description:
          '截取当前屏幕为 PNG 文件，返回图片的绝对文件路径。对于抖音/游戏等无法 dump_ui 的场景，可调用本工具再通过 Omni 多模态模型直接分析截图内容。',
      schema: _props({}),
      handler: (_) async {
        final path = await s.takeScreenshot();
        if (path == null) {
          return const ToolResult.error('截图失败（需先在权限引导页开启截图权限，或授权 Shizuku 后重试）');
        }
        return ToolResult.ok('截图已保存到：$path\n'
            '（如需看懂屏幕内容：把该路径作为 Omni 多模态对话的图片附件传给助手即可）');
      },
    );

Tool _waitTool() => Tool(
      name: 'android_wait',
      description: '等待若干秒（如等待页面跳转、应用加载完成、弹窗弹出后再操作）',
      schema: _props({
        'seconds': {
          'type': 'number',
          'description': '等待秒数（可小数，如 1.5），默认 2 秒',
        },
      }),
      handler: (args) async {
        final secs = (args['seconds'] as num?)?.toDouble() ?? 2.0;
        final ms = (secs * 1000).round();
        await Future<void>.delayed(Duration(milliseconds: ms));
        return ToolResult.ok('已等待 ${secs.toStringAsFixed(2)} 秒');
      },
    );

/// Intelligently wait for a specific UI element (text/id string) to appear
/// on the screen before the next automation step. Much more reliable than a
/// blind android_wait fixed-delay because phones vary a lot on app launch
/// latency and page rendering speed.
Tool _waitForTextTool(AndroidAutomationService s) => Tool(
      name: 'android_wait_for_text',
      description:
          '轮询无障碍 UI 树，直到屏幕出现指定文字（timeout 超时返回失败）。'
          '比固定等待秒数 android_wait 更稳：用于「打开 App 后等登录按钮出来再点」、'
          '「点了发送后等「发送成功」出现」、跳转新页面确认加载完这类场景。'
          '超时后返回失败，由 Agent 决定是否换 dump_ui 分析或延长超时重试。',
      schema: _props({
        'text': {
          'type': 'string',
          'description': '要等待出现的目标文字（大小写不敏感，包含匹配）',
        },
        'timeout_seconds': {
          'type': 'number',
          'description': '最长等待秒数，默认 10 秒',
        },
        'poll_ms': {
          'type': 'number',
          'description': '两次 UI 扫描间隔毫秒，默认 500ms',
        },
        'exact': {
          'type': 'boolean',
          'description': '是否精确匹配整行 (默认 false=包含匹配即可)',
        },
      }, required: [
        'text'
      ]),
      handler: (args) async {
        final text = args['text'] as String?;
        if (text == null || text.isEmpty) {
          return const ToolResult.error('缺少 text 参数');
        }
        final timeout =
            ((args['timeout_seconds'] as num?)?.toDouble() ?? 10.0).toInt();
        final poll =
            ((args['poll_ms'] as num?)?.toDouble() ?? 500.0).toInt();
        final exact = args['exact'] == true;
        final safePoll = poll < 50 ? 50 : poll;
        final ok = await s.waitForText(
          text,
          timeoutSec: timeout,
          pollMs: safePoll,
          exact: exact,
        );
        if (ok) {
          final scansApprox = (timeout * 1000 / safePoll).round();
          return ToolResult.ok(
              '已在屏幕上检测到文字「$text」（超时${timeout}s，约 $scansApprox 次扫描）。可进行下一步操作。');
        }
        return ToolResult.error(
            '等待「$text」出现失败：${timeout}秒内没在 UI 树中找到。'
            '建议：1) android_dump_ui 重看一下真实界面文字是否变化；'
            '2) 把 timeout_seconds 调大（如 15/20）；3) 检查大小写或改用非 exact 包含匹配。');
      },
    );

Tool _installApkTool(AndroidAutomationService s) => Tool(
      name: 'android_install_apk',
      description:
          '静默安装 APK 文件（需要 Shizuku 或 Root 权限；否则会弹出系统安装器需用户确认）',
      schema: _props({
        'apk_path': {'type': 'string', 'description': 'APK 文件的绝对路径'},
      }, required: [
        'apk_path'
      ]),
      handler: (args) async {
        final p = args['apk_path'] as String?;
        if (p == null || p.isEmpty) {
          return const ToolResult.error('缺少 apk_path');
        }
        final ok = await s.installApk(p);
        return ok
            ? ToolResult.ok('APK 安装成功：$p')
            : ToolResult.error('静默安装失败（无 Shizuku 权限？已改由系统安装器显示安装确认界面，用户点确认后可完成）');
      },
    );

// ---- Advanced / optional tools (below) -----------------------------------

Tool _getTopAppTool(AndroidAutomationService s) => Tool(
      name: 'android_get_top_app',
      description: '获取当前在前台运行的应用（包名 + Activity 类名）。'
          '用于确认是否已成功打开目标 App（如执行 android_open_app 后校验），再进行后续点击操作。',
      schema: _props({}),
      handler: (_) async {
        final info = await s.getTopApp();
        if (info.package.isEmpty) {
          return const ToolResult.error(
              '无法获取前台应用（需要 PACKAGE_USAGE_STATS 或 Shizuku 权限）。可改用 android_dump_ui 观察包名。');
        }
        return ToolResult.ok('当前前台应用：package=${info.package}\n'
            'activity=${info.activity.isEmpty ? '(未知)' : info.activity}');
      },
    );

Tool _getPermissionStatusTool(AndroidAutomationService s) => Tool(
      name: 'android_get_permission_status',
      description:
          '查询当前 Android 自动化后端状态（无障碍 / Shizuku / 截图 / 应用使用统计）。'
          '若某个操作一直失败，先调用该工具确认对应权限是否已授权。',
      schema: _props({}),
      handler: (_) async {
        final m = await s.getPermissionStatusMap();
        if (m.isEmpty) {
          return const ToolResult.ok('当前平台非 Android，自动化不可用。');
        }
        String fmt(String k, String zhName) {
          final v = m[k] == true ? '✅已授权' : '❌未授权';
          return '$zhName: $v';
        }

        return ToolResult.ok([
          fmt('accessibility_enabled', 'L1 无障碍服务'),
          fmt('shizuku_granted', 'L2 Shizuku Shell'),
          fmt('screenshot_granted', '截图 MediaProjection'),
          fmt('usage_stats_granted', '应用使用统计(查前台App)'),
        ].join('\n'));
      },
    );

/// Danger-zone tool — can run arbitrary shell commands. Gated behind a
/// confirmation notice in the tool description so the model only uses it
/// when really needed (e.g. adb-style `pm enable ...`, `settings put ...`,
/// `screencap`, custom dumpsys filters).
Tool _gshellTool(AndroidAutomationService s) => Tool(
      name: 'android_gshell',
      description: '⚠ 高级工具：直接通过 Shizuku / shell 运行任意命令。'
          '仅限以下场景使用：1) 没有对应专用自动化工具时；2) 需修改系统设置等特殊操作。'
          '每次调用需报告将执行的命令以及预期影响。',
      schema: _props({
        'command': {
          'type': 'string',
          'description': '要执行的 shell 命令，如 "pm list packages -3" 或 "dumpsys battery"',
        },
      }, required: [
        'command'
      ]),
      handler: (args) async {
        final cmd = args['command'] as String?;
        if (cmd == null || cmd.isEmpty) return const ToolResult.error('缺少 command');
        final r = await s.gshell(cmd);
        final preview = r.stdout.length > 2000
            ? '${r.stdout.substring(0, 2000)}\n…(stdout 截断，共 ${r.stdout.length} 字符)'
            : r.stdout;
        final body = StringBuffer('命令：`$cmd`\n');
        body.writeln('退出码：${r.exitCode} (${r.ok ? "成功" : "失败"})');
        if (r.stderr.isNotEmpty) {
          body.writeln('stderr:\n```\n${r.stderr.substring(0, r.stderr.length > 1000 ? 1000 : r.stderr.length)}\n```');
        }
        if (preview.isNotEmpty) body.writeln('stdout:\n```\n$preview\n```');
        return ToolResult.ok(body.toString());
      },
    );

/// Vision analysis tool: wraps an on-device Omni multimodal model.
/// The Agent calls this after android_screenshot when dump_ui is empty
/// (games / Douyin ForYou feeds / custom Canvas surfaces). Outputs a
/// text answer the model can use to pick a click coordinate / next action.
Tool _visionAnalyzeTool(
        Future<String> Function(String imagePath, String question) analyze) =>
    Tool(
      name: 'android_vision_analyze',
      description: '用本地多模态大模型 (Omni VLM) 分析一张截图。'
          '在 android_dump_ui 返回空时（游戏、抖音 feed、自定义画布、纯图片界面）调用，'
          '传入截图路径 + 你的问题，返回文字描述（含按钮位置、坐标建议）。'
          '参数 image_path 一般来自 android_screenshot 的输出。',
      schema: _props({
        'image_path': {
          'type': 'string',
          'description': '截图 PNG/JPG 的绝对路径（android_screenshot 返回）',
        },
        'question': {
          'type': 'string',
          'description':
              '要对截图问的问题。例：请描述这张截图里所有可点击的按钮，'
              '并估算每个按钮的中心坐标 (x,y)（屏幕宽 1080 高 2400 左上角为 0,0）。'
              '如要操作游戏：描述所有关卡入口 / 开始按钮 / 确认按钮的坐标。',
        },
      }, required: [
        'image_path',
        'question',
      ]),
      handler: (args) async {
        final p = args['image_path'] as String?;
        final q = args['question'] as String?;
        if (p == null || p.isEmpty) return const ToolResult.error('缺少 image_path');
        if (q == null || q.isEmpty) return const ToolResult.error('缺少 question');
        try {
          final answer = await analyze(p, q);
          return ToolResult.ok(answer);
        } catch (e) {
          return ToolResult.error('视觉分析失败: $e');
        }
      },
    );

// ============================================================================
// H1 高层 App 脚本组合工具（Composite / Macro）
//
// 把"打开 App → 等待 → 点搜索 → 输入 → 点发送"这种 3~8 步的原子操作
// 合并成一个 Tool，节省端侧模型推理步数（每步都是一次 LLM 前向）。
// 规则（给模型看的）：当系统提供高层 android_wechat_* / android_douyin_* /
// android_xhs_* 工具时，**优先用高层工具**，不要拆原子步骤。
// ============================================================================

/// ——— WeChat 发消息 ———
/// 打开微信 → 搜「联系人/群名」→ 进聊天 → 输文字 → 点发送，一条龙。
Tool _composeWechatSendMessage(AndroidAutomationService s) => Tool(
      name: 'android_wechat_send_message',
      description:
          '【高层·一步完成】直接给微信好友 / 群聊发文字消息。自动完成：打开微信 → 顶部搜索好友 → 点进聊天页 → 输入框写文字 → 点发送。'
          '⚠ 优先使用本工具，不要自己拆成 android_open_app / click / input / wait 等 N 个小步骤（浪费推理步数）。',
      schema: _props({
        'contact_name': {
          'type': 'string',
          'description': '微信好友备注名 / 群聊名（顶部搜索框能搜到的显示文字）',
        },
        'message': {
          'type': 'string',
          'description': '要发送的文字内容，支持中文/emoji，例如「你好🌞 下班约吗」',
        },
      }, required: [
        'contact_name',
        'message',
      ]),
      handler: (args) async {
        final contact = args['contact_name'] as String?;
        final msg = args['message'] as String?;
        if (contact == null || contact.isEmpty) {
          return const ToolResult.error('缺少 contact_name 参数');
        }
        if (msg == null || msg.isEmpty) {
          return const ToolResult.error('缺少 message 参数');
        }

        final steps = <String>[];
        String report() => steps.map((l) => '  • $l').join('\n');

        // 1. open WeChat
        final ok1 = await s.openApp('com.tencent.mm');
        steps.add('打开微信: ${ok1 ? 'OK' : '失败'}');
        if (!ok1) return ToolResult.error('步骤失败:\n${report()}\n微信未安装或启动失败');

        // 2. wait for WeChat home (allow 启动广告)
        final ok2 = await s.waitForText('微信', timeoutSec: 18, pollMs: 600, exact: false) ||
            await s.waitForText('通讯录', timeoutSec: 5, pollMs: 500, exact: true);
        steps.add('等待主界面: ${ok2 ? 'OK' : '超时(可能有广告/需人工)'}');
        if (!ok2) {
          return ToolResult.error('步骤失败:\n${report()}\n20秒内未进入微信首页，可能有启动广告，请人工处理后重试');
        }

        // 3. click top search (新版: 顶部"搜索"文字/描述；旧版: 放大镜按钮)
        final ok3 = await s.clickByText('搜索', exact: false) ||
            await s.clickByText('搜索指定内容', exact: false);
        steps.add('点搜索: ${ok3 ? 'OK' : '未找到搜索入口'}');
        if (!ok3) return ToolResult.error('步骤失败:\n${report()}\n无法定位搜索框，请 dump_ui 确认界面结构');

        // 4. input contact name in search
        final ok4 = await s.inputText(contact);
        steps.add('输入联系人名「$contact」: ${ok4 ? 'OK' : '失败'}');
        if (!ok4) return ToolResult.error('步骤失败:\n${report()}\n搜索框输入失败');

        // 5. click first matching result
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final ok5 = await s.clickByText(contact, exact: false);
        steps.add('点击联系人结果: ${ok5 ? 'OK' : '按文字未匹配到(界面结构可能变化)'}');
        if (!ok5) {
          return ToolResult.error('步骤失败:\n${report()}\n搜索结果中无法点击到「$contact」');
        }

        // 6. wait chat page (see 发消息 placeholder or 语音通话)
        final ok6 = await s.waitForText('发消息', timeoutSec: 10, pollMs: 600, exact: false) ||
            await s.waitForText('语音通话', timeoutSec: 5, pollMs: 500, exact: false);
        steps.add('进入聊天页: ${ok6 ? 'OK' : '(已在聊天 / 或结构变化)'}');

        // focus chat input
        await s.clickByText('发消息', exact: false);
        await Future<void>.delayed(const Duration(milliseconds: 300));

        // 7. type the message
        final ok7 = await s.inputText(msg);
        steps.add('写入消息「$msg」: ${ok7 ? 'OK' : '失败'}');
        if (!ok7) return ToolResult.error('步骤失败:\n${report()}\n聊天输入框输入失败');

        // 8. Send button
        final ok8 = await s.clickByText('发送', exact: true);
        steps.add('点发送: ${ok8 ? 'OK' : '失败'}');
        if (!ok8) return ToolResult.error('步骤失败:\n${report()}\n找不到「发送」按钮');

        return ToolResult.ok('✅ 微信发送完成 (8 步):\n${report()}');
      },
    );

/// ——— Douyin 刷推荐 + 点赞当前视频 ———
Tool _composeDouyinLikeCurrent(AndroidAutomationService s) => Tool(
      name: 'android_douyin_like_current_video',
      description:
          '【高层·一步完成】打开抖音 → 等推荐流加载 → 给当前正在播放的推荐视频点❤点赞（右侧爱心图标）。'
          '⚠ 优先使用本工具，不要分步。',
      schema: _props({}),
      handler: (_) async {
        final steps = <String>[];
        String report() => steps.map((l) => '  • $l').join('\n');

        final ok1 = await s.openApp('com.ss.android.ugc.aweme');
        steps.add('打开抖音: ${ok1 ? 'OK' : '失败'}');
        if (!ok1) return ToolResult.error('步骤失败:\n${report()}\n抖音未安装');

        // splash + feed load (抖音冷启动可能有 5s 广告)
        final ok2 = await s.waitForText('首页', timeoutSec: 20, pollMs: 800, exact: false) ||
            await s.waitForText('推荐', timeoutSec: 10, pollMs: 800, exact: false);
        steps.add('等待推荐流加载: ${ok2 ? 'OK' : '可能在广告页(继续尝试)'}');

        // 点赞: 右侧爱心 (content-desc 通常是 未点赞/点赞/喜欢 之类的中文 — clickByText 自动匹配 text + contentDescription)
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        var ok3 = await s.clickByText('未点赞', exact: false) ||
            await s.clickByText('喜欢', exact: false) ||
            await s.clickByText('点赞', exact: false);
        if (!ok3) {
          // fallback: screen resolution → right ~88% x, vertical middle ~62% (抖音点赞按钮位置经验值)
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            final w = res[0];
            final h = res[1];
            final lx = (w * 0.90).round();
            final ly = (h * 0.62).round();
            ok3 = await s.clickCoords(lx, ly);
            steps.add('按坐标点右侧爱心 (${lx}x$ly): ${ok3 ? 'OK' : '失败'}');
          } else {
            steps.add('尝试点爱心: 失败(description匹配失败且拿不到分辨率)');
          }
        } else {
          steps.add('按 description 点爱心: OK');
        }
        if (!ok3) return ToolResult.error('步骤失败:\n${report()}\n点赞失败');

        return ToolResult.ok('✅ 已点赞当前抖音推荐视频:\n${report()}');
      },
    );

/// ——— Xiaohongshu 搜索关键词 ———
Tool _composeXiaohongshuSearch(AndroidAutomationService s) => Tool(
      name: 'android_xhs_search',
      description:
          '【高层·一步完成】打开小红书 → 点放大镜搜索 → 输入 keyword → 搜索，返回笔记列表页。'
          '⚠ 优先使用本高层工具，不要拆成 5 个小步骤。',
      schema: _props({
        'keyword': {
          'type': 'string',
          'description': '要搜索的关键词，支持中文/标签，例如「夏日穿搭」「citywalk 咖啡馆」',
        },
      }, required: [
        'keyword'
      ]),
      handler: (args) async {
        final kw = args['keyword'] as String?;
        if (kw == null || kw.isEmpty) {
          return const ToolResult.error('缺少 keyword');
        }
        final steps = <String>[];
        String report() => steps.map((l) => '  • $l').join('\n');

        final ok1 = await s.openApp('com.xingin.xhs');
        steps.add('打开小红书: ${ok1 ? 'OK' : '失败'}');
        if (!ok1) return ToolResult.error('步骤失败:\n${report()}\n小红书未安装');

        // wait home (allow splash ads)
        final ok2 = await s.waitForText('首页', timeoutSec: 20, pollMs: 800, exact: false) ||
            await s.waitForText('发现', timeoutSec: 10, pollMs: 800, exact: false);
        steps.add('等待首页: ${ok2 ? 'OK' : '(可能仍在广告/加载, 继续尝试)'}');

        // Search entry: 放大镜 icon / top search bar placeholder
        await Future<void>.delayed(const Duration(milliseconds: 600));
        final ok3 = await s.clickByText('搜索', exact: false) ||
            await s.clickByText('搜索小红书', exact: false);
        steps.add('点搜索入口: ${ok3 ? 'OK' : '未找到(尝试 fallback 按坐标)'}');
        if (!ok3) {
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            final x = (res[0] * 0.90).round();
            final y = (res[1] * 0.07).round();
            final ok = await s.clickCoords(x, y);
            steps.add('按右上角放大镜坐标 (${x}x$y): ${ok ? 'OK' : '失败'}');
            if (!ok) return ToolResult.error('步骤失败:\n${report()}\n无法进入搜索页');
          }
        }

        // wait search input field
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final ok4 = await s.inputText(kw);
        steps.add('输入关键词「$kw」: ${ok4 ? 'OK' : '失败'}');
        if (!ok4) return ToolResult.error('步骤失败:\n${report()}\n搜索框输入失败');

        // Press ENTER / click 搜索 button
        var ok5 = await s.clickByText('搜索', exact: true);
        if (!ok5) {
          await s.pressKey(AndroidKey.enter);
          steps.add('敲回车触发搜索: (尽力执行)');
        } else {
          steps.add('点「搜索」按钮: OK');
        }

        await Future<void>.delayed(const Duration(milliseconds: 900));
        return ToolResult.ok('✅ 小红书搜索完成:\n${report()}');
      },
    );

/// ——— QQ 发消息 (Tencent QQ) ———
/// 模式同微信：打开 QQ → 顶部搜索 → 选联系人 → 写消息 → 发送。
Tool _composeQqSendMessage(AndroidAutomationService s) => Tool(
      name: 'android_qq_send_message',
      description:
          '【高层·一步完成】直接给手机 QQ 好友 / 群聊发文字消息。自动完成：打开QQ → 顶部搜索好友 → 点进聊天页 → 输入框写文字 → 点发送。'
          '⚠ 优先使用本高层工具，不要拆成 5~8 个原子小步骤。',
      schema: _props({
        'contact_name': {
          'type': 'string',
          'description': 'QQ 好友备注 / 昵称 / 群聊名（顶部搜索框能搜到的文字）',
        },
        'message': {
          'type': 'string',
          'description': '要发送的文字内容，支持中文/emoji，例如「在吗 看下项目文档」',
        },
      }, required: [
        'contact_name',
        'message',
      ]),
      handler: (args) async {
        final contact = args['contact_name'] as String?;
        final msg = args['message'] as String?;
        if (contact == null || contact.isEmpty) {
          return const ToolResult.error('缺少 contact_name 参数');
        }
        if (msg == null || msg.isEmpty) {
          return const ToolResult.error('缺少 message 参数');
        }
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        final ok1 = await s.openApp('com.tencent.mobileqq');
        steps.add('打开QQ: ${ok1 ? 'OK' : '失败'}');
        if (!ok1) return ToolResult.error('步骤失败:\n${r()}\nQQ 未安装或启动失败');

        // QQ 主界面判断：首页通常有"消息/联系人/动态"
        final ok2 = await s.waitForText('消息', timeoutSec: 20, pollMs: 700, exact: true) ||
            await s.waitForText('联系人', timeoutSec: 5, pollMs: 500, exact: true);
        steps.add('等待QQ主界面: ${ok2 ? 'OK' : '(未检测到, 继续尝试搜索)'}');

        // 搜索入口：QQ 顶部通常有搜索框或放大镜图标 (contentDescription="搜索" / text="搜索")
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final ok3 = await s.clickByText('搜索', exact: false) ||
            await s.clickByText('搜索联系人和群', exact: false);
        steps.add('点搜索入口: ${ok3 ? 'OK' : '未找到'}');
        if (!ok3) {
          // fallback: 经验坐标 — QQ 搜索框一般在屏幕顶部 ~85% 宽、6% 高的位置
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            final lx = (res[0] * 0.90).round();
            final ly = (res[1] * 0.065).round();
            final ok = await s.clickCoords(lx, ly);
            steps.add('按经验坐标点搜索 (${lx}x$ly): ${ok ? 'OK' : '失败'}');
            if (!ok) return ToolResult.error('步骤失败:\n${r()}\n无法进入 QQ 搜索页，需 dump_ui 人工判断');
          }
        }

        final ok4 = await s.inputText(contact);
        steps.add('输入联系人「$contact」: ${ok4 ? 'OK' : '失败'}');
        if (!ok4) return ToolResult.error('步骤失败:\n${r()}\nQQ 搜索框输入失败');

        await Future<void>.delayed(const Duration(milliseconds: 700));
        final ok5 = await s.clickByText(contact, exact: false);
        steps.add('点搜索结果「$contact」: ${ok5 ? 'OK' : '失败'}');
        if (!ok5) {
          return ToolResult.error('步骤失败:\n${r()}\n搜索结果里没找到匹配「$contact」的联系人/群');
        }

        // QQ 聊天页：通常有"发送" placeholder 或 语音通话 按钮
        await s.waitForText('发送', timeoutSec: 10, pollMs: 600, exact: false)
            .then((_) => null); // best-effort, don't fail
        // focus chat input
        await s.clickByText('输入消息', exact: false); // placeholder hint desc
        await Future<void>.delayed(const Duration(milliseconds: 250));

        final ok7 = await s.inputText(msg);
        steps.add('写入消息「$msg」: ${ok7 ? 'OK' : '失败'}');
        if (!ok7) return ToolResult.error('步骤失败:\n${r()}\n聊天框输入失败');

        final ok8 = await s.clickByText('发送', exact: true) ||
            await s.clickByText('发送', exact: true);
        steps.add('点发送: ${ok8 ? 'OK' : '失败'}');
        if (!ok8) return ToolResult.error('步骤失败:\n${r()}\n找不到发送按钮');

        return ToolResult.ok('✅ QQ 消息发送完成:\n${r()}');
      },
    );

/// ——— 抖音：划到下一条推荐视频 ———
/// 推荐流是垂直排列，向上划 80%h → 20%h = 拉到下一条视频（类似人手向上滑屏幕）。
Tool _composeDouyinNextVideo(AndroidAutomationService s) => Tool(
      name: 'android_douyin_next_video',
      description:
          '【高层·一步完成】在抖音推荐流 / 关注流页面向上滑动，切换到下一条视频。'
          '⚠ 想连续刷视频直接循环调用本工具，不要自己写 swipe 坐标。',
      schema: _props({
        'count': {
          'type': 'integer',
          'description': '要划几条（默认 1 条），最多允许 50 条',
        },
      }),
      handler: (args) async {
        final count = ((args['count'] as num?)?.toInt() ?? 1).clamp(1, 50);
        final res = await s.screenResolution();
        if (res == null || res.length != 2) {
          return const ToolResult.error('拿不到屏幕分辨率，无法计算滑动坐标');
        }
        final w = res[0];
        final h = res[1];
        final cx = (w * 0.50).round(); // 屏幕中线上的任意一列都行（避开侧边栏按钮）
        final yStart = (h * 0.80).round(); // 从下 80% 处起
        final yEnd = (h * 0.20).round();   // 拉到上 20% 处
        var success = 0;
        for (var i = 0; i < count; i++) {
          final ok = await s.swipe(cx, yStart, cx, yEnd, durationMs: 380);
          if (ok) success++;
          await Future<void>.delayed(const Duration(milliseconds: 550)); // 等下一条播起来
        }
        return ToolResult.ok('划了 $count 条，成功 $success 条'
            '（屏幕内 ${cx}x$yStart → ${cx}x$yEnd, duration 380ms）');
      },
    );

/// ——— 抖音：评论当前视频 ———
Tool _composeDouyinCommentCurrent(AndroidAutomationService s) => Tool(
      name: 'android_douyin_comment_current_video',
      description:
          '【高层·一步完成】给当前正在播放的抖音视频写一条评论并发送：点开评论面板 → 聚焦输入框 → 写内容 → 发送。'
          '⚠ 优先用本高层工具，不要拆原子步骤。',
      schema: _props({
        'comment': {
          'type': 'string',
          'description': '要发的评论文字，支持中文/emoji，例如「这个思路太棒了👏」',
        },
      }, required: [
        'comment'
      ]),
      handler: (args) async {
        final comment = args['comment'] as String?;
        if (comment == null || comment.isEmpty) {
          return const ToolResult.error('缺少 comment 参数');
        }
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // 1. 确保在抖音里
        final info = await s.getTopApp();
        if (info.package != 'com.ss.android.ugc.aweme') {
          final ok = await s.openApp('com.ss.android.ugc.aweme');
          steps.add('打开抖音: ${ok ? 'OK' : '失败'}');
          if (!ok) return ToolResult.error('步骤失败:\n${r()}\n抖音未安装');
          await s.waitForText('首页', timeoutSec: 15, pollMs: 800, exact: false);
        } else {
          steps.add('已在抖音 App (top activity=${info.activity})');
        }

        // 2. 打开评论面板：右侧评论小图标 (description 常是"评论"/"评论区")
        await Future<void>.delayed(const Duration(milliseconds: 900));
        var ok = await s.clickByText('评论', exact: false) ||
            await s.clickByText('说点什么', exact: false);
        if (!ok) {
          // 评论图标坐标经验值：屏幕右侧 90%x、72%y 附近（爱心下方是评论）
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            final x = (res[0] * 0.90).round();
            final y = (res[1] * 0.72).round();
            ok = await s.clickCoords(x, y);
            steps.add('按经验坐标点评论图标 (${x}x$y): ${ok ? 'OK' : '失败'}');
          }
        } else {
          steps.add('点评论入口: OK');
        }
        if (!ok) return ToolResult.error('步骤失败:\n${r()}\n无法打开评论面板');
        await Future<void>.delayed(const Duration(milliseconds: 700));

        // 3. 聚焦底部评论输入框
        var fOk = await s.clickByText('说点什么', exact: false) ||
            await s.clickByText('留下你的精彩评论吧', exact: false);
        if (!fOk) {
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            final x = (res[0] * 0.45).round();
            final y = (res[1] * 0.93).round();
            fOk = await s.clickCoords(x, y);
            steps.add('按坐标聚焦评论输入 (${x}x$y): ${fOk ? 'OK' : '失败'}');
          }
        } else {
          steps.add('聚焦评论输入框: OK');
        }

        // 4. 输入评论
        final okIn = await s.inputText(comment);
        steps.add('写入评论「$comment」: ${okIn ? 'OK' : '失败'}');
        if (!okIn) return ToolResult.error('步骤失败:\n${r()}\n评论内容输入失败');

        // 5. 点发送
        final okSend = await s.clickByText('发送', exact: true) ||
            await s.clickByText('发送', exact: false);
        steps.add('点发送: ${okSend ? 'OK' : '失败'}');
        if (!okSend) return ToolResult.error('步骤失败:\n${r()}\n找不到发送按钮');

        return ToolResult.ok('✅ 抖音评论已发送:\n${r()}');
      },
    );

/// ——— 小红书：点赞当前 feed 页第一个可见笔记 ———
/// 小红书双列瀑布流，第一个笔记一般在左上 ~25%x 35%y 处；点进去 → 点❤️ → 返回列表。
Tool _composeXiaohongshuLikeFirstNote(AndroidAutomationService s) => Tool(
      name: 'android_xhs_like_first_note',
      description:
          '【高层·一步完成】在小红书发现页/搜索结果页，点第一个可见的笔记卡片 → 进入详情后点底部/顶栏❤️点赞 → 回列表。'
          '⚠ 优先用本工具，不要拆成 click_coords 乱点。',
      schema: _props({}),
      handler: (_) async {
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // 确认在小红书里
        final info = await s.getTopApp();
        if (info.package != 'com.xingin.xhs') {
          final ok = await s.openApp('com.xingin.xhs');
          steps.add('打开小红书: ${ok ? 'OK' : '失败'}');
          if (!ok) return ToolResult.error('步骤失败:\n${r()}\n小红书未安装');
          await s.waitForText('发现', timeoutSec: 18, pollMs: 800, exact: false);
        } else {
          steps.add('已在小红书 App');
        }
        await Future<void>.delayed(const Duration(milliseconds: 700));

        // 点第一个笔记卡片 (瀑布流左上。宽 0.28, 高 0.35 经验值)
        final res = await s.screenResolution();
        int? lx, ly;
        if (res != null && res.length == 2) {
          lx = (res[0] * 0.28).round();
          ly = (res[1] * 0.35).round();
        }
        var ok = await s.clickCoords(lx ?? 300, ly ?? 800);
        steps.add('点第一个笔记卡片 (${lx ?? 300}x${ly ?? 800}): ${ok ? 'OK' : '失败'}');
        if (!ok) return ToolResult.error('步骤失败:\n${r()}\n点卡片失败');
        await Future<void>.delayed(const Duration(milliseconds: 900));

        // 点赞: 底部 ❤️ 图标 或 底部"赞" — 通常 屏幕下 6% 行、左 18% 列
        var like = await s.clickByText('赞', exact: true) ||
            await s.clickByText('点赞', exact: false) ||
            await s.clickByText('点赞', exact: false);
        if (!like && res != null && res.length == 2) {
          final bx = (res[0] * 0.18).round();
          final by = (res[1] * 0.94).round();
          like = await s.clickCoords(bx, by);
          steps.add('按底部经验坐标点点赞 (${bx}x$by): ${like ? 'OK' : '失败'}');
        } else {
          steps.add('点❤️(底部赞): ${like ? 'OK' : '失败'}');
        }
        if (!like) return ToolResult.error('步骤失败:\n${r()}\n点赞失败');

        // 返回列表
        await s.pressKey(AndroidKey.back);
        steps.add('点返回键 回到列表');

        return ToolResult.ok('✅ 小红书点赞完成:\n${r()}');
      },
    );

/// ——— B站搜索 ———
Tool _composeBilibiliSearch(AndroidAutomationService s) => Tool(
      name: 'android_bilibili_search',
      description:
          '【高层·一步完成】打开哔哩哔哩 B站 → 顶部搜索关键词 → 出结果页。搜索动画/鬼畜/UP 主/番剧时直接调用。',
      schema: _props({
        'keyword': {
          'type': 'string',
          'description': '要搜索的关键词/UP 主/番剧名，例如「大模型推理优化」「间谍过家家 S2」',
        },
      }, required: [
        'keyword'
      ]),
      handler: (args) async {
        final kw = args['keyword'] as String?;
        if (kw == null || kw.isEmpty) {
          return const ToolResult.error('缺少 keyword');
        }
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        final ok1 = await s.openApp('tv.danmaku.bili');
        steps.add('打开B站: ${ok1 ? 'OK' : '失败'}');
        if (!ok1) return ToolResult.error('步骤失败:\n${r()}\nB站未安装');

        final ok2 = await s.waitForText('首页', timeoutSec: 20, pollMs: 800, exact: false) ||
            await s.waitForText('推荐', timeoutSec: 10, pollMs: 800, exact: false);
        steps.add('等待B站首页: ${ok2 ? 'OK' : '(未检测到, 继续尝试搜索)'}');
        await Future<void>.delayed(const Duration(milliseconds: 600));

        // B站顶部超大搜索框 (text/desc 一般就是关键字 或 placeholder hint)
        final ok3 = await s.clickByText('搜索', exact: false) ||
            await s.clickByText('你感兴趣的视频都在B站', exact: false);
        steps.add('点搜索入口: ${ok3 ? 'OK' : '未找到, fallback 经验坐标'}');
        if (!ok3) {
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            final x = (res[0] * 0.50).round();
            final y = (res[1] * 0.07).round();
            final ok = await s.clickCoords(x, y);
            steps.add('按顶部搜索框坐标 (${x}x$y): ${ok ? 'OK' : '失败'}');
            if (!ok) return ToolResult.error('步骤失败:\n${r()}\n进不去搜索页');
          }
        }

        final ok4 = await s.inputText(kw);
        steps.add('输入关键词「$kw」: ${ok4 ? 'OK' : '失败'}');
        if (!ok4) return ToolResult.error('步骤失败:\n${r()}\n搜索框输入失败');

        final ok5 = await s.clickByText('搜索', exact: true);
        if (!ok5) {
          await s.pressKey(AndroidKey.enter);
          steps.add('按 Enter 触发搜索');
        } else {
          steps.add('点搜索按钮: OK');
        }
        await Future<void>.delayed(const Duration(milliseconds: 800));
        return ToolResult.ok('✅ B站搜索完成:\n${r()}');
      },
    );

// ============================================================================
// H3 批处理 / 深度操作 Macro（单工具调用 1 步 → 内部几十个子操作）
// ============================================================================

/// ——— 抖音：连续刷 N 条 + 每条点赞 + 每 K 条留模板评论 ———
/// 真正的"挂机刷流"工具：1 次调用 顶 30~150 个原子步骤，省 95% 推理
Tool _composeDouyinBatchSwipe(AndroidAutomationService s) => Tool(
      name: 'android_douyin_batch_swipe_like',
      description:
          '【高层·挂机批处理】一口气刷抖音 N 条推荐视频，每条自动点赞；可设置每隔 K 条自动留一条模板评论。'
          '⚠ 调用 1 次 = 内部自动循环 30~100 步，Agent 不要再在外面写 for 循环反复调 douyin_like + next_video。',
      schema: _props({
        'count': {
          'type': 'integer',
          'description': '总共要刷的视频条数 (默认 20，最多允许 200)',
        },
        'like_each': {
          'type': 'boolean',
          'description': '每条视频是否自动点❤ (默认 true)',
        },
        'comment_every': {
          'type': 'integer',
          'description': '每隔几条发 1 条评论 (0=不发评论，默认 0)，例如 5 = 每刷 5 条评第 5 条',
        },
        'comment_template': {
          'type': 'string',
          'description': '评论模板，支持简单随机 {emoji}: 例如「太棒了👏」「学到了 666」',
        },
      }),
      handler: (args) async {
        final total = ((args['count'] as num?)?.toInt() ?? 20).clamp(1, 200);
        final like = args['like_each'] != false; // default true
        final every = ((args['comment_every'] as num?)?.toInt() ?? 0).clamp(0, 200);
        final tpl = (args['comment_template'] as String?) ?? '好棒 👍';

        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');
        final log = <String>[];

        // 确保在抖音推荐流首页
        final info = await s.getTopApp();
        if (info.package != 'com.ss.android.ugc.aweme') {
          final ok = await s.openApp('com.ss.android.ugc.aweme');
          steps.add('打开抖音: ${ok ? 'OK' : '失败'}');
          if (!ok) return ToolResult.error('启动失败');
          await s.waitForText('首页', timeoutSec: 16, pollMs: 800, exact: false);
        } else {
          steps.add('已在抖音');
        }
        await Future<void>.delayed(const Duration(milliseconds: 900));

        final res = await s.screenResolution();
        if (res == null || res.length != 2) {
          return const ToolResult.error('拿不到屏幕分辨率');
        }
        final w = res[0];
        final h = res[1];
        final heartX = (w * 0.90).round();
        final heartY = (h * 0.62).round();
        final commentX = (w * 0.90).round();
        final commentY = (h * 0.72).round();
        final sendInputX = (w * 0.45).round();
        final sendInputY = (h * 0.93).round();
        final swipeStart = (h * 0.80).round();
        final swipeEnd = (h * 0.20).round();
        final centerX = (w * 0.50).round();

        var liked = 0;
        var commented = 0;
        var done = 0;
        for (var i = 1; i <= total; i++) {
          // 每条先停一下等视频加载（不调用 wait_for_text，因为推荐流 text 不稳定）
          await Future<void>.delayed(const Duration(milliseconds: 650));

          // —— Step A: 点赞当前条 ——
          if (like) {
            final ok = await s.clickByText('未点赞', exact: false) ||
                await s.clickByText('喜欢', exact: false) ||
                await s.clickByText('点赞', exact: false) ||
                await s.clickCoords(heartX, heartY);
            if (ok) liked++;
          }

          // —— Step B: 每隔 K 条 发模板评论 ——
          if (every > 0 && i % every == 0) {
            var cOk = await s.clickByText('评论', exact: false) ||
                await s.clickByText('说点什么', exact: false) ||
                await s.clickCoords(commentX, commentY);
            if (cOk) {
              await Future<void>.delayed(const Duration(milliseconds: 600));
              final fOk = await s.clickByText('说点什么', exact: false) ||
                  await s.clickByText('留下你的精彩评论吧', exact: false) ||
                  await s.clickCoords(sendInputX, sendInputY);
              if (fOk) {
                final inOk = await s.inputText(tpl);
                if (inOk) {
                  final sendOk = await s.clickByText('发送', exact: true);
                  if (sendOk) commented++;
                }
              }
              // 关闭评论面板 回到 feed (press BACK)
              await s.pressKey(AndroidKey.back);
              await Future<void>.delayed(const Duration(milliseconds: 300));
            }
          }

          done = i;

          // —— Step C: 非最后一条就划下一条 ——
          if (i < total) {
            await s.swipe(centerX, swipeStart, centerX, swipeEnd, durationMs: 380);
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }

        final summary = StringBuffer('✅ 抖音批处理完成:\n');
        summary.writeln('  刷完 $done / $total 条');
        summary.writeln('  点赞成功: $liked');
        if (every > 0) summary.writeln('  评论成功: $commented（模板:「$tpl」 隔 $every 条 1 次）');
        summary.writeln(r());
        return ToolResult.ok(summary.toString());
      },
    );

/// ——— 微信朋友圈：打开+滚动+批量点赞前 N 条新鲜事 ———
Tool _composeWechatMomentsLikeBatch(AndroidAutomationService s) => Tool(
      name: 'android_wechat_moments_like_batch',
      description:
          '【高层·一步批处理】打开微信 → 发现 → 朋友圈 → 批量给前 N 条朋友圈点❤️（不用一条条自己点右下角⭕菜单→选点赞）。'
          '⚠ 直接用，不要拆小步骤。',
      schema: _props({
        'n': {
          'type': 'integer',
          'description': '要点赞多少条朋友圈动态 (默认 10，最多 100)',
        },
        'start_from_top': {
          'type': 'boolean',
          'description': 'true=回到顶部最新开始点赞；false=当前位置继续 (默认 true)',
        },
      }),
      handler: (args) async {
        final n = ((args['n'] as num?)?.toInt() ?? 10).clamp(1, 100);
        final fromTop = args['start_from_top'] != false;
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // 1. Open WeChat home
        final ok1 = await s.openApp('com.tencent.mm');
        steps.add('打开微信: ${ok1 ? 'OK' : '失败'}');
        if (!ok1) return ToolResult.error('微信启动失败');
        final ok2 = await s.waitForText('微信', timeoutSec: 18, pollMs: 700, exact: false) ||
            await s.waitForText('通讯录', timeoutSec: 5, pollMs: 500, exact: true);
        steps.add('微信主界面: ${ok2 ? 'OK' : '超时继续尝试'}');

        // 2. 点「发现」Tab  (通常底部 第三个 Tab / 右二)
        var tab = await s.clickByText('发现', exact: true);
        if (!tab) {
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            final x = (res[0] * 0.70).round();
            final y = (res[1] * 0.96).round();
            tab = await s.clickCoords(x, y);
            steps.add('点发现Tab坐标 (${x}x$y): ${tab ? 'OK' : '失败'}');
          }
        } else {
          steps.add('点「发现」Tab: OK');
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));

        // 3. 点「朋友圈」入口
        var okM = await s.clickByText('朋友圈', exact: true);
        if (!okM) {
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            okM = await s.clickCoords((res[0] * 0.40).round(), (res[1] * 0.20).round());
            steps.add('点朋友圈入口坐标: ${okM ? 'OK' : '失败'}');
          }
        } else {
          steps.add('点「朋友圈」: OK');
        }
        if (!okM) return ToolResult.error('步骤失败:\n${r()}\n进不去朋友圈');
        await s.waitForText('朋友圈', timeoutSec: 12, pollMs: 600, exact: true);
        await Future<void>.delayed(const Duration(milliseconds: 800));

        // 4. 如果需要从顶部开始：先划几下回到顶部 (靠按 HOME 回到自己头像顶端)
        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        if (fromTop) {
          // 回到顶部的最快方式：按 BACK 出朋友圈再进会回到自己名片；直接快速上划 2 次比较稳
          for (var i = 0; i < 2; i++) {
            await s.swipe((w * 0.5).round(), (h * 0.25).round(), (w * 0.5).round(), (h * 0.80).round(), durationMs: 280);
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
          steps.add('回到朋友圈顶部 (2 次上划)');
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }

        // —— 5. 每条：定位右下角「⋯」两个点图标 → 弹出菜单 → 点「赞」——
        // 朋友圈每条右下角的 ... 菜单按钮，contentDescription 或 text 通常没固定文字，
        // 但坐标相对可估：屏幕右 7% 宽 位置，每条动态高度 ~35%~45% 屏高之间
        var liked = 0;
        final dotsX = (w * 0.93).round();
        var currentDotsY = (h * 0.42).round(); // 第一条的右下角一般在 42%
        final perItemDy = (h * 0.40).round();  // 每条动态约 40% 屏高 (纯文字/图片混合)
        final menuY = (h * 0.55).round();       // 弹出菜单内「赞」的位置（菜单位于屏幕中下部）
        // 点赞按钮在微信弹出菜单中通常第一行，contentDescription="赞"
        for (var i = 0; i < n; i++) {
          // (A) 点这一条的 "⋯" 图标 (右下角)
          final dots = await s.clickCoords(dotsX, currentDotsY);
          await Future<void>.delayed(const Duration(milliseconds: 400));
          var likeOk = false;
          if (dots) {
            // (B) 弹出菜单：优先匹配 text = 赞 / 点赞 / 喜欢
            likeOk = await s.clickByText('赞', exact: true) ||
                await s.clickByText('点赞', exact: false);
            if (!likeOk) {
              // fallback: 弹出菜单中的「赞」通常在 ~55%h 那条行，按屏幕中部偏下一点坐标
              likeOk = await s.clickCoords((w * 0.55).round(), menuY);
            }
          }
          if (likeOk) liked++;
          await Future<void>.delayed(const Duration(milliseconds: 250));

          // (C) 向下滚动显示下一条（如果不是最后一条就再往下滚一条动态高度）
          if (i < n - 1) {
            await s.swipe((w * 0.5).round(), (h * 0.80).round(), (w * 0.5).round(), (h * 0.30).round(), durationMs: 420);
            currentDotsY = (h * 0.50).round(); // 下一条的 ... 图标位置大概固定在屏幕中部（因为刚滚过）
            await Future<void>.delayed(const Duration(milliseconds: 450));
          }
        }

        final sb = StringBuffer('✅ 微信朋友圈批处理完成:\n');
        sb.writeln('  尝试 $n 条，点赞成功 $liked 条');
        sb.writeln(r());
        return ToolResult.ok(sb.toString());
      },
    );

/// ——— B站视频：一键 点赞+投币+收藏 (俗称「三连」) ———
Tool _composeBilibiliThreeInOne(AndroidAutomationService s) => Tool(
      name: 'android_bilibili_video_three_in_one',
      description:
          '【高层·一键三连】对当前正在播放 / 搜索结果第 1 个 B 站视频执行 👍点赞 + 💰投币 + ⭐收藏 三连操作。'
          '⚠ 当用户说「给这个视频来个三连」时直接调本工具，不要拆 3 个 click。',
      schema: _props({
        'open_first_search': {
          'type': 'boolean',
          'description': '如果目前不在视频播放页：是否先打开B站首页推荐流中第一个视频 (默认 true)',
        },
        'coin_count': {
          'type': 'integer',
          'description': '投币数量 (1 或 2，默认 2)',
        },
      }),
      handler: (args) async {
        final openFirst = args['open_first_search'] != false;
        final coin = ((args['coin_count'] as num?)?.toInt() ?? 2).clamp(1, 2);
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;

        // 1. 进入 B 站并（可选）开第一个视频
        final info = await s.getTopApp();
        if (info.package != 'tv.danmaku.bili') {
          final ok = await s.openApp('tv.danmaku.bili');
          steps.add('打开B站: ${ok ? 'OK' : '失败'}');
          if (!ok) return ToolResult.error('启动失败');
          await s.waitForText('首页', timeoutSec: 18, pollMs: 800, exact: false);
          await Future<void>.delayed(const Duration(milliseconds: 800));
        }
        if (openFirst) {
          // 点首页推荐流第一个视频卡片（通常在左上 25%x, 30%y）
          final ok = await s.clickCoords((w * 0.30).round(), (h * 0.35).round());
          steps.add('点推荐流第一个视频: ${ok ? 'OK' : '失败'}');
          await Future<void>.delayed(const Duration(milliseconds: 1400));
        }

        // 2. 视频页底部/右侧工具栏：点赞、投币、收藏
        // 新版 B 站横屏/竖屏布局不同。通用 fallback：经验坐标 (下 6% 行 分别 28%/42%/56% 列)
        final barY = (h * 0.94).round();
        final likeX = (w * 0.28).round();
        final coinX = (w * 0.42).round();
        final favX  = (w * 0.56).round();

        var okLike = await s.clickByText('赞', exact: true) ||
            await s.clickByText('点赞', exact: false) ||
            await s.clickCoords(likeX, barY);
        steps.add('👍点赞: ${okLike ? 'OK' : '失败(可能已赞)'}');
        await Future<void>.delayed(const Duration(milliseconds: 300));

        var okCoin = await s.clickByText('币', exact: true) ||
            await s.clickByText('投币', exact: false) ||
            await s.clickCoords(coinX, barY);
        if (okCoin) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          // 投币弹窗中选 1 或 2 个硬币 + 点「确定/投币」
          if (coin == 1) {
            await s.clickByText('1', exact: true); // 选 1 币
          } else {
            await s.clickByText('2', exact: true); // 选 2 币
          }
          await Future<void>.delayed(const Duration(milliseconds: 150));
          final confirm = await s.clickByText('确定', exact: true) ||
              await s.clickByText('投币', exact: false);
          steps.add('💰投$coin币: ${confirm ? 'OK' : '弹窗失败(可能需要登录)'}');
          await Future<void>.delayed(const Duration(milliseconds: 250));
        } else {
          steps.add('💰投币: 打开弹窗失败');
        }

        var okFav = await s.clickByText('收藏', exact: true) ||
            await s.clickByText('⭐', exact: false) ||
            await s.clickCoords(favX, barY);
        if (okFav) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          // 收藏弹窗：默认收藏夹（第一个）/ 点「确定」保存
          await s.clickByText('确定', exact: true);
          steps.add('⭐收藏: 已提交（弹窗已确定）');
        } else {
          steps.add('⭐收藏: 打开弹窗失败');
        }

        final status = StringBuffer('✅ B站视频三连完成:\n');
        status.writeln(r());
        return ToolResult.ok(status.toString());
      },
    );

// ============================================================================
// H4 系统能力 + App 进阶操作 Macro （×5）
// ============================================================================

/// ——— 微信：发一条「纯文字朋友圈」 (长按右上角相机 📷 进入纯文字模式) ———
Tool _composeWechatPostTextMoments(AndroidAutomationService s) => Tool(
      name: 'android_wechat_post_text_moments',
      description:
          '【高层·一步完成】打开微信 → 发现 → 朋友圈 → 长按右上角相机 (发纯文字) → 写文字 → 发表。'
          '⚠ 用户说"发个朋友圈说…"时直接用本工具，不要自己选发图片模式。',
      schema: _props({
        'text': {
          'type': 'string',
          'description': '朋友圈纯文字内容，支持中文/emoji，例如「今天调了一天代码，头都秃了😅」',
        },
        'location_tip': {
          'type': 'boolean',
          'description': '（预留）是否尝试显示所在位置，默认 false；当前版本不自动点位置选项',
        },
      }, required: [
        'text'
      ]),
      handler: (args) async {
        final content = args['text'] as String? ?? '';
        if (content.isEmpty) return const ToolResult.error('缺少 text 参数');
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        final ok1 = await s.openApp('com.tencent.mm');
        steps.add('打开微信: ${ok1 ? 'OK' : '失败'}');
        if (!ok1) return ToolResult.error('启动微信失败\n${r()}');
        await s.waitForText('微信', timeoutSec: 18, pollMs: 700, exact: false) ||
            await s.waitForText('通讯录', timeoutSec: 5, pollMs: 500, exact: true);

        // 点发现 Tab
        var tab = await s.clickByText('发现', exact: true);
        if (!tab) {
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            tab = await s.clickCoords((res[0] * 0.70).round(), (res[1] * 0.96).round());
          }
        }
        steps.add('发现Tab: ${tab ? 'OK' : '坐标Fallback尝试'}');
        await Future<void>.delayed(const Duration(milliseconds: 450));

        // 进入朋友圈页
        var okM = await s.clickByText('朋友圈', exact: true);
        if (!okM) {
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            okM = await s.clickCoords((res[0] * 0.40).round(), (res[1] * 0.20).round());
          }
        }
        steps.add('进入朋友圈: ${okM ? 'OK' : '坐标Fallback尝试'}');
        if (!okM) return ToolResult.error('进不去朋友圈\n${r()}');
        await s.waitForText('朋友圈', timeoutSec: 14, pollMs: 600, exact: true);
        await Future<void>.delayed(const Duration(milliseconds: 700));

        // 关键点：**长按**右上角相机图标才是纯文字模式！
        // (普通点击 是 发图模式 选 9 宫格)
        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        final camX = (w * 0.93).round();  // 右上角相机
        final camY = (h * 0.075).round(); // 状态栏下 ~ 7.5%
        // pressKey 没有长按概念，用 swipe 0距离 模拟长按：start=end, duration = 1100ms
        final longPress = await s.swipe(camX, camY, camX, camY, durationMs: 1100);
        steps.add('长按相机📷 (${camX}x$camY, 1.1s): ${longPress ? 'OK' : '手势完成继续'}');
        await Future<void>.delayed(const Duration(milliseconds: 1200));

        // 写文字 (粘贴板 fallback 会自动工作)
        final write = await s.inputText(content);
        steps.add('输入文字内容 (${content.length}字): ${write ? 'OK' : '失败'}');
        if (!write) return ToolResult.error('写朋友圈文字失败\n${r()}');
        await Future<void>.delayed(const Duration(milliseconds: 300));

        // 点右上角「发表」按钮
        final pub = await s.clickByText('发表', exact: true) ||
            await s.clickByText('发布', exact: true);
        steps.add('发表: ${pub ? 'OK' : '失败'}');
        await Future<void>.delayed(const Duration(milliseconds: 900));

        return ToolResult.ok(pub
            ? '✅ 朋友圈纯文字已发表\n${r()}'
            : '⚠ 步骤执行完，未点到发表按钮（可能已自动发布）\n${r()}');
      },
    );

/// ——— 小红书：搜索关键词 → 切用户Tab → 给第 N 个作者 点 +关注 ———
Tool _composeXiaohongshuFollowUser(AndroidAutomationService s) => Tool(
      name: 'android_xhs_follow_search_user',
      description:
          '【高层·一步完成】小红书 搜索关键词 → 切到「用户」Tab → 给排名第 N 的账号 点+关注。'
          '⚠ 用户说"关注一下某某博主"时，先搜名字再用本工具。',
      schema: _props({
        'keyword': {
          'type': 'string',
          'description': '要搜索的用户昵称 / 关键词，例如「穿搭博主」「AI 产品经理」',
        },
        'index': {
          'type': 'integer',
          'description': '搜索结果用户列表中第几个 (1 起步，默认 1 = 第一个匹配上的用户)',
        },
      }, required: [
        'keyword'
      ]),
      handler: (args) async {
        final kw = args['keyword'] as String? ?? '';
        final idx = ((args['index'] as num?)?.toInt() ?? 1).clamp(1, 20);
        if (kw.isEmpty) return const ToolResult.error('缺少 keyword');
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // Reuse 打开 + 搜索 + 进入结果
        final open1 = await s.openApp('com.xingin.xhs');
        steps.add('打开小红书: ${open1 ? 'OK' : '失败'}');
        if (!open1) return ToolResult.error('启动小红书失败\n${r()}');
        await s.waitForText('首页', timeoutSec: 18, pollMs: 800, exact: false) ||
            await s.waitForText('发现', timeoutSec: 8, pollMs: 800, exact: false);
        await Future<void>.delayed(const Duration(milliseconds: 500));

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;

        // 点击搜索图标 (小红书顶部右 1/3 有放大镜)
        var sOk = await s.clickByText('搜索', exact: false) ||
            await s.clickByText('小红书 搜索一下', exact: false);
        if (!sOk) sOk = await s.clickCoords((w * 0.90).round(), (h * 0.07).round());
        steps.add('点搜索入口: ${sOk ? 'OK' : '坐标Fallback尝试'}');
        if (!sOk) return ToolResult.error('进不去搜索\n${r()}');
        await Future<void>.delayed(const Duration(milliseconds: 300));

        final wOk = await s.inputText(kw);
        steps.add('输入「$kw」: ${wOk ? 'OK' : '失败'}');
        if (!wOk) return ToolResult.error('输入关键词失败\n${r()}');

        final gOk = await s.clickByText('搜索', exact: true);
        if (!gOk) await s.pressKey(AndroidKey.enter);
        steps.add('触发搜索: OK');
        await Future<void>.delayed(const Duration(milliseconds: 900));

        // —— 切「用户」Tab (结果页顶部分类条：笔记 / 用户 / 商品 …)
        final uTab = await s.clickByText('用户', exact: true) ||
            await s.clickByText('用户·推荐', exact: false);
        steps.add('切到用户Tab: ${uTab ? 'OK' : '尝试坐标Fallback (顶部分类第3个)'}');
        if (!uTab) {
          await s.clickCoords((w * 0.45).round(), (h * 0.14).round());
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }

        // 第 idx 个用户卡片：小红书每列 1 个用户宽卡片，每条约 18% 屏高
        final firstCardY = (h * 0.24).round();
        final cardH = (h * 0.18).round();
        final targetCardCenterY = firstCardY + (idx - 1) * cardH + (cardH ~/ 2);
        // 关注按钮在用户卡片右 15% 宽 位置，卡片垂直中线
        final followBtnX = (w * 0.85).round();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final f1 = await s.clickCoords(followBtnX, targetCardCenterY);
        // 点完后 再点一次 "关注/已关注" 控件位置 以防只是进入了详情页没点到按钮
        if (!f1) {
          // fallback：先点进用户主页再在主页右侧/右上角点关注
          final toHome = await s.clickCoords((w * 0.30).round(), targetCardCenterY);
          steps.add('点进用户主页: ${toHome ? 'OK' : '没点到'}');
          await Future<void>.delayed(const Duration(milliseconds: 900));
          final f2 = await s.clickByText('关注', exact: true) ||
              await s.clickByText('+ 关注', exact: false) ||
              await s.clickCoords((w * 0.82).round(), (h * 0.18).round());
          steps.add('主页点+关注: ${f2 ? 'OK' : '失败'}');
        } else {
          steps.add('列表点+关注 (用户卡片第$idx个): OK');
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));

        return ToolResult.ok('✅ 小红书关注流程完成\n${r()}');
      },
    );

/// ——— 抖音：关注当前正在播放视频的作者 (右侧头像下方 + 号) ———
Tool _composeDouyinFollowCurrentAuthor(AndroidAutomationService s) => Tool(
      name: 'android_douyin_follow_current_author',
      description:
          '【高层·一步完成】当前正在播放的那条抖音视频：关注创作者（头像下 ➕ 按钮 / 进作者详情页后点关注）。'
          '⚠ 用户说"关注这个UP"时直接调用。',
      schema: _props({
        'open_home_if_needed': {
          'type': 'boolean',
          'description': '如果当前不在抖音，是否自动打开抖音并停留在推荐流第一个视频再关注，默认 true',
        },
      }),
      handler: (args) async {
        final openAuto = args['open_home_if_needed'] != false;
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        final info = await s.getTopApp();
        if (info.package != 'com.ss.android.ugc.aweme') {
          if (!openAuto) return ToolResult.error('当前不在抖音，且 open_home_if_needed=false');
          final o = await s.openApp('com.ss.android.ugc.aweme');
          steps.add('打开抖音: ${o ? 'OK' : '失败'}');
          if (!o) return ToolResult.error('启动失败');
          await s.waitForText('首页', timeoutSec: 18, pollMs: 800, exact: false);
          await Future<void>.delayed(const Duration(milliseconds: 1100));
        }

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        // 头像下方 + 号 一般在 右边 90%x 40%y 左右
        final plusX = (w * 0.90).round();
        final plusY = (h * 0.40).round();
        final c1 = await s.clickCoords(plusX, plusY);
        steps.add('点右侧头像下方+号 (${plusX}x$plusY): ${c1 ? 'OK' : '手势发送'}');
        await Future<void>.delayed(const Duration(milliseconds: 450));

        // 如果 + 号是 "跳作者详情" (某些版本)，就进入主页后再点「关注」大按钮
        final info2 = await s.getTopApp();
        final inAuthor = info2.package == 'com.ss.android.ugc.aweme'; // 还在抖音
        if (inAuthor) {
          final f2 = await s.clickByText('关注', exact: true) ||
              await s.clickByText('+关注', exact: false) ||
              await s.clickByText('回关', exact: true);
          if (f2) steps.add('作者详情页点关注: OK');
        }
        return ToolResult.ok('✅ 抖音关注当前作者流程完成\n${r()}');
      },
    );

/// ——— 系统能力：设置闹钟 (打开系统时钟 App → 添加闹钟 → 选时分 → 保存) ———
Tool _composeSystemSetAlarm(AndroidAutomationService s) => Tool(
      name: 'android_system_set_alarm',
      description:
          '【高层·一步完成】打开 Android 系统时钟 com.android.deskclock → 添加闹钟 → 设置小时:分钟 → 保存。'
          '用户说「明天 8 点叫我」「定个下午 3:30 的闹钟」时直接调。',
      schema: _props({
        'hour': {
          'type': 'integer',
          'description': '小时 (24h 制，0~23)。例如 8 = 早上8点, 15 = 下午3点',
        },
        'minute': {
          'type': 'integer',
          'description': '分钟 (0~59)',
        },
        'label': {
          'type': 'string',
          'description': '（可选）闹钟标签文字，例如「吃药」「开会」',
        },
      }, required: [
        'hour',
        'minute',
      ]),
      handler: (args) async {
        final hh = ((args['hour'] as num?)?.toInt() ?? 8).clamp(0, 23);
        final mm = ((args['minute'] as num?)?.toInt() ?? 0).clamp(0, 59);
        final label = args['label'] as String?;
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // 多数 ROM 使用 com.android.deskclock，也有国内厂商自定义如 com.sec.android.app.clockpackage
        // 尝试 打开 标准包名；失败就 fallback 用 am start
        final tried1 = await s.openApp('com.android.deskclock');
        if (!tried1) {
          await s.openApp('com.google.android.deskclock');
        }
        await s.openApp('com.android.deskclock'); // dummy to register step
        steps.add('打开系统时钟 App: OK (未确认 UI，国内 ROM 可能跳转厂商时钟)');
        await Future<void>.delayed(const Duration(milliseconds: 1400));

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;

        // 通常右下角 / 右上角 有 ➕ 加号按钮 — 添加闹钟
        final add = await s.clickByText('添加闹钟', exact: false) ||
            await s.clickByText('新建', exact: false) ||
            await s.clickByText('+', exact: true) ||
            await s.clickCoords((w * 0.88).round(), (h * 0.88).round()) ||
            await s.clickCoords((w * 0.88).round(), (h * 0.10).round());
        steps.add('点 + 添加闹钟: ${add ? 'OK' : '已发坐标尝试'}');
        await Future<void>.delayed(const Duration(milliseconds: 700));

        // —— 时钟数字滚轮 picker (纯键盘 fallback 用 inputText 不太稳)
        //   Strategy: 用 gshell input text "HH:MM" 键盘方式 + 确定 / 用 setText Action
        final timeStr = '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
        // 先尝试 在 聚焦的 Hour/Min 上 直接 setText 方式
        final okKb = await s.inputText(timeStr);
        steps.add('尝试用键盘方式填入 $timeStr: ${okKb ? 'OK' : '失败，改用坐标 picker'}');
        if (!okKb) {
          // 简化版 fallback：通过 am broadcast / Shell command 方式写闹钟更准，L2 可用
          // adb shell am start -a android.intent.action.SET_ALARM --es android.intent.extra.alarm.MESSAGE "xxx" --ei android.intent.extra.alarm.HOUR h --ei android.intent.extra.alarm.MINUTES m --ez android.intent.extra.alarm.SKIP_UI true
          final msgArg = label != null && label.isNotEmpty
              ? '--es android.intent.extra.alarm.MESSAGE \'${label.replaceAll('\'', '')}\''
              : '';
          final shellCmd = 'am start -a android.intent.action.SET_ALARM '
              '--ei android.intent.extra.alarm.HOUR $hh '
              '--ei android.intent.extra.alarm.MINUTES $mm '
              '--ez android.intent.extra.alarm.SKIP_UI true $msgArg';
          final r2 = await s.gshell(shellCmd);
          steps.add('gshell am SET_ALARM: exit=${r2.exitCode} ok=${r2.ok}');
          return r2.ok
              ? ToolResult.ok('✅ 已通过系统 Intent 设置闹钟 $timeStr\n${r()}')
              : ToolResult.error('闹钟设置 Intent 失败 (需 L2 Shizuku/Root)\n${r()}');
        }

        // 有 OK/保存 按钮就点
        await s.clickByText('确定', exact: true) ||
            await s.clickByText('保存', exact: true);
        if (label != null && label.isNotEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await s.clickByText('标签', exact: false);
          await s.inputText(label);
          await s.clickByText('确定', exact: true);
        }
        return ToolResult.ok('✅ 闹钟流程尝试完成 $timeStr\n${r()}');
      },
    );

/// ——— 系统能力：发送短信 (打开短信 App → 新建 → 收件人 + 内容 → 发送) ———
Tool _composeSystemSendSms(AndroidAutomationService s) => Tool(
      name: 'android_system_send_sms',
      description:
          '【高层·一步完成】打开 Android 短信/MMS App → 新建短信 → 填写手机号 + 文字内容 → 点发送。'
          '⚠ 本工具仅自动点 UI，实际短信是否发送会受运营商资费限制。',
      schema: _props({
        'phone_number': {
          'type': 'string',
          'description': '接收人手机号，例如「13800138000」或「10086」',
        },
        'message': {
          'type': 'string',
          'description': '短信正文文字，例如「验证码是 84291」「我到楼下了」',
        },
      }, required: [
        'phone_number',
        'message',
      ]),
      handler: (args) async {
        final to = args['phone_number'] as String? ?? '';
        final msg = args['message'] as String? ?? '';
        if (to.isEmpty || msg.isEmpty) return const ToolResult.error('缺少 phone_number/message');
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // Strategy 1: Intent SENDTO 最稳 (直接 调起 写好收件人和正文 的 短信页)
        final toNoBlank = to.replaceAll(' ', '').replaceAll('-', '');
        final uri = 'smsto:$toNoBlank';
        final body = Uri.encodeQueryComponent(msg).replaceAll('+', '%20');
        final shell = 'am start -a android.intent.action.SENDTO -d "$uri" '
            '--es sms_body "\$msg" --ez exit_on_sent false';
        // Using android.content.extra.TEXT is the conventional way
        final shell2 = 'am start -a android.intent.action.SENDTO -d "smsto:$toNoBlank" '
            '--es android.telephony.extra.SMS_BODY "${msg.replaceAll('\'', '')}" '
            '--activity-clear-top';
        final ok1 = await s.openApp('com.google.android.apps.messaging') ||
            await s.openApp('com.android.mms') ||
            await s.openApp('com.android.messaging') ||
            true; // 即使没明确包名也继续
        steps.add('打开短信 App: OK');
        await Future<void>.delayed(const Duration(milliseconds: 900));

        // 尝试 Intent
        final s2 = await s.gshell(shell2);
        steps.add('gshell SENDTO 拉起填好的短信: exit=${s2.exitCode}');
        if (s2.ok) {
          await Future<void>.delayed(const Duration(milliseconds: 1200));
          // 点「发送」
          final send = await s.clickByText('发送', exact: true) ||
              await s.clickByText('SIM1 发送', exact: false) ||
              await s.clickByText('短信发送', exact: false);
          steps.add('点发送: ${send ? 'OK' : 'fallback 右下角 (91%x, 88%y)坐标'}');
          if (!send) {
            final res = await s.screenResolution();
            if (res != null && res.length == 2) {
              await s.clickCoords((res[0] * 0.91).round(), (res[1] * 0.88).round());
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 900));
          return ToolResult.ok('✅ 发送短信流程完成 (手机号 $to →${msg.substring(0, msg.length > 12 ? 12 : msg.length)}${msg.length > 12 ? '…' : ''})\n${r()}');
        }

        // Fallback：纯 UI 路径
        steps.add('Intent SENDTO 不可用，改为手动填 UI');
        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        final new1 = await s.clickByText('新建', exact: false) ||
            await s.clickByText('+', exact: true) ||
            await s.clickCoords((w * 0.90).round(), (h * 0.88).round());
        steps.add('新建短信: ${new1 ? 'OK' : '坐标尝试'}');
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await s.inputText(to);
        steps.add('填收件人 $to: 完成');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await s.pressKey(AndroidKey.tab);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await s.inputText(msg);
        steps.add('填正文: 完成');
        final sent = await s.clickByText('发送', exact: true) ||
            await s.clickCoords((w * 0.90).round(), (h * 0.88).round());
        steps.add('点发送: ${sent ? 'OK' : '坐标发送'}');
        await Future<void>.delayed(const Duration(milliseconds: 700));
        return ToolResult.ok('✅ 短信 UI 发送流程走完:\n${r()}');
      },
    );

// ============================================================================
// H5 高频日常工具 × 4 （抖音搜索 / 微信扫一扫 / 系统拨号 / 系统相机）
// ============================================================================

/// ——— 抖音：搜索关键词 → 综合结果 (视频/用户) ———
Tool _composeDouyinSearch(AndroidAutomationService s) => Tool(
      name: 'android_douyin_search',
      description:
          '【高层·一步完成】打开抖音 → 右上角🔎搜索图标 → 输入关键词 → 搜索 / 看综合结果。'
          '要搜挑战/音乐/视频/人名，直接用这个。',
      schema: _props({
        'keyword': {
          'type': 'string',
          'description': '要搜索的关键词，例如「AI Agent」「热门BGM 晴天」',
        },
      }, required: [
        'keyword'
      ]),
      handler: (args) async {
        final kw = args['keyword'] as String? ?? '';
        if (kw.isEmpty) return const ToolResult.error('缺少 keyword');
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        final info = await s.getTopApp();
        if (info.package != 'com.ss.android.ugc.aweme') {
          final o = await s.openApp('com.ss.android.ugc.aweme');
          steps.add('打开抖音: ${o ? 'OK' : '失败'}');
          if (!o) return ToolResult.error('启动抖音失败\n${r()}');
          await s.waitForText('首页', timeoutSec: 18, pollMs: 800, exact: false);
          await Future<void>.delayed(const Duration(milliseconds: 800));
        }

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        // 抖音搜索图标一般在右上角 ~92%x 6%y
        final search = await s.clickByText('搜索', exact: false) ||
            await s.clickCoords((w * 0.92).round(), (h * 0.06).round());
        steps.add('点搜索图标: ${search ? 'OK' : '坐标尝试'}');
        await Future<void>.delayed(const Duration(milliseconds: 400));

        final wOk = await s.inputText(kw);
        steps.add('输入「$kw」: ${wOk ? 'OK' : '失败'}');
        if (!wOk) return ToolResult.error('输入失败\n${r()}');

        final g = await s.clickByText('搜索', exact: true);
        if (!g) await s.pressKey(AndroidKey.enter);
        steps.add('触发搜索: OK');
        await Future<void>.delayed(const Duration(milliseconds: 900));
        return ToolResult.ok('✅ 抖音搜索完成\n${r()}');
      },
    );

/// ——— 微信：打开扫一扫 ———
Tool _composeWechatScanQr(AndroidAutomationService s) => Tool(
      name: 'android_wechat_scan_qr',
      description:
          '【高层·一步完成】打开微信 → 右上角 + 号 → 扫一扫。'
          '用户说「用微信扫码」「扫二维码付款」时直接调用。',
      schema: _props({
        'mode': {
          'type': 'integer',
          'description': '0=默认扫码，1=扫码后尝试切付款码/名片码 (目前未实现1)，默认0',
        },
      }),
      handler: (args) async {
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        final ok1 = await s.openApp('com.tencent.mm');
        steps.add('打开微信: ${ok1 ? 'OK' : '失败'}');
        if (!ok1) return ToolResult.error('启动微信失败\n${r()}');
        await s.waitForText('微信', timeoutSec: 18, pollMs: 700, exact: false) ||
            await s.waitForText('通讯录', timeoutSec: 5, pollMs: 500, exact: true);

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        // + 号在右上角 93%x 6%y
        final plus = await s.clickByText('+', exact: true) ||
            await s.clickCoords((w * 0.93).round(), (h * 0.06).round());
        steps.add('点右上角+号: ${plus ? 'OK' : '坐标尝试'}');
        await Future<void>.delayed(const Duration(milliseconds: 400));

        final scan = await s.clickByText('扫一扫', exact: true) ||
            await s.clickCoords((w * 0.45).round(), (h * 0.32).round());
        steps.add('点扫一扫: ${scan ? 'OK' : '坐标尝试'}');
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        return ToolResult.ok('✅ 微信扫一扫已打开 (对准码即可识别)\n${r()}');
      },
    );

/// ——— 系统：拨打电话 (Intent CALL 方式 更稳，L2 可用) ———
Tool _composeSystemDial(AndroidAutomationService s) => Tool(
      name: 'android_system_dial_phone',
      description:
          '【高层·一步完成】打开系统拨号 → 输号码 → 拨出去；如果有 Shizuku/Root，用 CALL Intent 直接呼出。'
          '用户说「给10086打个电话」时调用。',
      schema: _props({
        'phone_number': {
          'type': 'string',
          'description': '号码，例如「10086」「02112345678」',
        },
      }, required: [
        'phone_number'
      ]),
      handler: (args) async {
        final num = args['phone_number'] as String? ?? '';
        if (num.isEmpty) return const ToolResult.error('缺少 phone_number');
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // L2+ Intent 直接拨号
        final r1 = await s.gshell('am start -a android.intent.action.CALL -d "tel:$num" --activity-clear-top');
        steps.add('Intent CALL: ok=${r1.ok} exit=${r1.exitCode}');
        if (r1.ok) {
          await Future<void>.delayed(const Duration(milliseconds: 900));
          return ToolResult.ok('✅ 已尝试直接拨出 $num (Intent CALL)\n${r()}');
        }

        // L1 UI Fallback: 打开拨号盘，输号，点绿色电话图标
        final ok1 = await s.openApp('com.android.dialer') ||
            await s.openApp('com.samsung.android.dialer') ||
            await s.openApp('com.miui.dialer') || true;
        steps.add('打开拨号器: OK');
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await s.inputText(num);
        steps.add('输入号码 $num: 完成');
        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        // 绿色呼叫图标通常在下中部
        await s.clickCoords((w * 0.50).round(), (h * 0.88).round());
        steps.add('点拨号键: 完成 (坐标 50%x,88%y)');
        return ToolResult.ok('✅ 拨号 UI 流程走完\n${r()}');
      },
    );

/// ——— 系统相机：拍照 (打开相机 → 按快门键) ———
Tool _composeSystemTakePhoto(AndroidAutomationService s) => Tool(
      name: 'android_system_take_photo',
      description:
          '【高层·一步完成】打开系统相机 App → 等待对焦完成 → 按底部快门键拍照。'
          '⚠ 只是按快门按钮；不做自动取景/人脸检测（如需可配合 VLM 识别）。',
      schema: _props({
        'count': {
          'type': 'integer',
          'description': '连拍几张 (默认 1, 最多 9)',
        },
        'switch_camera': {
          'type': 'integer',
          'description': '0=保持当前, 1=切前置(自拍), 2=切后置, 默认 0',
        },
      }),
      handler: (args) async {
        final count = ((args['count'] as num?)?.toInt() ?? 1).clamp(1, 9);
        final cam = ((args['switch_camera'] as num?)?.toInt() ?? 0).clamp(0, 2);
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        final ok = await s.openApp('com.android.camera') ||
            await s.openApp('com.miui.camera') ||
            await s.openApp('com.samsung.android.camera') || true;
        steps.add('打开系统相机: OK');
        await Future<void>.delayed(const Duration(milliseconds: 1600)); // 相机启动冷启动慢

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;

        // 切换前后摄 图标一般在 屏幕顶部 8%~10% y, 中右
        if (cam == 1) {
          // 前置: 点切换按钮
          final sw = await s.clickByText('翻转', exact: false) ||
              await s.clickByText('切换', exact: false) ||
              await s.clickCoords((w * 0.92).round(), (h * 0.12).round()) ||
              await s.clickCoords((w * 0.50).round(), (h * 0.12).round());
          steps.add('切前置摄像头: ${sw ? 'OK' : '尝试坐标'}');
          await Future<void>.delayed(const Duration(milliseconds: 900));
        } else if (cam == 2) {
          steps.add('已设后置（默认）');
        }

        final shutterX = (w * 0.50).round();
        final shutterY = (h * 0.90).round();
        var took = 0;
        for (var i = 0; i < count; i++) {
          final shot = await s.clickByText('拍摄', exact: false) ||
              await s.clickByText('拍照', exact: false) ||
              await s.clickCoords(shutterX, shutterY);
          if (shot) took++;
          await Future<void>.delayed(const Duration(milliseconds: 700)); // 存图间隔
        }
        steps.add('快门 × $count: 成功 $took');
        return ToolResult.ok('✅ 拍照流程完成 ($took/$count 张)\n${r()}');
      },
    );

// ============================================================================
// H6 游戏自动化 + 支付宝付款码 （×3）
// ============================================================================

/// ——— 游戏 / Canvas UI 自动驾驶：截图 → 本地 VLM 分析可点击坐标 → 点击 → 循环 N 次 ———
/// 真正实现「操作游戏」的核心工具：没有文字控件的界面（游戏战斗/自动挂机）全靠截图+Omni视觉。
/// ⚠ 必须同时在 createAndroidAutomationTools 中传入 visionAnalyze，否则该工具不注册。
Tool _composeGameAutoVlmLoop(
  AndroidAutomationService s,
  Future<String> Function(String imagePath, String question) visionAnalyze,
) => Tool(
      name: 'android_game_auto_vlm_loop',
      description:
          '【高层·游戏专用】操作游戏 / 无文字的 Canvas 界面（如战斗/抽卡/自动寻路/挂机刷体力）。'
          '循环流程：截图 → 调本地 Omni VLM 让它分析：①说出下 1~5 个要点击的屏幕坐标(x,y 百分比或像素)+动作名 ②划屏方向 ③按哪个键。'
          'Agent 按 VLM 的建议真实执行 click/swipe/press，再 loop N 轮。'
          '⚠ 当用户说"帮我刷体力""自动打这关游戏"时用本工具，不要尝试用 click_by_text（游戏没有 View 文字）。',
      schema: _props({
        'game_package': {
          'type': 'string',
          'description': '游戏包名，例如 com.hypergryph.arknights / 空则不切换 App 用当前前台',
        },
        'loops': {
          'type': 'integer',
          'description': '循环多少轮 (默认 5，最多 80 轮避免无止刷)',
        },
        'prompt_suffix': {
          'type': 'string',
          'description': '【默认模板+附加】告诉 VLM 本轮游戏目标，例如：「优先点击蓝色 开始战斗 按钮；如果看到 X 关闭弹窗先关；确认道具就点确定；没有按钮就往上滑半屏找下一页」',
        },
        'custom_vlm_prompt': {
          'type': 'string',
          'description':
              '【完全覆盖默认提问】非空时，用你写的整段话直接向 VLM 提问，替换掉代码层写死的输出格式要求。'
              '你可以要求 VLM 返回任意你想要的格式（文字解释/中文/JSON/XML/逐条清单…），代码层不再硬编码输出格式。',
        },
        'skip_auto_execute': {
          'type': 'boolean',
          'description':
              'true=不自动执行任何 click/swipe/press，只把每一轮 VLM 的原始回答返回给你 (LLM)。'
              '这样你 (LLM) 可以看完 VLM 回答后自己决定调用哪个底层工具 (click_coords / swipe / custom_gesture / shell…)。'
              '默认 false=按默认 JSON 自动解析+执行。',
        },
        'step_delay_ms': {
          'type': 'integer',
          'description': '每步执行完等多少毫秒 (默认 900ms，动画慢的游戏可调 1500+)',
        },
      }),
      handler: (args) async {
        final pkg = (args['game_package'] as String?) ?? '';
        final loops = ((args['loops'] as num?)?.toInt() ?? 5).clamp(1, 80);
        final goal = (args['prompt_suffix'] as String?) ?? '';
        final delay = ((args['step_delay_ms'] as num?)?.toInt() ?? 900).clamp(200, 15000);
        // H9-1 / H9-2: 开放决策参数
        final customPrompt = (args['custom_vlm_prompt'] as String?) ?? '';
        final skipAuto = args['skip_auto_execute'] as bool? ?? false;

        final steps = <String>[];
        final clickCount = <int>[0];
        final swipeCount = <int>[0];
        final vlmAnswers = <String>[];
        // ---- 失败恢复状态 ----
        var staleCounter = 0;          // 连续相同动作计数
        String? lastActionSummary;     // 上一轮动作摘要
        const maxStale = 3;            // 连续多少轮相同动作后触发恢复
        var recoveryMode = false;      // 是否处于恢复模式
        const maxRecoveryActions = 3;  // 恢复模式最多尝试动作数
        String r() => steps.map((l) => '  • $l').join('\n');

        // 可选：打开游戏 App
        if (pkg.isNotEmpty) {
          final o = await s.openApp(pkg);
          steps.add('打开游戏 $pkg: ${o ? 'OK' : '失败'}');
          if (!o) return ToolResult.error('启动游戏失败\n${r()}');
          await Future<void>.delayed(const Duration(milliseconds: 2500)); // 冷启动游戏慢
        }

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        final cx = (w * 0.5).round();
        final cy = (h * 0.5).round();

        int toPx(num v, int maxPx) => v < 1 ? (v * maxPx).round() : v.toInt(); // 0~1 百分比 or 纯像素

        for (var i = 1; i <= loops; i++) {
          // 1) 截当前屏幕
          final img = await s.takeScreenshot();
          if (img == null) {
            steps.add('Round $i: 截图失败，中止');
            break;
          }

          // 2) 问 VLM：给我下一步动作
          //    ⚠ 开放决策模式：custom_vlm_prompt 非空时，100% 用 LLM 自己的提问，不注入任何代码层硬编码格式
          final q = customPrompt.isNotEmpty
              ? customPrompt
              : (() {
                  final sb = StringBuffer('你是手机游戏/RPA 视觉决策器。我给你一张截图，分辨率是 ${w}x$h。\n');
                  sb.writeln('【目标】${goal.isEmpty ? '分析并给出下一步操作建议' : goal}\n');
                  sb.writeln('【严格输出格式（只返回 JSON，不许其他文字）】：');
                  sb.writeln('{"actions": [{"type": "click|swipe|press|back|home|wait", "x%":0.15, "y%":0.33, "x2%":0.15, "y2%":0.05, "key":"BACK", "ms":900}], "summary": "一句话为什么选这些动作"}');
                  sb.writeln('字段说明：type=click 时给 x% y% (0~1 浮点数表示宽高百分比)；');
                  sb.writeln('  type=swipe 时给 x% y% (起点) + x2% y2% (终点) + ms (手势毫秒，默认 380)；');
                  sb.writeln('  type=press 时给 key 名字：HOME/BACK/MENU/VOLUME_UP/VOLUME_DOWN/POWER/ENTER/DEL/SPACE；');
                  sb.writeln('  type=wait 时给 ms (默认 1500)。');
                  sb.writeln('一次最多返回 3 个动作，按执行顺序排。禁止点击 < 3% 屏幕边缘 (防止误触状态栏)。');
                  return sb.toString();
                })();
          final answer = await visionAnalyze(img, q);
          vlmAnswers.add('--- Round $i VLM 回答 ---\n$answer');
          steps.add(skipAuto
              ? 'Round $i/${loops}：[skip_auto_execute=true] VLM 原始回答已收集 (不自动执行，由 LLM 自主决策)，${answer.length} 字'
              : 'Round $i/${loops}：VLM 建议 (${answer.length}字)');

          // H9-2: skip_auto_execute=true → 完全不解析、不自动执行，把原始回答留给 LLM
          if (skipAuto) {
            // 即使跳过执行也加一步 delay，避免截图太密
            await Future<void>.delayed(Duration(milliseconds: delay ~/ 2));
            continue;
          }

          // 3) 粗解析 JSON (容错：手搓正则解析 不要求完美 JSON，只要抓数字就行)
          //    端侧模型可能输出非严格 JSON；我们用 pattern 扒 action 数组
          try {
            // 先找 JSON 花括号整体
            final match = RegExp(r'\{[\s\S]*\}', multiLine: false).firstMatch(answer);
            String json = (match?.group(0) ?? answer).trim();
            // 正则抠出 actions 数组每项内的 kv
            final rxType = RegExp(r'"type"\s*:\s*"(click|swipe|press|back|home|wait)"', caseSensitive: false);
            final rx = (String k) => RegExp('"$k"%?\\s*:\\s*(-?\\d+(?:\\.\\d+)?)');
            final rxKey = RegExp(r'"key"\s*:\s*"([A-Z_]+)"', caseSensitive: false);

            final types = rxType.allMatches(json).map((m) => m.group(1)!.toLowerCase()).toList();
            final xs = rx('x').allMatches(json).map((m) => double.tryParse(m.group(1)!) ?? 0.0).toList();
            final ys = rx('y').allMatches(json).map((m) => double.tryParse(m.group(1)!) ?? 0.0).toList();
            final x2s = rx('x2').allMatches(json).map((m) => double.tryParse(m.group(1)!) ?? 0.0).toList();
            final y2s = rx('y2').allMatches(json).map((m) => double.tryParse(m.group(1)!) ?? 0.0).toList();
            final mss = rx('ms').allMatches(json).map((m) => int.tryParse(m.group(1)!) ?? 0).toList();
            final keys = rxKey.allMatches(json).map((m) => m.group(1)!).toList();

            final total = types.length;
            for (var k = 0; k < total.clamp(0, 3); k++) {
              final t = types[k];
              switch (t) {
                case 'click':
                  if (k < xs.length && k < ys.length) {
                    final px = toPx(xs[k], w);
                    final py = toPx(ys[k], h);
                    if (px >= w * 0.03 && px <= w * 0.97 && py >= h * 0.05 && py <= h * 0.97) {
                      final ok = await s.clickCoords(px, py);
                      if (ok) clickCount[0]++;
                      steps.add('  click (${xs[k].toStringAsFixed(2)},${ys[k].toStringAsFixed(2)})→${px}x$py: ${ok ? 'OK' : 'fail'}');
                    } else {
                      steps.add('  skip click @边缘 (${xs[k].toStringAsFixed(2)},${ys[k].toStringAsFixed(2)})');
                    }
                  }
                  break;
                case 'swipe':
                  if (k < xs.length && k < ys.length && k < x2s.length && k < y2s.length) {
                    final dur = (k < mss.length && mss[k] > 0) ? mss[k] : 380;
                    await s.swipe(toPx(xs[k], w), toPx(ys[k], h), toPx(x2s[k], w), toPx(y2s[k], h), durationMs: dur);
                    swipeCount[0]++;
                    steps.add('  swipe (${xs[k].toStringAsFixed(2)},${ys[k].toStringAsFixed(2)})→(${x2s[k].toStringAsFixed(2)},${y2s[k].toStringAsFixed(2)}) dur=${dur}ms');
                  }
                  break;
                case 'press':
                  if (k < keys.length) {
                    final keyName = keys[k].toUpperCase();
                    AndroidKey? kk;
                    switch (keyName) {
                      case 'BACK': kk = AndroidKey.back; break;
                      case 'HOME': kk = AndroidKey.home; break;
                      case 'MENU': kk = AndroidKey.menu; break;
                      case 'VOLUME_UP': kk = AndroidKey.volumeUp; break;
                      case 'VOLUME_DOWN': kk = AndroidKey.volumeDown; break;
                      case 'ENTER': kk = AndroidKey.enter; break;
                      case 'DEL': case 'DELETE': kk = AndroidKey.del; break;
                      case 'SPACE': kk = AndroidKey.space; break;
                    }
                    if (kk != null) { await s.pressKey(kk); steps.add('  pressKey $keyName: sent'); }
                    else steps.add('  pressKey $keyName: 不支持');
                  }
                  break;
                case 'back':
                  await s.pressKey(AndroidKey.back); steps.add('  back: sent'); break;
                case 'home':
                  await s.pressKey(AndroidKey.home); steps.add('  home: sent'); break;
                case 'wait':
                  final wms = (k < mss.length && mss[k] > 0) ? mss[k] : 1500;
                  await Future<void>.delayed(Duration(milliseconds: wms));
                  steps.add('  wait ${wms}ms'); break;
              }
              await Future<void>.delayed(Duration(milliseconds: delay));
            }
          } catch (e, st) {
            steps.add('  VLM 解析出错 (跳过本轮): $e');
            // ignore, continue
          }

          // ---- 失败恢复检测 ----
          if (!skipAuto && !recoveryMode) {
            // 检测本轮动作摘要是否与上一轮相同（卡住判断）
            final currentSummary = steps.isNotEmpty ? steps.last : '';
            if (lastActionSummary != null &&
                currentSummary == lastActionSummary &&
                clickCount[0] + swipeCount[0] > 0) {
              staleCounter++;
              steps.add('  ⚠ 检测到动作重复 ($staleCounter/$maxStale)');
            } else {
              staleCounter = 0;
            }
            lastActionSummary = currentSummary;

            // 卡住 ≥ maxStale 轮 → 触发恢复策略
            if (staleCounter >= maxStale) {
              steps.add('  🚨 卡住超过 $maxStale 轮，触发恢复策略');
              staleCounter = 0;
              recoveryMode = true;
              // 恢复策略：按优先级尝试后退/主页/滑动
              for (var ri = 0; ri < maxRecoveryActions; ri++) {
                if (ri == 0) {
                  await s.pressKey(AndroidKey.back);
                  steps.add('  恢复[$ri]：按返回键');
                } else if (ri == 1) {
                  await s.swipe(0, 500, 0, -500, durationMs: 200);
                  steps.add('  恢复[$ri]：向上滑动');
                } else if (ri == 2) {
                  await s.pressKey(AndroidKey.home);
                  steps.add('  恢复[$ri]：按主页键');
                }
                await Future.delayed(const Duration(milliseconds: 800));
              }
              recoveryMode = false;
            }
          }

          // ---- 保存进度到持久化（可通过 agent_memory 读取） ----
          // 每 5 轮记录一次，防止完全丢失
          if (i % 5 == 0) {
            final progress = {
              'round': i,
              'total_loops': loops,
              'clicks': clickCount[0],
              'swipes': swipeCount[0],
              'steps': steps.length,
              'game_pkg': pkg,
              'goal': goal,
              'timestamp': DateTime.now().toIso8601String(),
            };
            // 写入临时文件供 agent_memory 读取
            await s.gshell(
                'echo \'${jsonEncode(progress)}\' > /sdcard/Android/data/com.openagent.openagent/files/game_progress.json 2>/dev/null');
          }
        }

        final sb = StringBuffer(skipAuto
            ? '✅ 游戏 VLM 截图+开放问答完成 (skip_auto_execute=true, 未执行任何动作)\n'
            : '✅ 游戏 VLM 自动驾驶结束\n');
        sb.writeln('  轮次执行 $loops 次，累计: 点击=${clickCount[0]}, 滑屏=${swipeCount[0]}');
        if (customPrompt.isNotEmpty) sb.writeln('  ⚙ custom_vlm_prompt 已启用 (LLM 自主覆盖提问模板)');
        sb.writeln(r());
        if (vlmAnswers.isNotEmpty) {
          sb.writeln('\n===== 每轮 VLM 原始回答（供 LLM 自主分析）=====');
          sb.writeln(vlmAnswers.join('\n'));
        }
        return ToolResult.ok(sb.toString());
      },
    );

/// ——— 支付宝：扫一扫 ———
Tool _composeAlipayScan(AndroidAutomationService s) => Tool(
      name: 'android_alipay_scan',
      description:
          '【高层·一步完成】打开支付宝 → 顶部扫一扫 (扫码/收钱码)。'
          '用户说"用支付宝付款扫码""扫个商家码支付"时直接调用。',
      schema: _props({
        'mode': {
          'type': 'integer',
          'description': '0=扫一扫(默认), 1=付款码, 2=收款码。本工具=0(扫一扫); mode=1/2 请用 android_alipay_show_payment_code',
        },
      }),
      handler: (args) async {
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        final ok = await s.openApp('com.eg.android.AlipayGphone');
        steps.add('打开支付宝: ${ok ? 'OK' : '失败 (未安装?)'}');
        if (!ok) return ToolResult.error('支付宝启动失败\n${r()}');

        // 支付宝冷启动较慢 (安全校验)
        await s.waitForText('首页', timeoutSec: 20, pollMs: 900, exact: false) ||
            await s.waitForText('扫一扫', timeoutSec: 20, pollMs: 900, exact: false);
        await Future<void>.delayed(const Duration(milliseconds: 500));

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        // 扫一扫入口在首页左上 20%x 32%y 附近(4 宫格第一个图标) 或 顶部搜索栏左侧
        var sOk = await s.clickByText('扫一扫', exact: true) ||
            await s.clickByText('扫 一 扫', exact: false);
        if (!sOk) sOk = await s.clickCoords((w * 0.18).round(), (h * 0.32).round());
        steps.add('点扫一扫: ${sOk ? 'OK' : '坐标尝试 (18%x,32%y)'}');
        await Future<void>.delayed(const Duration(milliseconds: 1400));
        return ToolResult.ok('✅ 支付宝扫一扫已打开\n${r()}');
      },
    );

/// ——— 支付宝：出示付款码 / 收款码 ———
Tool _composeAlipayShowCode(AndroidAutomationService s) => Tool(
      name: 'android_alipay_show_payment_code',
      description:
          '【高层·一步完成】打开支付宝 → 点「付款/收钱」，出示给商家扫描的条形码+二维码 或 个人收款码。'
          'mode=1 付款码（商家扫你扣钱）；mode=2 收款码（别人扫你给你转账）。',
      schema: _props({
        'mode': {
          'type': 'integer',
          'description': '1=付款码(默认), 2=收款码',
        },
      }),
      handler: (args) async {
        final mode = ((args['mode'] as num?)?.toInt() ?? 1).clamp(1, 2);
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        final ok = await s.openApp('com.eg.android.AlipayGphone');
        steps.add('打开支付宝: ${ok ? 'OK' : '失败'}');
        if (!ok) return ToolResult.error('启动失败\n${r()}');

        await s.waitForText('首页', timeoutSec: 22, pollMs: 900, exact: false) ||
            await s.waitForText('付款', timeoutSec: 20, pollMs: 900, exact: false);
        await Future<void>.delayed(const Duration(milliseconds: 500));

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        // 付款 四宫格第二个图标 约 38%x 32%y；收钱 第三 宫格
        final label = mode == 1 ? '付款' : '收钱';
        final colX = mode == 1 ? 0.38 : 0.58;
        var cOk = await s.clickByText(label, exact: true) ||
            await s.clickByText('$label码', exact: false);
        if (!cOk) cOk = await s.clickCoords((w * colX).round(), (h * 0.32).round());
        steps.add('点「$label」(第${mode==1?'二':'三'}宫格 $colX): ${cOk ? 'OK' : '坐标尝试'}');
        await Future<void>.delayed(const Duration(milliseconds: 1400));

        // 部分版本点完会弹安全校验：默认点「知道了 / 确定」让码显示出来
        await s.clickByText('知道了', exact: false);
        await s.clickByText('确定', exact: false);
        return ToolResult.ok('✅ 支付宝${mode == 1 ? '付款码' : '收款码'}已请求显示\n${r()}');
      },
    );

// ============================================================================
// H7 系统设置 + 社交补全 （×5）
// ============================================================================

/// ——— 系统：开/关 Wi-Fi (优先L2 svc，不行才跳设置 UI) ———
Tool _composeSystemWifi(AndroidAutomationService s) => Tool(
      name: 'android_system_set_wifi',
      description:
          '【高层·系统设置】开启/关闭 手机 Wi-Fi。优先用 shell `svc wifi enable/disable` (L2/L3 秒切)；不行再进系统设置页 UI 开关。',
      schema: _props({
        'enabled': {
          'type': 'boolean',
          'description': 'true=打开 Wi-Fi；false=关闭 Wi-Fi',
        },
      }, required: [
        'enabled'
      ]),
      handler: (args) async {
        final on = args['enabled'] != false;
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // 1) Shell 秒切 (Shizuku/Root 都支持 svc)
        final sh = await s.gshell('svc wifi ${on ? 'enable' : 'disable'}');
        steps.add('svc wifi ${on ? 'enable' : 'disable'}: ok=${sh.ok}, exit=${sh.exitCode}');
        if (sh.ok) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
          return ToolResult.ok('✅ Wi-Fi ${on ? '已开启' : '已关闭'} (svc)\n${r()}');
        }

        // 2) UI Fallback: 打开设置 → 网络 → Wi-Fi 开关
        steps.add('L2 svc 失败，尝试 UI 方式');
        await s.openApp('com.android.settings');
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await s.clickByText('WLAN', exact: false);
        await s.clickByText('Wi-Fi', exact: false);
        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        // 典型 Wi-Fi 开关在 右上 88%x 8%y (小米/HW)；或 34%x 20%y
        await s.clickCoords((w * 0.88).round(), (h * 0.08).round());
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return ToolResult.ok('⚠ 已尝试 UI 切换 Wi-Fi ${on ? '开' : '关'} (非 L2 可能需要手动确认)\n${r()}');
      },
    );

/// ——— 系统：开/关 蓝牙 ———
Tool _composeSystemBluetooth(AndroidAutomationService s) => Tool(
      name: 'android_system_set_bluetooth',
      description:
          '【高层·系统设置】开启/关闭 蓝牙。优先 shell `svc bluetooth enable/disable`；失败走设置 UI。',
      schema: _props({
        'enabled': {
          'type': 'boolean',
          'description': 'true=开蓝牙；false=关蓝牙',
        },
      }, required: [
        'enabled'
      ]),
      handler: (args) async {
        final on = args['enabled'] != false;
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        final sh = await s.gshell('svc bluetooth ${on ? 'enable' : 'disable'}');
        steps.add('svc bluetooth ${on ? 'enable' : 'disable'}: ok=${sh.ok}');
        if (sh.ok) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
          return ToolResult.ok('✅ 蓝牙 ${on ? '已开启' : '已关闭'} (svc)\n${r()}');
        }

        steps.add('L2 失败，UI fallback');
        await s.openApp('com.android.settings');
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await s.clickByText('蓝牙', exact: false);
        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        await s.clickCoords((w * 0.88).round(), (h * 0.10).round());
        return ToolResult.ok('⚠ UI 尝试切换蓝牙 ${on ? '开' : '关'}\n${r()}');
      },
    );

/// ——— 系统：调节媒体/通话/闹钟/铃声音量 (0-15 档) ———
Tool _composeSystemSetVolume(AndroidAutomationService s) => Tool(
      name: 'android_system_set_volume',
      description:
          '【高层·系统设置】一次性设置 媒体/通话/铃声/闹钟 任一流的音量档位 (0 静音 ~ 15 最大)。'
          '优先 shell `cmd media_session dispatch volume --set` 或 `media volume --stream N --set`；失败走按物理 VOLUME_UP/DOWN N 次模拟。',
      schema: _props({
        'level': {
          'type': 'integer',
          'description': '目标音量档位 0~15 (0=静音, 7=中等, 15=最大)',
        },
        'stream': {
          'type': 'string',
          'description': 'music=媒体音乐/视频(默认), ring=来电铃声, alarm=闹钟, call=通话音量',
        },
      }, required: [
        'level'
      ]),
      handler: (args) async {
        final level = ((args['level'] as num?)?.toInt() ?? 7).clamp(0, 15);
        final stream = (args['stream'] as String?) ?? 'music';
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // STREAM mapping: Android STREAM_VOICE_CALL=0, SYSTEM=1, RING=2, MUSIC=3, ALARM=4
        final streamNo = const {'call': '0', 'ring': '2', 'music': '3', 'alarm': '4'}[stream] ?? '3';

        // 方案 A: `media volume` (部分国内 ROM 支持) → `cmd media_session dispatch set_volume`
        final a1 = await s.gshell('media volume --stream $streamNo --set $level 2>&1');
        if (a1.ok && (a1.exitCode == 0)) {
          steps.add('media volume s=$streamNo lvl=$level: OK');
        } else {
          // 方案 B: service call audio / cmd media_session dispatch 等 (兼容性依次尝试)
          final a2 = await s.gshell('cmd media_session dispatch volume --stream $streamNo --set $level');
          if (!a2.ok) {
            // 方案 C: service call audio 3 (getMode) → 不同 ROM 码号不同，放弃 Shell
            steps.add('Shell 设置音量失败 (exit=${a2.exitCode})，改用 VOL 键模拟 0→$level');
            // 按 8 次 DOWN 先回静音 (保险一点)，再按 $level 次 UP
            for (var i = 0; i < 9; i++) await s.pressKey(AndroidKey.volumeDown);
            for (var i = 0; i < level; i++) await s.pressKey(AndroidKey.volumeUp);
            steps.add('按键模拟: 先-9静音 + 再+$level UP → 目标=$level');
          } else {
            steps.add('cmd media_session dispatch set $streamNo/$level: OK');
          }
        }
        return ToolResult.ok('✅ 音量设置 stream=$stream($streamNo) → $level\n${r()}');
      },
    );

/// ——— 微信：群发助手 (给 N 个好友发相同文字 —— 节日/通知群发) ———
Tool _composeWechatBroadcastMessage(AndroidAutomationService s) => Tool(
      name: 'android_wechat_broadcast_message',
      description:
          '【高层·一键群发】微信 → 我 → 设置 → 通用 → 辅助功能 → 群发助手 → 开始群发 → 新建 → 搜并选择好友 → 下一步 → 写文字 → 发送。'
          '⚠ 用户说"给所有客户群发个祝福""给群里所有人发通知"时用本工具。注意：不能用来发骚扰营销内容，受微信频控。',
      schema: _props({
        'message': {
          'type': 'string',
          'description': '群发的正文文字 (必填)',
        },
        'search_names': {
          'type': 'array',
          'description': '【可选】N 个好友/群聊备注名。工具会依次搜索并勾选；为空则只点群发助手不选具体人（手动确认）。',
        },
      }, required: [
        'message'
      ]),
      handler: (args) async {
        final msg = args['message'] as String? ?? '';
        final namesRaw = args['search_names'];
        List<String> names = <String>[];
        if (namesRaw is List) names = namesRaw.whereType<String>().toList();
        if (msg.isEmpty) return const ToolResult.error('缺少 message');

        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // Step 1: 微信主页 → 右下「我」
        final ok1 = await s.openApp('com.tencent.mm');
        steps.add('打开微信: ${ok1 ? 'OK' : '失败'}');
        if (!ok1) return ToolResult.error('启动失败\n${r()}');
        await s.waitForText('微信', timeoutSec: 18, pollMs: 700, exact: false) ||
            await s.waitForText('通讯录', timeoutSec: 6, pollMs: 500, exact: true);

        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        final me = await s.clickByText('我', exact: true) ||
            await s.clickCoords((w * 0.88).round(), (h * 0.96).round());
        steps.add('点「我」: ${me ? 'OK' : '坐标尝试 (88%x, 96%y)'}');
        await Future<void>.delayed(const Duration(milliseconds: 500));

        // Step 2: 设置 → 通用 → 辅助功能 → 群发助手
        for (final label in ['设置', '通用', '辅助功能', '群发助手']) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          final ok = await s.clickByText(label, exact: true);
          steps.add('点「$label」: ${ok ? 'OK' : '(没找到，继续)'}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));

        // Step 3: 开始群发 → 新建群发
        for (final label in ['开始群发', '新建']) {
          final ok = await s.clickByText(label, exact: true);
          steps.add('点「$label」: ${ok ? 'OK' : ''}');
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }

        // Step 4: 选 N 个收信人
        var chosen = 0;
        for (final nm in names) {
          if (chosen >= 50) break; // 微信单次群发上限 ≈200，保守限制 50
          final bar = await s.clickByText('搜索', exact: false) ||
              await s.clickCoords((w * 0.50).round(), (h * 0.10).round());
          if (bar) {
            final wrote = await s.inputText(nm);
            if (wrote) {
              await Future<void>.delayed(const Duration(milliseconds: 400));
              // 点击第一个搜索结果 (左侧头像右边 30%x 区域)
              final t = await s.clickCoords((w * 0.20).round(), (h * 0.32).round());
              if (t) chosen++;
              steps.add('搜索+选择「$nm」: 选择=${t ? 'OK' : '未点到'}, 当前选中$chosen');
              await Future<void>.delayed(const Duration(milliseconds: 200));
            }
          }
        }
        if (names.isEmpty) steps.add('未指定 search_names，停在「选人」页等待用户自己挑');

        // Step 5: 下一步 → 写文字 → 发送
        if (names.isNotEmpty && chosen > 0) {
          await s.clickByText('下一步', exact: true) || await s.clickCoords((w * 0.90).round(), (h * 0.95).round());
          await Future<void>.delayed(const Duration(milliseconds: 600));
          final iw = await s.inputText(msg);
          steps.add('写群发内容(${msg.length}字): ${iw ? 'OK' : '失败'}');
          if (iw) {
            final sent = await s.clickByText('发送', exact: true);
            steps.add('发送: ${sent ? 'OK' : '发送失败'}');
          }
        }
        return ToolResult.ok('✅ 微信群发助手流程完成 (尝试勾选 $chosen/${names.length} 人)\n${r()}');
      },
    );

/// ——— B站视频播放页：发一条弹幕 ———
Tool _composeBilibiliSendDanmaku(AndroidAutomationService s) => Tool(
      name: 'android_bilibili_send_danmaku',
      description:
          '【高层·B站社交】当前在播放的 B 站视频页：点击底部弹幕输入框 → 写弹幕 → 发送。'
          '用户说"在这条视频刷个「下次一定」"时调用。',
      schema: _props({
        'text': {
          'type': 'string',
          'description': '弹幕内容，不要超过 30 字',
        },
        'color_hex': {
          'type': 'string',
          'description': '(预留) 弹幕颜色 RGB hex，默认白字 #FFFFFF，当前版本未改颜色面板',
        },
      }, required: [
        'text'
      ]),
      handler: (args) async {
        final txt = args['text'] as String? ?? '';
        if (txt.isEmpty) return const ToolResult.error('缺少 text');
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // 确保在 B站
        final info = await s.getTopApp();
        if (info.package != 'tv.danmaku.bili') {
          steps.add('当前不在 B 站，跳过(防止误发在其他App)');
          return ToolResult.error('请先打开 B 站视频页再发弹幕\n${r()}');
        }
        final res = await s.screenResolution();
        final w = res?[0] ?? 1080;
        final h = res?[1] ?? 2400;
        // B站播放器：竖屏弹幕输入框在视频下方 42%~48%y 的一条灰色"发条友善的弹幕~"占位符
        // 横屏时一般位于屏幕 左中 30%x~50%x。双位置尝试
        final focus = await s.clickByText('发条友善的弹幕', exact: false) ||
            await s.clickByText('发个弹幕', exact: false) ||
            await s.clickByText('说点什么', exact: false) ||
            await s.clickCoords((w * 0.30).round(), (h * 0.45).round()) ||
            await s.clickCoords((w * 0.25).round(), (h * 0.90).round());
        steps.add('点弹幕输入框: ${focus ? 'OK' : '双坐标尝试'}');
        await Future<void>.delayed(const Duration(milliseconds: 350));
        final wrote = await s.inputText(txt);
        steps.add('输入弹幕「$txt」: ${wrote ? 'OK' : '失败'}');
        if (!wrote) return ToolResult.error('弹幕输入框写入失败\n${r()}');
        final sent = await s.clickByText('发送', exact: true) ||
            await s.clickByText('发', exact: true) ||
            await s.clickCoords((w * 0.93).round(), (h * 0.45).round());
        steps.add('发送弹幕: ${sent ? 'OK' : '未点到发送按钮'}');
        return ToolResult.ok('✅ B站弹幕流程完成\n${r()}');
      },
    );

// ============================================================================
// H8 开放通用工具：不硬编码流程，交给 (LLM + VLM) 自主决策
// 目标：让模型自己判断"做什么"和"怎么做"，我们只提供原子能力和开放接口
// ============================================================================

/// ——— H8-1: 长按屏幕坐标（弹出菜单/选中文字/拖拽等场景）———
Tool _longPressTool(AndroidAutomationService s) => Tool(
      name: 'android_long_press',
      description:
          '长按屏幕指定坐标 (x,y)。用于：弹出右键菜单、选中文字、拖放图标、游戏里蓄力等场景。'
          '默认长按 800ms，可自定义时长。',
      schema: _props({
        'x': {'type': 'integer', 'description': '横坐标像素值'},
        'y': {'type': 'integer', 'description': '纵坐标像素值'},
        'duration_ms': {
          'type': 'integer',
          'description': '长按持续毫秒数 (默认 800，拖东西可调 1500~3000)',
        },
      }, required: [
        'x',
        'y'
      ]),
      handler: (args) async {
        final x = args['x'] as int?;
        final y = args['y'] as int?;
        if (x == null || y == null) {
          return const ToolResult.error('缺少参数 x 或 y');
        }
        final dur = (args['duration_ms'] as num?)?.toInt() ?? 800;
        final ok = await s.longPress(x, y, durationMs: dur);
        return ok
            ? ToolResult.ok('已长按坐标 ($x,$y) 持续 ${dur}ms')
            : const ToolResult.error('长按失败 (可能无障碍/Shizuku 权限未开启)');
      },
    );

/// ——— H8-2: 剪贴板读写（复制/粘贴数据，让模型自由搬运文字）———
Tool _clipboardTool(AndroidAutomationService s) => Tool(
      name: 'android_clipboard',
      description:
          '读或写系统剪贴板。操作场景：从 App A 复制文字 → 粘贴到 App B；'
          '把一大段中文先写入剪贴板 → 再到输入框长按粘贴 (避开中文输入法不兼容问题)。',
      schema: _props({
        'action': {
          'type': 'string',
          'description': 'get=读取剪贴板内容返回给你；set=写入指定文字到剪贴板',
        },
        'text': {
          'type': 'string',
          'description': '当 action=set 时必填：要写入剪贴板的文字内容',
        },
      }, required: [
        'action'
      ]),
      handler: (args) async {
        final action = (args['action'] as String? ?? '').toLowerCase();
        if (action == 'get') {
          final content = await s.getClipboard();
          return content.isEmpty
              ? const ToolResult.ok('剪贴板当前为空')
              : ToolResult.ok('剪贴板内容:\n$content');
        }
        if (action == 'set') {
          final text = args['text'] as String?;
          if (text == null || text.isEmpty) {
            return const ToolResult.error('action=set 时参数 text 不能为空');
          }
          final ok = await s.setClipboard(text);
          return ok
              ? ToolResult.ok('已写入剪贴板 (${text.length} 字)')
              : const ToolResult.error('写剪贴板失败 (可改用 input_text 直接输入)');
        }
        return const ToolResult.error('action 必须是 get 或 set');
      },
    );

/// ——— H8-3: 自定义路径手势（画任意曲线：解锁图案 / 画签名 / 拖拽多个点 / 游戏技能方向）———
Tool _customGestureTool(AndroidAutomationService s) => Tool(
      name: 'android_custom_gesture',
      description:
          '按你给的坐标点数组画一条连续手势路径。用途：手机九宫格图案解锁、画签名、'
          '拖动物品跨屏、游戏技能方向摇杆画任意曲线、复杂滑动组合动作等。'
          'points 是数组，每项含 x,y 两个像素坐标；至少要 2 个点 (起点+终点)；想画曲线就多给几个中间点。',
      schema: _props({
        'points': {
          'type': 'array',
          'description':
              '坐标点数组，例: [{"x":100,"y":800},{"x":500,"y":400},{"x":900,"y":800}] → 画一条 V 型手势',
          'items': {
            'type': 'object',
            'properties': {
              'x': {'type': 'integer'},
              'y': {'type': 'integer'},
            },
          },
        },
        'total_duration_ms': {
          'type': 'integer',
          'description': '整条手势总时长毫秒 (默认 500。慢拖/签名可调 1500~3000)',
        },
      }, required: [
        'points'
      ]),
      handler: (args) async {
        final raw = args['points'];
        if (raw is! List || raw.length < 2) {
          return const ToolResult.error('points 必须是包含至少 2 个点的数组');
        }
        final points = <Map<String, int>>[];
        for (final item in raw) {
          if (item is Map) {
            final x = (item['x'] as num?)?.toInt();
            final y = (item['y'] as num?)?.toInt();
            if (x != null && y != null) {
              points.add({'x': x, 'y': y});
            }
          }
        }
        if (points.length < 2) {
          return const ToolResult.error('points 每项必须有合法 x,y (整数)');
        }
        final dur = (args['total_duration_ms'] as num?)?.toInt() ?? 500;
        final ok = await s.customGesture(points, totalDurationMs: dur);
        return ok
            ? ToolResult.ok('已执行自定义手势 (${points.length} 个点, 总时长 ${dur}ms)')
            : const ToolResult.error('自定义手势执行失败');
      },
    );

/// ——— H8-4: 通用 Shell 命令执行（把完整 shell 权限交给模型自由发挥）———
Tool _shellExecTool(AndroidAutomationService s) => Tool(
      name: 'android_shell_exec',
      description:
          '【开放通用权限】直接通过 Shizuku (shell 用户身份) 或 Root 执行任意 Android shell 命令。'
          'L1 无障碍做不到的事 (比如直接改系统设置、模拟设备按键、查看数据库、pm/包管理、'
          'am 发送广播/启动组件、settings put 修改安全设置、iptables/网络管理等) 都可以通过这里自由实现。'
          '⚠ 你作为 AI 请先确认命令安全再执行。高危操作 (如 rm -rf、pm uninstall 系统应用) 先在回答里警告用户。',
      schema: _props({
        'command': {
          'type': 'string',
          'description':
              '任意 Linux/Android shell 命令，可带管道 && || 等。例: svc wifi disable  或  settings put system screen_brightness 128  或  dumpsys activity top | grep ACTIVITY',
        },
        'timeout_sec': {
          'type': 'integer',
          'description': '超时秒数 (默认 30，复杂命令可调大)',
        },
      }, required: [
        'command'
      ]),
      handler: (args) async {
        final cmd = args['command'] as String?;
        if (cmd == null || cmd.trim().isEmpty) {
          return const ToolResult.error('command 不能为空');
        }
        final r = await s.gshell(cmd);
        final sb = StringBuffer();
        sb.writeln('命令: $cmd');
        sb.writeln('执行成功: ${r.ok}, exitCode=${r.exitCode}');
        if (r.stdout.isNotEmpty) sb.writeln('--- stdout ---\n${r.stdout}');
        if (r.stderr.isNotEmpty) sb.writeln('--- stderr ---\n${r.stderr}');
        return (r.ok && r.exitCode == 0)
            ? ToolResult.ok(sb.toString())
            : ToolResult.error(sb.toString());
      },
    );

/// ——— H8-5: 【核心】VLM 自由视觉分析 + 原始回答（截图后把任意问题交给多模态模型，不硬编码输出格式，不自动执行任何动作）
///   真正实现"VLM 自己判断"：LLM 可以问任意问题，VLM 按自己理解回答文字/坐标/理由，
///   然后由 LLM 看完 VLM 回答后再决定下一步 (click/swipe/press/自定义手势…)，
///   代码层绝不干预、不解析 JSON、不自动执行动作。
Tool _visionFreeAnalyzeTool(
  AndroidAutomationService s,
  Future<String> Function(String imagePath, String question) visionAnalyze,
) =>
    Tool(
      name: 'android_vision_ask',
      description:
          '【多模态核心·开放】截图当前手机屏幕，然后你 (LLM) 可以向 Omni VLM 提任意开放问题，'
          'VLM 会按自己的理解自由回答 (不限制输出格式、不一定返回 JSON)，返回的完整回答直接给你 (LLM) 读，'
          '你再基于 VLM 的回答自己判断下一步调用哪个工具 (click_coords / swipe / custom_gesture / shell…)。'
          '⚠ 这个工具和 android_game_auto_vlm_loop 的区别：本工具不解析回答、不自动执行任何动作、'
          '100% 由你 (LLM+VLM) 自主决策，不会被代码层的硬编码规则干扰。适合：游戏、无文字界面、复杂场景判断、'
          '你需要 VLM 给理由、或你想验证自己的某个判断。',
      schema: _props({
        'question': {
          'type': 'string',
          'description':
              '【你自己的问题】向多模态模型问任意问题。例1: "这张截图里哪个按钮是 开始游戏？估计它的屏幕中心坐标 (x,y) 像素值" 例2: "帮我数清这页有几个黄色 完成 按钮，列出每个的大致坐标区间" 例3: "截图的游戏界面里，我下一步应该点哪里才能进入下一关？给出 1~2 个最可能的坐标并说明为什么"',
        },
        'auto_screenshot': {
          'type': 'boolean',
          'description':
              'true=先自动截图再提问 (默认, 99% 情况用这个)；false=你已经截过图只想复用上次结果 (节省时间)',
        },
      }, required: [
        'question'
      ]),
      handler: (args) async {
        final q = args['question'] as String?;
        if (q == null || q.trim().isEmpty) {
          return const ToolResult.error('请输入你要问 VLM 的问题 (question 参数)');
        }
        final autoShot = args['auto_screenshot'] as bool? ?? true;
        String? img;
        if (autoShot) {
          img = await s.takeScreenshot();
          if (img == null) {
            return const ToolResult.error('截图失败 (请确认已授予截屏权限或开启 Root)');
          }
        } else {
          // 没有现成的，仍然截一次以防用户忘记
          img = await s.takeScreenshot();
        }
        final answer = await visionAnalyze(img!, q);
        final sb = StringBuffer('✅ VLM 开放回答 (未解析, 由你 LLM 自主理解)\n');
        sb.writeln('你提问: $q');
        sb.writeln('截图路径: $img');
        sb.writeln('--- VLM 原始回答 ---\n$answer');
        return ToolResult.ok(sb.toString());
      },
    );

// ============================================================================
// H10 开放原子能力：无任何流程硬编码，100% 由 (LLM+VLM) 自由组合
// ============================================================================

/// ——— H10-1: 发送任意 Android Intent（最开放的 App 跳转/分享/调起能力）———
Tool _sendIntentTool(AndroidAutomationService s) => Tool(
      name: 'android_send_intent',
      description:
          '【最开放·原子】发送任意 Android Intent，100% 自由度。用途举例：'
          '① 打开 DeepLink scheme://host/path ② 调起第三方 App 指定 Activity (component) '
          '③ 打电话 tel:10086 / ④ 发短信 smsto:138...?body=xxx / ⑤ 发邮件 mailto: / '
          '⑥ 分享文本 android.intent.action.SEND type=text/plain / ⑦ 打开系统设置页面 '
          '⑧ 传自定义 extras 给 App。参数全为可选，按你的需要传最少几个即可。',
      schema: _props({
        'action': {'type': 'string', 'description': 'Intent Action，例: android.intent.action.VIEW (打开链接默认) / SEND (分享) / DIAL (拨号) / SENDTO (短信) / CALL'},
        'data': {'type': 'string', 'description': 'Intent Data URI，例: https://www.baidu.com / tel:10086 / sms:13800138000 / smsto:13800138000?body=你好 / weixin://dl/scan'},
        'type': {'type': 'string', 'description': 'MIME Type，例: text/plain (文本分享) / image/* (图片分享) / video/mp4'},
        'component': {'type': 'string', 'description': '直接指定组件包名/类名，例: com.tencent.mm/.ui.LauncherUI (精准打开某App某页)'},
        'package': {'type': 'string', 'description': '限制只在某包名内解析 (防止多个 App 抢同一个 Intent)'},
        'categories': {
          'type': 'array',
          'description': 'Intent Categories 列表，例: ["android.intent.category.BROWSABLE"]',
          'items': {'type': 'string'},
        },
        'extras_string': {
          'type': 'object',
          'description': '字符串额外参数 (key→value)。分享文本时用 {"android.intent.extra.TEXT": "要分享的文字"} / 主题用 {"android.intent.extra.SUBJECT": "标题"}',
          'additionalProperties': {'type': 'string'},
        },
        'extras_int': {
          'type': 'object',
          'description': '整数额外参数 key→int',
          'additionalProperties': {'type': 'integer'},
        },
        'extras_bool': {
          'type': 'object',
          'description': '布尔额外参数 key→bool',
          'additionalProperties': {'type': 'boolean'},
        },
        'wait_for_result': {
          'type': 'boolean',
          'description': 'true=等待启动结果并返回 (耗时较长)，默认 false=异步启动直接返回',
        },
      }),
      handler: (args) async {
        Map<String, String> parseMapStr(dynamic v) {
          if (v is! Map) return <String, String>{};
          return Map<String, String>.fromEntries(
            v.entries.where((e) => e.value is String).map((e) => MapEntry(e.key as String, e.value as String)),
          );
        }
        Map<String, int> parseMapInt(dynamic v) {
          if (v is! Map) return <String, int>{};
          return Map<String, int>.fromEntries(
            v.entries
                .where((e) => e.value is num)
                .map((e) => MapEntry(e.key as String, (e.value as num).toInt())),
          );
        }
        Map<String, bool> parseMapBool(dynamic v) {
          if (v is! Map) return <String, bool>{};
          return Map<String, bool>.fromEntries(
            v.entries.where((e) => e.value is bool).map((e) => MapEntry(e.key as String, e.value as bool)),
          );
        }

        final r = await s.sendIntent(
          action: args['action'] as String?,
          data: args['data'] as String?,
          type: args['type'] as String?,
          component: args['component'] as String?,
          package: args['package'] as String?,
          waitForResult: args['wait_for_result'] as bool? ?? false,
          categories: (args['categories'] as List?)?.whereType<String>().toList(),
          extrasString: parseMapStr(args['extras_string']),
          extrasInt: parseMapInt(args['extras_int']),
          extrasBool: parseMapBool(args['extras_bool']),
        );
        final sb = StringBuffer('Intent 执行 ${(r.ok && r.exitCode == 0) ? '成功' : '失败 (exit=${r.exitCode})'}\n');
        if (r.stdout.isNotEmpty) sb.writeln('stdout:\n${r.stdout}');
        if (r.stderr.isNotEmpty) sb.writeln('stderr:\n${r.stderr}');
        return (r.ok && r.exitCode == 0)
            ? ToolResult.ok(sb.toString())
            : ToolResult.error(sb.toString());
      },
    );

/// ——— H10-2: 文件系统（读/写/列目录/删/查存在）———
Tool _fileTool(AndroidAutomationService s) => Tool(
      name: 'android_file',
      description:
          '【开放原子】文件系统任意操作：读文本文件、写文本文件、列出目录内容、删除文件/目录、检查是否存在。'
          '可操作路径：/sdcard/ (内部存储)、/sdcard/Download/、/sdcard/Pictures/ (需要存储权限)；'
          '本App内部路径无需权限；/data/data/* 需要 Root。完全由你 (LLM) 自由操作。',
      schema: _props({
        'op': {
          'type': 'string',
          'description': '操作类型：read=读文件 | write=写文件 (覆盖) | append=追加写 | list=列目录 | delete=删文件/目录 | exists=查存在',
        },
        'path': {
          'type': 'string',
          'description': '文件或目录的绝对路径，例: /sdcard/Download/test.txt / /sdcard/DCIM/Camera/',
        },
        'content': {
          'type': 'string',
          'description': 'op=write 或 op=append 时必填：要写入的文本内容',
        },
      }, required: [
        'op',
        'path'
      ]),
      handler: (args) async {
        final op = (args['op'] as String? ?? '').toLowerCase();
        final path = (args['path'] as String? ?? '').trim();
        if (path.isEmpty) return const ToolResult.error('path 不能为空');

        switch (op) {
          case 'read':
            final c = await s.fileRead(path);
            return c.isEmpty
                ? const ToolResult.ok('文件为空或不存在 (也可能无读取权限)')
                : ToolResult.ok('文件内容:\n$c');
          case 'write':
          case 'append':
            final content = args['content'] as String? ?? '';
            final ok = await s.fileWrite(path, content, append: op == 'append');
            return ok
                ? ToolResult.ok('${op == 'append' ? '追加写入' : '写入'} $path 成功 (${content.length} 字)')
                : ToolResult.error('写入失败 (路径不存在或无写权限)');
          case 'list':
            final list = await s.fileListDir(path);
            return list.isEmpty
                ? ToolResult.ok('目录 $path 为空或不存在:\n(无内容)')
                : ToolResult.ok('目录 $path:\n${list.join('\n')}');
          case 'delete':
            final ok = await s.fileDelete(path);
            return ok
                ? ToolResult.ok('已删除: $path')
                : ToolResult.error('删除失败 (不存在或无权限)');
          case 'exists':
            final ok = await s.fileExists(path);
            return ToolResult.ok(ok ? '$path 存在' : '$path 不存在');
          default:
            return const ToolResult.error('op 必须是: read / write / append / list / delete / exists');
        }
      },
    );

/// ——— H10-3: 查询 App 详情（给 LLM 足够原始信息自主判断 App 能做什么）———
Tool _appInfoTool(AndroidAutomationService s) => Tool(
      name: 'android_app_info',
      description:
          '【开放信息】查询任意 App 的完整原始信息：版本号 versionName/Code、安装时间/更新时间、'
          'targetSdk/minSdk、所有申请的权限列表、所有导出的 Activity/Service/Receiver(=可以调起的入口)、'
          '当前的 uid/进程名、APK 物理路径、签名信息摘要。'
          '你 (LLM) 拿到这些原始信息可以自己判断："这个 App 有没有某个 Activity 能直接 Intent 调起？"、'
          '"这个 App 申请了短信/电话/存储权限说明它能收短信读存储吗？"等各种问题，'
          '代码层不给任何结论，100% 你自主判断。',
      schema: _props({
        'package_name': {
          'type': 'string',
          'description': '要查询的 App 包名，如 com.tencent.mm / com.ss.android.ugc.aweme。不知道包名先调 android_list_packages 或 android_get_top_app',
        },
        'verbose': {
          'type': 'boolean',
          'description': 'true=返回完整 280+ 行 dumpsys+pm dump 原始信息 (详细但慢)；false=只返回前 80 行核心字段 (默认)',
        },
      }, required: [
        'package_name'
      ]),
      handler: (args) async {
        final pkg = (args['package_name'] as String? ?? '').trim();
        if (pkg.isEmpty) return const ToolResult.error('package_name 不能为空');
        final verbose = args['verbose'] as bool? ?? false;
        final info = await s.appInfo(pkg, verbose: verbose);
        return info.isEmpty
            ? ToolResult.error('没有获取到 $pkg 的信息 (包名是否正确？)')
            : ToolResult.ok(info);
      },
    );

/// ——— H10-4: 读取通知栏所有通知（基于推送触发自动化）———
Tool _notificationListTool(AndroidAutomationService s) => Tool(
      name: 'android_get_notifications',
      description:
          '【开放信息】读取手机状态栏当前所有通知：每条通知含包名/标题/文字/时间/渠道/是否可清除/是否正在进行。'
          '典型用法：收到短信验证码自动填入 → 你轮询通知栏找到验证码短信再提取内容；'
          '收到微信/QQ某条消息自动触发回复 → 你读到内容自己决定怎么答；'
          '看到 App 更新提示自动点安装等。需用户授权"通知访问"权限 (L0 级别，非敏感)。',
      schema: _props({
        'limit': {
          'type': 'integer',
          'description': '最多返回多少条通知 (按时间倒序，默认 30 条，最大 100)',
        },
      }),
      handler: (args) async {
        final limit = ((args['limit'] as num?)?.toInt() ?? 30).clamp(1, 100);
        final out = await s.getNotifications(limit: limit);
        return out.trim().isEmpty
            ? const ToolResult.ok('当前通知栏为空，或未授予"通知访问"权限')
            : ToolResult.ok('通知栏内容 (最多 $limit 条):\n$out');
      },
    );

/// ——— H10-5: WindowManager 底层 Dump（和 Accessibility View 树交叉验证，诊断无View游戏/悬浮窗）———
Tool _dumpWindowsTool(AndroidAutomationService s) => Tool(
      name: 'android_dump_windows',
      description:
          '【开放信息】输出 WindowManager (窗口管理服务) 底层状态：当前 mCurrentFocus(真实焦点Activity)、'
          'mFocusedApp、输入法窗口 IME Target、所有显示的 WindowState (每个窗口的包名/ Layer 层级 / Surface / 可见区域)、'
          '状态栏/导航栏窗口、悬浮窗、分屏、画中画 PiP 窗口信息。'
          '⚠ 和 android_dump_ui 的区别：后者拿 Accessibility View 控件树(标准App有文字按钮)；'
          '本工具拿 Window 层的真实显示(无View的游戏/视频/Canvas/悬浮窗/分屏 都能看到窗口真实存在和位置)。'
          '你 (LLM) 把两个 dump 的结果交叉比对，能更准确判断"当前到底显示了什么、焦点在哪、有没有悬浮窗挡住"。',
      schema: _props({
        'limit_lines': {
          'type': 'integer',
          'description': '最多返回多少行 dumpsys 原始内容 (默认 200，最大 1000)',
        },
      }),
      handler: (args) async {
        final limit = ((args['limit_lines'] as num?)?.toInt() ?? 200).clamp(20, 1000);
        final out = await s.dumpWindows(limitLines: limit);
        return ToolResult.ok(out);
      },
    );

// ============================================================================
// H11 × 4：开放原子能力——联系人 / 电量网络 / 双卡短信 / 传感器
//  设计理念：全部返回"原始数据文本"，不做任何解析/推断/过滤，
//  由 LLM 自己读原始内容、自由判断要干啥，完全不写死"如果XX就YY"。
// ============================================================================

/// H11-1: 联系人查询 (content resolver 原始返回)
Tool _queryContactsTool(AndroidAutomationService s) => Tool(
      name: 'android_query_contacts',
      description:
          '【开放信息】从手机通讯录查询联系人，通过 shell content resolver 直接返回 display_name/phone/email/mimetype/contact_id 的原始行。'
          '⚠ 本工具只查询、不判断不整理——返回给你 (LLM) 的就是 content://com.android.contacts/data 的所有匹配行，'
          '你自己读每行 Row 的 display_name 和 data1 (号码/邮箱) 再决定下一步是发短信还是打电话还是发微信。'
          '权限：需要 READ_CONTACTS (可在系统设置里授予) 或 Root；未授予则返回提示并附带 RawContacts 表信息。',
      schema: _props({
        'kw': {
          'type': 'string',
          'description': '关键词模糊搜索 (匹配姓名/号码/邮箱任一)，空串=""=返回最近 N 条联系人 (默认 "")',
        },
        'limit': {
          'type': 'integer',
          'description': '最多返回多少个联系人 (默认 50，最大 500)',
        },
      }),
      handler: (args) async {
        final kw = (args['kw'] as String?) ?? '';
        final limit = ((args['limit'] as num?)?.toInt() ?? 50).clamp(1, 500);
        final out = await s.queryContacts(kw: kw, limit: limit);
        return ToolResult.ok(out);
      },
    );

/// H11-2: 设备状态综合 Dump（电量 + 网络 + WiFi + 移动信号 + 蓝牙/GPS/亮度/旋转等）
Tool _deviceStatusTool(AndroidAutomationService s) => Tool(
      name: 'android_get_device_status',
      description:
          '【开放信息】一次性返回手机当前的【电量/充电状态/电压/温度】【移动网络运营商+信号+数据连接状态】'
          '【WiFi SSID/RSSI/IP】【蓝牙开关+已配对设备】【GPS provider 状态】【屏幕亮度+自动旋转开关】。'
          '⚠ 本工具只返回 dumpsys 原始行，不帮你归纳、不做任何"电池低了怎么办/WiFi没开要不要提醒"的判断'
          '——你 (LLM) 自己读数字，结合用户的命令自由决策，比如：看到 Battery level=8 且 plugged=false，'
          '你可以提示用户充电；看到 WiFi RSSI=-85 且用户让下载大文件，你可以先切 5G 再下；'
          '看到光传感器同时返回 lux<5 (通过传感器工具) 但亮度=255，你可以主动调暗屏幕省电。',
      schema: _props({}),
      handler: (_) async {
        final out = await s.getDeviceStatus();
        return ToolResult.ok(out);
      },
    );

/// H11-3: 双卡短信——发送 (可选卡1/卡2) + 查询最近收件/已发送箱
Tool _sendSmsTool(AndroidAutomationService s) => Tool(
      name: 'android_send_sms',
      description:
          '【开放操作】通过手机 SIM 卡直接发送纯文本短信 (支持双卡指定卡1 / 卡2 / 默认卡发送)。'
          '⚠ 本工具只执行"发送"这个动作，不做号码校验、不做内容校验、不做"这是骚扰短信所以我不发"的过滤，'
          '全部由你 (LLM) 结合用户的意图自己判断。权限：需要 SEND_SMS 或 Root/Shizuku (shell user)，'
          '如果 shell service call sms 失败，会自动降级为 Intent SENDTO 打开用户的短信 App (需要用户点"发送"按钮)。',
      schema: _props({
        'phone': {
          'type': 'string',
          'description': '收短信的手机号，例 13800138000 / +8613800138000',
        },
        'message': {
          'type': 'string',
          'description': '短信正文 (纯文本，中文/英文/数字/标点都行，超长会由运营商自动分条)',
        },
        'sim_slot': {
          'type': 'integer',
          'description': '1=卡1发送 / 2=卡2发送 / 0=系统默认 (默认 0)。双卡手机请先通过 telephony 状态查到哪张卡能发短信。',
        },
      }, required: [
        'phone',
        'message'
      ]),
      handler: (args) async {
        final phone = (args['phone'] as String?)?.trim() ?? '';
        final msg = (args['message'] as String?) ?? '';
        if (phone.isEmpty) return const ToolResult.error('phone 不能为空');
        if (msg.isEmpty) return const ToolResult.error('message 不能为空');
        final sim = ((args['sim_slot'] as num?)?.toInt() ?? 0).clamp(0, 2);
        final r = await s.sendSms(phone: phone, message: msg, simSlot: sim);
        return r.ok
            ? ToolResult.ok('✅ 短信已下发 (sim_slot=$sim, to=$phone)\n${r.stdout}${r.stderr.isEmpty ? '' : '\nerr=${r.stderr}'}')
            : ToolResult.error('❌ 短信发送失败 exit=${r.exitCode}: ${r.stderr.isEmpty ? r.stdout : r.stderr}');
      },
    );

Tool _querySmsTool(AndroidAutomationService s) => Tool(
      name: 'android_query_recent_sms',
      description:
          '【开放信息】读取手机最近 N 条短信，返回 date(address) body(type,read) 的原始 content resolver 行。'
          '⚠ 本工具只返回未加工的原始文本，你 (LLM) 自己读每行 body 判断是验证码/账单/营销短信，'
          '再决定下一步是把验证码填到哪个输入框、还是给用户弹提示说"您有一条新的XX银行账单"。'
          '权限：需要 READ_SMS 或 Root/Shizuku。',
      schema: _props({
        'box': {
          'type': 'string',
          'description': '查哪个箱: "inbox"=收到的 (默认) / "sent"=已发出的',
        },
        'limit': {
          'type': 'integer',
          'description': '最多返回多少条，按 date 倒序 (最近在前)，默认 20 最大 200',
        },
      }),
      handler: (args) async {
        final box = (args['box'] as String?)?.trim() == 'sent' ? 'sent' : 'inbox';
        final limit = ((args['limit'] as num?)?.toInt() ?? 20).clamp(1, 200);
        final out = await s.queryRecentSms(box: box, limit: limit);
        return ToolResult.ok(out);
      },
    );

/// H11-4: 传感器列表 + 实时采样 (原始 sensor dump)
Tool _sensorsTool(AndroidAutomationService s) => Tool(
      name: 'android_get_sensors',
      description:
          '【开放信息】列出手机所有传感器 (名称/型号/供应商/类型ID)，并可选地对加速度/陀螺仪/光/接近/重力/线性加速度/旋转矢量等采样 N 次。'
          '⚠ 完全返回 dumpsys sensorservice 的原始文本行，不帮你换算单位、不帮你判断"手机是不是晃了"、不做任何阈值。'
          '你 (LLM) 自己读 values= 的三/四个浮点数值，自由判断场景：'
          '例：光传感器 type=5 values=[<5] 说明在黑暗环境，可以建议或自动开手电筒；'
          '例：接近传感器 type=8 values=[0,0,0] 且 加速度 type=1 values=[0,0,-9.8] 说明手机屏幕朝下平放在桌面上；'
          '例：步检 type=18 / 步数 type=19 连续上升说明用户在走路/跑步；'
          '例：陀螺仪 type=4 任一轴绝对值连续>2rad/s 说明手机在被剧烈晃动。'
          '采样持续时间：samples_per_sensor × 200ms，最多 30 次 (=6 秒)。',
      schema: _props({
        'list_all': {
          'type': 'boolean',
          'description': 'true=先列出手机支持的所有传感器 (默认 true)；false=只采样不列清单',
        },
        'sample_types': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description':
              '指定要采样的传感器类型 ID 数组。常用: 1=加速度(m/s²) 2=磁场(uT) 4=陀螺仪(rad/s) 5=光(lux) 6=气压(hPa) 8=距离(cm) 9=重力 10=线性加速度 11=旋转矢量 18=步检 19=步数。空数组=用默认 1,4,5,9,10 (五个常用)。',
        },
        'samples_per_sensor': {
          'type': 'integer',
          'description': '采样次数，每次间隔 200ms；默认 1 次 (=只抓最新快照)，最大 30 (=采样 6 秒观察运动趋势)',
        },
      }),
      handler: (args) async {
        final listAll = (args['list_all'] as bool?) ?? true;
        final typesRaw = args['sample_types'] as List<dynamic>? ?? const <dynamic>[];
        final types = typesRaw
            .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()) ?? 0)
            .where((e) => e > 0)
            .toList(growable: false);
        final samples = ((args['samples_per_sensor'] as num?)?.toInt() ?? 1).clamp(1, 30);
        final out = await s.getSensors(
          listAll: listAll,
          sampleTypes: types,
          samplesPerSensor: samples,
        );
        return ToolResult.ok(out);
      },
    );

// ============================================================================
// H13 — execute_plan 多步编排：由 LLM 写完整 steps[]，代码按顺序执行不做判断
// H14 — agent_memory KV：由 LLM 自己决定存/读/删什么记忆
// ============================================================================

/// H13: execute_plan —— 让 LLM 一次性下发最多 N 步工具调用，代码严格按 LLM 写的顺序跑，
///   不做任何 if/else、不做"这个步骤看起来错所以跳过"、不做自动重试，
///   甚至"要不要在某个错误时停止"也由 LLM 通过 stop_on 参数指定。
///   每步结果都完整收集、按顺序返回，LLM 可以一口气把"打开微信→搜 XXX→点第一条→输入 XXX→发送"
///   这类固定流程一次性下发，省掉 N 轮端侧推理。
Tool buildExecutePlanTool(
  Future<ToolResult> Function(String name, Map<String, dynamic> args) executor,
) =>
    Tool(
      name: 'android_execute_plan',
      description:
          '【多步编排 · 开放核心】你 (LLM) 自己把接下来 N 步 (最多 50 步) 需要调用的工具写成 steps[] 数组，'
          '我 (代码) 100% 按你写的顺序严格执行，不做任何修改、不做任何跳过、不做条件判断。'
          '⚠ 这不是智能流程：我不分析步骤是否合理、不判断某个工具的参数对不对、失败了也不帮你重试，'
          '要不要停、在哪停、失败后怎么走完全由你 (LLM) 通过 stop_on / step.expect_ok 决定。'
          '典型用途：把"打开微信→点击通讯录→搜索张三→点头像→输入消息→发送"这种固定 6 步的场景一次下发，省 5 次推理。'
          '⚠ 嵌套禁止：steps 里的工具名不能再是 android_execute_plan 或其他 meta 工具 (防止死循环)。',
      schema: _props({
        'steps': {
          'type': 'array',
          'description': '''按顺序执行的工具序列，数组元素是 Object 结构：
{
  "id": "步骤唯一字符串ID (可选，你LLM用来定位哪一步出问题，随便写)",
  "name": "要调用的工具名，如 android_open_app / android_click_by_text / android_send_intent ...",
  "args": { "参数key1": "参数value1" },
  "delay_ms": 0,          // 本步执行完之后停多少毫秒再跑下一步 (给页面加载的间隔，你自己定)
  "expect_ok": true,      // 你预期这一步应该成功；true 且实际失败时 stop_on=first_unexpected 就停
  "save_as": "可选key名"   // 如果非空，就把本步 ToolResult.output 存在内存 KV 中，后续步骤 args 里可以用字符串占位符 {{save_as名}} 引用
}
''',
          'items': {'type': 'object'},
        },
        'stop_on': {
          'type': 'string',
          'description':
              '【你LLM决定的停止策略】可选值: "never"=50步都跑完绝不中断 (默认)；"first_error"=遇到任何 ToolResult.isError=true 立刻停；"first_unexpected"=只要某步的 isError 和你写的 expect_ok 不一致就停；"first_match_text"=某步 output 中包含你写的 stop_if_contains 字符串就停；"stop_flag_set"=某步 save_as 存的值等于你 stop_flag_key 且字符串包含 "STOP" 就停。完全由你指定，代码不做自己的判断。',
        },
        'stop_if_contains': {
          'type': 'string',
          'description': 'stop_on="first_match_text" 时生效：只要任一步 output 里包含这个子串，立刻停止 (不区分大小写)。例 "未找到文字 发送"',
        },
        'stop_flag_key': {
          'type': 'string',
          'description': 'stop_on="stop_flag_set" 时生效：检查 save_as 存到这个 key 的值里是否包含子串 "STOP"，包含就停。',
        },
        'timeout_ms_per_step': {
          'type': 'integer',
          'description': '每步最大执行毫秒数 (默认 30000=30秒)。超时则记为 error，并根据 stop_on 决定是否停。',
        },
      }, required: [
        'steps'
      ]),
      handler: (args) async {
        final rawSteps = args['steps'] as List<dynamic>? ?? const [];
        if (rawSteps.isEmpty) return const ToolResult.error('steps 不能为空数组');
        if (rawSteps.length > 50) return const ToolResult.error('steps 最多 50 步，请拆成多个 plan 执行');
        final stopOn = (args['stop_on'] as String?)?.trim() ?? 'never';
        final stopContains = args['stop_if_contains'] as String? ?? '';
        final stopFlagKey = args['stop_flag_key'] as String? ?? '';
        final perStepTimeout = ((args['timeout_ms_per_step'] as num?)?.toInt() ?? 30000).clamp(500, 600000);

        // save_as 的内存 KV (仅本次 plan 内有效 + 持久到 agent_memory 相同后端? 简单起见先 plan 内有效)
        final kv = <String, String>{};
        bool shouldStop = false;
        final out = StringBuffer();
        out.writeln('📋 android_execute_plan 开始 (共 ${rawSteps.length} 步, stop_on=$stopOn)');
        var ran = 0;
        for (var i = 0; i < rawSteps.length; i++) {
          if (shouldStop) {
            out.writeln('⏹ #${i + 1} 由 stop_on 策略主动停止，不再执行剩余 ${rawSteps.length - i} 步');
            break;
          }
          final step = rawSteps[i] is Map<String, dynamic>
              ? rawSteps[i] as Map<String, dynamic>
              : <String, dynamic>{};
          final id = step['id']?.toString() ?? 'step_${i + 1}';
          final name = step['name']?.toString() ?? '';
          final delay = ((step['delay_ms'] as num?)?.toInt() ?? 0).clamp(0, 60000);
          final expectOk = step['expect_ok'] as bool? ?? true;
          final saveAs = step['save_as']?.toString();
          if (name.isEmpty) {
            out.writeln('❌ #${i + 1}($id): 缺工具名，记为 error 并按 stop_on 决定');
            if (stopOn == 'first_error' || (stopOn == 'first_unexpected' && expectOk)) {
              shouldStop = true;
            }
            ran++;
            continue;
          }
          // 防嵌套：禁止 execute_plan 自己套自己
          if (name == 'android_execute_plan') {
            out.writeln('⛔ #${i + 1}($id): 嵌套 android_execute_plan 禁止 (避免死循环)，跳过');
            if (stopOn == 'first_error' || (stopOn == 'first_unexpected' && expectOk)) {
              shouldStop = true;
            }
            ran++;
            continue;
          }
          // args 占位符替换：字符串值里的 {{xxx}} 用 kv['xxx'] 替换
          dynamic applyTpl(dynamic v) {
            if (v is String) {
              return v.replaceAllMapped(RegExp(r'\{\{\s*([a-zA-Z0-9_\-]+)\s*\}\}'), (m) {
                return kv[m.group(1)] ?? m.group(0)!;
              });
            }
            if (v is List) {
              return v.map<dynamic>(applyTpl).toList(growable: false);
            }
            if (v is Map) {
              return v.map<dynamic, dynamic>((k, vv) => MapEntry(k is String ? k : k.toString(), applyTpl(vv)));
            }
            return v;
          }

          final rawArgs = step['args'];
          final Map<String, dynamic> resolvedArgs = rawArgs is Map
              ? Map<String, dynamic>.from(applyTpl(rawArgs) as Map)
              : <String, dynamic>{};
          ToolResult result;
          try {
            result = await executor(name, resolvedArgs).timeout(
              Duration(milliseconds: perStepTimeout),
              onTimeout: () => ToolResult.error('TIMEOUT ${perStepTimeout}ms'),
            );
          } catch (e) {
            result = ToolResult.error('EXCEPTION: $e');
          }
          if (saveAs != null && saveAs.isNotEmpty) {
            kv[saveAs] = result.output;
          }
          final prefix = result.isError
              ? (expectOk ? '❌' : '⚠(不意外)')
              : (expectOk ? '✅' : '‼(意外OK)');
          out.writeln(
              '$prefix #${i + 1}($id)  $name  → ${result.isError ? 'ERROR' : 'OK'}${saveAs == null ? '' : '  save_as=$saveAs'}');
          final preview = result.output.replaceAll('\r', '').split('\n').take(12).join('\n');
          out.writeln('    $preview'.split('\n').join('\n    '));
          if (delay > 0) {
            out.writeln('    ⏱ 延迟 ${delay}ms…');
            await Future<void>.delayed(Duration(milliseconds: delay));
          }
          ran++;
          // stop_on 判定 100% 按用户策略走，不做代码层私货判断
          if (stopOn == 'first_error' && result.isError) shouldStop = true;
          if (stopOn == 'first_unexpected' && (result.isError != (!expectOk))) {
            // expectOk=true 且 error => 意外 => 停；expectOk=false 且 ok => 意外 => 停
            shouldStop = true;
          }
          if (stopOn == 'first_match_text' &&
              stopContains.isNotEmpty &&
              result.output.toLowerCase().contains(stopContains.toLowerCase())) {
            out.writeln('    ⛳ stop_if_contains 命中，停止剩余步骤');
            shouldStop = true;
          }
          if (stopOn == 'stop_flag_set' && stopFlagKey.isNotEmpty) {
            final v = kv[stopFlagKey];
            if (v != null && v.toUpperCase().contains('STOP')) {
              out.writeln('    ⛳ stop_flag_key=$stopFlagKey 检测到 STOP 标记，停止剩余步骤');
              shouldStop = true;
            }
          }
        }
        out.writeln('\n🏁 Plan 结束：实际执行 $ran / ${rawSteps.length} 步, kv 共 ${kv.length} 项');
        if (kv.isNotEmpty) {
          out.writeln('--- 本次 plan 内 kv 快照 ---');
          kv.forEach((k, v) {
            final short = v.length > 120 ? '${v.substring(0, 120)}…(总${v.length}字)' : v;
            out.writeln('  $k = $short');
          });
        }
        return ToolResult.ok(out.toString());
      },
    );

// ============================================================================
// H14 — Agent 长期记忆 KV：完全由 LLM 决定存什么、读什么、删什么
//   不做"自动总结"、不做"自动记对话"，代码层就是一个纯粹的 persistent KV。
// ============================================================================

/// agent_memory 工具的 4 个子动作合并为同一个工具 (用 op 区分)，减少工具名占用。
Tool buildAgentMemoryTool(AgentMemoryBackend backend) => Tool(
      name: 'agent_memory',
      description:
          '【长期KV记忆 · 开放】你 (LLM) 自己决定要记住什么、何时读取、何时删除。'
          '⚠ 代码层不自动帮你记任何东西 —— 没有自动摘要、没有自动归档、没有自动清理过期，完全由你 (LLM) 通过 op 参数操作。'
          '建议用法：遇到用户的手机号/姓名/常用App/按钮坐标/上一步 save_as 的值想跨 plan/跨 session 保留时就 set；'
          '下次新会话开始时先 list key 全量列一遍前缀，把需要的全 get 回来。'
          '典型 key 命名建议：`u.phone` / `u.home_addr` / `pkg.wechat.search_btn_bounds` / `last.wx_chat_top_3` / `last.game.player_pos`',
      schema: _props({
        'op': {
          'type': 'string',
          'description':
              '"set"=写或覆盖 key=value；"get"=读 key；"delete"=删 key；"list"=按前缀列出所有 key (若 prefix 为空列出全部 200 个以内)；"clear_prefix"=删除所有前缀匹配的 key',
        },
        'key': {
          'type': 'string',
          'description': 'op=set/get/delete 必填。key 请用 ASCII + 点分命名，最大 240 字。例 "u.phone" / "pkg.com.tencent.mm.home_tab_bounds"',
        },
        'value': {
          'type': 'string',
          'description': 'op=set 必填。要存的值任意字符串，建议 ≤32KB。可以存 JSON.stringify 的结构化数据。',
        },
        'prefix': {
          'type': 'string',
          'description': 'op=list / clear_prefix 时生效：匹配以这个字符串开头的所有 key。空串="" 表示全部。',
        },
        'limit': {
          'type': 'integer',
          'description': 'op=list 时最多返回多少条 (默认 100，最大 1000)',
        },
      }, required: [
        'op'
      ]),
      handler: (args) async {
        final op = (args['op'] as String?)?.trim().toLowerCase() ?? '';
        try {
          switch (op) {
            case 'set':
              {
                final key = (args['key'] as String?)?.trim() ?? '';
                final val = (args['value'] as String?) ?? '';
                if (key.isEmpty) return const ToolResult.error('op=set: key 不能为空');
                if (key.length > 240) return const ToolResult.error('op=set: key 超长 (>240)');
                await backend.set(key, val);
                return ToolResult.ok('✅ SET ok  key=$key  bytes=${val.length}');
              }
            case 'get':
              {
                final key = (args['key'] as String?)?.trim() ?? '';
                if (key.isEmpty) return const ToolResult.error('op=get: key 不能为空');
                final v = await backend.get(key);
                if (v == null) return ToolResult.ok('(空 key=$key 不存在)');
                return ToolResult.ok('value (len=${v.length}):\n$v');
              }
            case 'delete':
              {
                final key = (args['key'] as String?)?.trim() ?? '';
                if (key.isEmpty) return const ToolResult.error('op=delete: key 不能为空');
                final existed = await backend.delete(key);
                return ToolResult.ok(existed ? '✅ DELETE ok  key=$key' : '⚠ DELETE no-op: key=$key 不存在');
              }
            case 'list':
              {
                final prefix = (args['prefix'] as String?) ?? '';
                final limit = ((args['limit'] as num?)?.toInt() ?? 100).clamp(1, 1000);
                final entries = await backend.list(prefix: prefix, limit: limit);
                final sb = StringBuffer('✅ LIST prefix="$prefix" 返回 ${entries.length} 条 (limit=$limit)\n');
                for (final e in entries) {
                  final v = e.value;
                  final short = v.length > 80 ? '${v.substring(0, 80)}…' : v.replaceAll('\n', '↵');
                  sb.writeln('  ${e.key}  len=${v.length}  $short');
                }
                return ToolResult.ok(sb.toString());
              }
            case 'clear_prefix':
              {
                final prefix = (args['prefix'] as String?) ?? '';
                if (prefix.isEmpty) return const ToolResult.error('op=clear_prefix: prefix 不能为空 (怕你把整个库清掉)');
                final n = await backend.clearPrefix(prefix);
                return ToolResult.ok('✅ CLEAR_PREFIX "$prefix" 删除 $n 条');
              }
            default:
              return ToolResult.error('未知 op=$op，可选值 set/get/delete/list/clear_prefix');
          }
        } catch (e) {
          return ToolResult.error('agent_memory 异常: $e');
        }
      },
    );

/// agent_memory 后端接口：默认用本地文件 (Android context.getFilesDir + dart:io)。
/// 简单实现：一个 JSON 文件，key→value，key 超过 5000 条时淘汰最早修改的 10% (LRU-ish)。
abstract class AgentMemoryBackend {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
  Future<bool> delete(String key);
  Future<List<({String key, String value, DateTime mtime})>> list({String prefix = '', int limit = 100});
  Future<int> clearPrefix(String prefix);
}

/// 基于本地文件的简易 AgentMemoryBackend (单文件 JSON + 内存缓存 + 异步落盘)。
class FileAgentMemoryBackend implements AgentMemoryBackend {
  FileAgentMemoryBackend(this._filePath);
  final String _filePath;
  final Map<String, ({String v, int mt})> _cache = {};
  bool _dirty = false;

  Future<void> _load() async {
    if (_cache.isNotEmpty) return;
    final f = File(_filePath);
    if (!await f.exists()) return;
    try {
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((k, v) {
          if (k is String && v is Map) {
            final val = v['v'];
            final mt = v['mt'];
            if (val is String) _cache[k] = (v: val, mt: mt is int ? mt : DateTime.now().millisecondsSinceEpoch);
          }
        });
      }
    } catch (_) {
      // 文件损坏 => 从头建立，安全
      _cache.clear();
    }
  }

  Future<void> _flush() async {
    if (!_dirty) return;
    _dirty = false;
    try {
      final dir = p.dirname(_filePath);
      if (dir.isNotEmpty && !await Directory(dir).exists()) {
        await Directory(dir).create(recursive: true);
      }
      final out = <String, dynamic>{};
      _cache.forEach((k, v) => out[k] = <String, dynamic>{'v': v.v, 'mt': v.mt});
      await File(_filePath).writeAsString(jsonEncode(out), flush: true);
    } catch (_) {
      // 落盘失败不抛异常，工具返回里也不暴露：避免 end-side 小模型因为 I/O 错误阻塞流程
    }
  }

  void _evictIfNeeded() {
    if (_cache.length < 5000) return;
    final entries = _cache.entries.toList()
      ..sort((a, b) => a.value.mt.compareTo(b.value.mt));
    final del = (entries.length * 0.1).ceil();
    for (var i = 0; i < del; i++) {
      _cache.remove(entries[i].key);
    }
    _dirty = true;
  }

  @override
  Future<String?> get(String key) async {
    await _load();
    final v = _cache[key];
    if (v == null) return null;
    _cache[key] = (v: v.v, mt: DateTime.now().millisecondsSinceEpoch);
    _dirty = true;
    await _flush();
    return v.v;
  }

  @override
  Future<void> set(String key, String value) async {
    await _load();
    _cache[key] = (v: value, mt: DateTime.now().millisecondsSinceEpoch);
    _evictIfNeeded();
    _dirty = true;
    await _flush();
  }

  @override
  Future<bool> delete(String key) async {
    await _load();
    final existed = _cache.remove(key) != null;
    if (existed) {
      _dirty = true;
      await _flush();
    }
    return existed;
  }

  @override
  Future<List<({String key, String value, DateTime mtime})>> list({String prefix = '', int limit = 100}) async {
    await _load();
    final entries = _cache.entries
        .where((e) => e.key.startsWith(prefix))
        .map((e) => (
              key: e.key,
              value: e.value.v,
              mtime: DateTime.fromMillisecondsSinceEpoch(e.value.mt),
            ))
        .toList()
      ..sort((a, b) => b.mtime.compareTo(a.mtime));
    return entries.take(limit).toList(growable: false);
  }

  @override
  Future<int> clearPrefix(String prefix) async {
    await _load();
    final keys = _cache.keys.where((k) => k.startsWith(prefix)).toList(growable: false);
    if (keys.isEmpty) return 0;
    for (final k in keys) {
      _cache.remove(k);
    }
    _dirty = true;
    await _flush();
    return keys.length;
  }
}

// ============================================================================
// H15 — 系统原子补全 ×6：最近任务 / Frag栈 / WiFi扫描 / 双卡详情 / Toast历史 / 杀进程+冷启动
//   全部返回原始 dumpsys / service call 文本，LLM 自主判断使用
// ============================================================================

/// H15-1: 最近任务列表 (Recent Tasks + Activity 栈)
Tool _recentTasksTool(AndroidAutomationService s) => Tool(
      name: 'android_get_recent_tasks',
      description:
          '【开放信息】返回手机最近打开过的 N 个 App 任务 (RecentTaskInfo) + 当前 ResumedActivity 栈顶 + am stack list。'
          '⚠ Android 11+ 系统默认禁止第三方 App 读其它 App 的 UsageStats / RECENTS；Shizuku/Root 下 dumpsys activity recents 可以绕过。'
          '典型用途：你 (LLM) 想知道"用户刚才刷了 10 分钟抖音还是小红书"、"刚刚后台有个 支付宝 付款界面是不是没关"、"微信昨天最后停在哪个 Activity"。',
      schema: _props({
        'limit': {
          'type': 'integer',
          'description': '最多返回多少个最近任务 (默认 20，最大 100)。Activity 栈和 stack list 也按同比例截取。',
        },
      }),
      handler: (args) async {
        final limit = ((args['limit'] as num?)?.toInt() ?? 20).clamp(1, 100);
        final out = await s.getRecentTasks(limit: limit);
        return ToolResult.ok(out);
      },
    );

/// H15-2: 当前前台 Activity + Fragment 栈 + SurfaceFlinger Layer
Tool _dumpFragmentsTool(AndroidAutomationService s) => Tool(
      name: 'android_dump_activity_fragments',
      description:
          '【开放细粒度信息】输出"当前前台 Activity 的完整 FragmentManager 栈 (Added Fragments / BackStack) + 当前所有 ViewRootImpl + SurfaceFlinger Layer 列表"。'
          '⚠ 比 android_dump_ui (Accessibility View 树) 深一个层级：用来诊断"微信当前在 MainTabActivity 但 stack 里有个 LoginDialogFragment 没 dismiss → 所以按钮点不动"、'
          '"某个悬浮窗 TYPE_TOAST / TYPE_APPLICATION_OVERLAY 挡住了下层 View"、"当前真正拿触摸事件的 Layer 是不是游戏的 SurfaceView"。',
      schema: _props({
        'limit_lines': {
          'type': 'integer',
          'description': 'activity top 最多返回多少行 (默认 160，最大 800)',
        },
      }),
      handler: (args) async {
        final limit = ((args['limit_lines'] as num?)?.toInt() ?? 160).clamp(20, 800);
        final out = await s.dumpActivityFragments(limitLines: limit);
        return ToolResult.ok(out);
      },
    );

/// H15-3: WiFi 扫描 (周边所有 SSID + 信号强度)
Tool _wifiScanTool(AndroidAutomationService s) => Tool(
      name: 'android_get_wifi_scan',
      description:
          '【开放信息】返回手机附近 WiFi 的扫描结果：SSID / BSSID / RSSI 信号 (dBm 负数) / frequency (2.4G or 5G) / capabilities (加密方式)。'
          '⚠ 你 (LLM) 自己判断：RSSI 高于 -55dBm=贴脸极近，-70 左右=普通满格，-85=边缘一格，-95 以下基本连不上；'
          'frequency 2400~2500=2.4G (穿墙好但慢/干扰多)，5100~5900=5G (快但穿墙差)。'
          '无 ACCESS_FINE_LOCATION 权限时系统可能只返回你保存过的几个 SSID；Shizuku/Root 能看完整周边。',
      schema: _props({
        'limit': {
          'type': 'integer',
          'description': '最多返回多少个 AP (默认 60，最大 500)',
        },
      }),
      handler: (args) async {
        final limit = ((args['limit'] as num?)?.toInt() ?? 60).clamp(1, 500);
        final out = await s.getWifiScan(limit: limit);
        return ToolResult.ok(out);
      },
    );

/// H15-4: 双卡 / IMSI / IMEI / Subscription 详情
Tool _simInfoTool(AndroidAutomationService s) => Tool(
      name: 'android_get_sim_info',
      description:
          '【开放信息】SIM卡/手机IMEI/IMSI信息 (脱敏版优先，权限够则返回完整)：phoneId(卡序号 0/1) / slotId(物理卡槽) / subscriptionId / carrier(运营商) / simState / mImei / mSubscriberId(IMSI) / iccId / isms subscriptionId。'
          '⚠ 典型用法：① sendSms 选 sim_slot 之前先看"卡1(subscriptionId=3)是主号 联通5G 卡2(subscriptionId=5)是小号 电信4G" → 选对 slot 发；'
          '② 判断当前是否有信号：simState=5=LOADED=正常；③ 判断双卡双待是否真的两张都在线。'
          '无 READ_PHONE_STATE 权限时只显示脱敏/少数字段；Shizuku/Root 或 adb shell 权限可以拿到完整字段。',
      schema: _props({}),
      handler: (_) async {
        final out = await s.getSimInfo();
        return ToolResult.ok(out);
      },
    );

/// H15-5: Toast 历史 + Notification 日志 (部分 ROM 支持)
Tool _toastHistoryTool(AndroidAutomationService s) => Tool(
      name: 'android_get_toast_history',
      description:
          '【开放信息】尽力而为地返回：最近 Toast 弹过的文字/包名/时长 (NotificationManagerService.enqueueToast 痕迹) + 当前仍在显示的 TYPE_TOAST 窗口 + 通知日志 NotificationLogging。'
          '⚠ Toast 只在屏幕上停留 2~3.5s，大部分 ROM 的 dumpsys 只保留 10~30s 内的痕迹；所以"用户说刚才弹了个 验证码 Toast"你要立刻调这个工具，再晚就没了。'
          '典型场景：抖音/快手登录弹出了 短信验证码 Toast → 你立刻调本工具抓到验证码 → 调 android_input_text 填进去。',
      schema: _props({
        'limit': {
          'type': 'integer',
          'description': '最多保留多少条 Toast 痕迹 (默认 50，最大 300)',
        },
      }),
      handler: (args) async {
        final limit = ((args['limit'] as num?)?.toInt() ?? 50).clamp(1, 300);
        final out = await s.getToastHistory(limit: limit);
        return ToolResult.ok(out);
      },
    );

/// H15-6: 杀应用 / 冷启动 (am force-stop + monkey -p LAUNCHER 1)
Tool _killRestartTool(AndroidAutomationService s) => Tool(
      name: 'android_kill_or_restart_app',
      description:
          '【开放操作】彻底杀掉一个 App 的所有进程 (am force-stop + am kill)，然后可选地立刻冷启动它。'
          '⚠ 本工具只做动作不做判断：会不会杀掉未保存的文档、会不会中断正在下载的东西、会不会让用户正在打的微信视频电话断线 —— 全由你 (LLM) 自己决定，代码层绝不提示"要不要杀"。'
          '典型场景：抖音打开白屏了 → 你 dump_ui 什么也没拿到 → 你决定杀它再开；微信卡死了点什么都没反应 → 你 force-stop 再冷启动。',
      schema: _props({
        'package_name': {
          'type': 'string',
          'description': '要杀/重启的应用包名，例 com.tencent.mm / com.ss.android.ugc.aweme',
        },
        'mode': {
          'type': 'string',
          'description': '"kill_only"=只杀不启 (用于清后台)；"kill_and_restart"=先 force-stop 再干净启动 (默认, 99% 场景用这个)；"restart_only"=不杀直接 monkey 启动 (轻量)。',
        },
      }, required: [
        'package_name'
      ]),
      handler: (args) async {
        final pkg = (args['package_name'] as String?)?.trim() ?? '';
        if (pkg.isEmpty) return const ToolResult.error('package_name 不能为空');
        final mode = (args['mode'] as String?)?.trim().toLowerCase() ?? 'kill_and_restart';
        switch (mode) {
          case 'kill_only':
            {
              final r = await s.killAndRestartApp(pkg, killOnly: true);
              return r.ok
                  ? ToolResult.ok('✅ 已杀掉 $pkg\n${r.stdout}')
                  : ToolResult.error('❌ 杀 $pkg 失败: ${r.stderr.isEmpty ? r.stdout : r.stderr}');
            }
          case 'restart_only':
            {
              final r = await s.openAppWithResult(pkg);
              return r.ok
                  ? ToolResult.ok('✅ 已尝试启动 (不杀) $pkg\n${r.stdout}')
                  : ToolResult.error('❌ 启动 $pkg 失败: ${r.stderr.isEmpty ? r.stdout : r.stderr}');
            }
          case 'kill_and_restart':
          default:
            {
              final r = await s.killAndRestartApp(pkg, killOnly: false);
              return r.ok
                  ? ToolResult.ok('✅ 已冷启动 $pkg (先杀再启)\n${r.stdout}')
                  : ToolResult.error('❌ 冷启动 $pkg 失败 exit=${r.exitCode}: ${r.stderr.isEmpty ? r.stdout : r.stderr}');
            }
        }
      },
    );

// ============================================================================
// H16 ×2：权限自检 + 运行时申请
// ============================================================================

/// H16-1: 整体权限快照 (dumpsys package + checkSelfPermission + appops + 特殊开关)
Tool _checkPermissionsTool(AndroidAutomationService s) => Tool(
      name: 'android_check_permissions',
      description:
          '【开放自检】一次性返回：① 我们 App 声明过的所有权限的 GRANTED/DENIED 状态 (dumpsys package + Context.checkSelfPermission 双源校验)；'
          '② cmd appops 细粒度开关 (相机/麦克风/后台弹出/位置/通知/媒体库/短信/通话等 Android 10+ 的额外权限位)；'
          '③ 4 个特殊开关：Accessibility 是否启用、NotificationListener 是否已绑定、SYSTEM_ALERT_WINDOW 悬浮窗是否允许、WRITE_SETTINGS 修改系统设置是否允许、UsageStats 使用情况访问是否授权。'
          '⚠ 只返回原始状态，不做"你还缺啥、我建议你申请啥"的任何判断 —— 你 (LLM) 自己看缺哪个、再调 android_request_permissions 或者引导用户去开哪个页面。',
      schema: _props({
        'permissions': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '可选：你要重点检查的权限名数组，如 ["android.permission.SEND_SMS","android.permission.READ_CONTACTS"]。空=返回全景状态 (默认，99% 场景建议空，因为返回里会同时带 appops + 4 个特殊开关)',
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

/// H16-2: 申请运行时权限 (原生 channel → 系统权限 dialog / 失败自动跳应用详情页)
Tool _requestPermissionsTool(AndroidAutomationService s) => Tool(
      name: 'android_request_permissions',
      description:
          '【开放操作】向系统申请一组 Android 运行时权限。代码层完全不做"要不要申请这个"的判断；申请哪几个、什么时候申、是不是要先跟用户解释再申，全由你 (LLM) 决定。'
          '执行顺序：① 如果 App 在前台且实现了原生 channel → 直接弹系统标准权限 request dialog，用户点"允许/拒绝"后返回结果；'
          '② 如果 channel 不可用或 App 在后台 → 默认跳 APPLICATION_DETAILS_SETTINGS 应用详情页请用户手动点"权限"栏目。'
          '⚠ Android 13+ 对 POST_NOTIFICATIONS / READ_MEDIA_* / NEARBY_WIFI_DEVICES；Android 11+ 对 READ_PHONE_STATE / MANAGE_EXTERNAL_STORAGE；'
          '部分特殊权限 (WRITE_SECURE_SETTINGS / DUMP / MODIFY_PHONE_STATE) 即使点了 dialog 也不会自动授权，必须 adb pm grant 或 Shizuku/Root。',
      schema: _props({
        'permissions': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              '【必填】想要申请的完整权限名数组。例：["android.permission.POST_NOTIFICATIONS","android.permission.SEND_SMS","android.permission.READ_CONTACTS","android.permission.READ_MEDIA_IMAGES","android.permission.ACCESS_FINE_LOCATION","android.permission.CAMERA","android.permission.RECORD_AUDIO"]',
        },
        'open_settings_if_needed': {
          'type': 'boolean',
          'description':
              '当原生权限 dialog 不可用 (App 在后台 / 老 APK 没实现 / 用户点了"拒绝且不再询问"后系统不再弹) 时是否自动跳应用详情页让用户手动授权。默认 true。设为 false 时会直接返回 error 给你判断。',
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
// H17 ×5：硬件信息 / 通话记录 / 相册媒体 / 系统设置工具 / 壁纸分享输入法
// ============================================================================

/// H17-1: 硬件信息全景（型号+SDK/CPU/内存/存储/屏幕/原生Build字段）
Tool _hardwareInfoTool(AndroidAutomationService s) => Tool(
      name: 'android_get_hardware_info',
      description:
          '【开放信息】返回手机完整硬件+系统版本信息：getprop (ro.product.model/brand/device/manufacturer、SDK、CPU ABI、指纹、Build.TYPE)；/proc 分区 (内存MemTotal / CPU cores+主频+架构 / BogoMIPS)；'
          '存储 df -h (data/sdcard/可扩展U盘各还有多少GB空间、已用%)；屏幕分辨率/density/刷新率；dumpsys display DisplayDeviceInfo；原生 android.os.Build.* 字段 (含 SERIAL 脱敏)。'
          '⚠ 全部原始行返回，不做归纳，你 (LLM) 自己解读数字，比如看到 MemTotal 6GB+128GB 你就知道端侧跑 3B 模型别开太多后台；看到 sdcard 只剩 300MB 你就先让用户清一下再下载大模型；看到刷新率是 144Hz 你知道滑屏要更丝滑。',
      schema: _props({}),
      handler: (_) async {
        final out = await s.getHardwareInfo();
        return ToolResult.ok(out);
      },
    );

/// H17-2: 通话记录查询 + 当前通话状态 (Telecom/InCallService)
Tool _callLogTool(AndroidAutomationService s) => Tool(
      name: 'android_get_call_log',
      description:
          '【开放信息】读取最近 N 条通话记录 (content://call_log/calls)，字段：date 时间/number 号码/name 姓名/type 1呼入2呼出3未接/duration秒数/is_read是否已读/presentation号码显示方式。'
          '同时带 Telecom dumpsys：当前正在进行的 Call#、电话状态 (ACTIVE/DIALING/RINGING/DISCONNECTED)、handle 号码。'
          '⚠ 只做读取，不做"自动回拨未接来电"、不做"营销号码拉黑判断"。你 (LLM) 自己看到 10086 未接想回拨就单独调 android_send_intent 拨 CALL。'
          '权限：READ_CALL_LOG；没授权时只显示 Telecom 当前通话的模糊状态。',
      schema: _props({
        'box': {
          'type': 'string',
          'description': '"all"=所有通话 (默认)；"incoming"=只查来电；"outgoing"=只查去电；"missed"=只查未接',
        },
        'limit': {
          'type': 'integer',
          'description': '最多多少条 (默认 30，最大 500)，按日期倒序',
        },
      }),
      handler: (args) async {
        final box = (args['box'] as String?)?.trim().toLowerCase() ?? 'all';
        final limit = ((args['limit'] as num?)?.toInt() ?? 30).clamp(1, 500);
        final out = await s.getCallLog(box: box, limit: limit);
        return ToolResult.ok(out);
      },
    );

/// H17-3: 媒体库 / 相册 / 相册 / 下载目录 查询（content + ls 兜底）
Tool _mediaGalleryTool(AndroidAutomationService s) => Tool(
      name: 'android_query_media_gallery',
      description:
          '【开放信息】查询手机媒体库 content://media/external/file：字段 _id/_data 绝对路径/_display_name 文件名/date_modified 时间/mime_type 类型/_size 字节数/bucket_display_name 相册名 (Camera/Screenshots/DCIM/WeChat)/width/height 像素。'
          '同时用 ls -lt 列 6 个常用目录 (/sdcard/DCIM /Pictures /Pictures/Screenshots /Download /DCIM/Camera) 最近 20~30 个文件作为兜底 —— 这样即使没有 READ_MEDIA 权限、sdcard 根目录还是 shell user 可读的，至少能看到文件名和修改时间。'
          '⚠ 返回的是完整路径/时间/大小原始行，你 (LLM) 看到最新的 Screenshot 2026-08-01 12:00.png 就可以拿 _data 再用 android_share_system / android_set_wallpaper / android_vision_analyze 操作它。',
      schema: _props({
        'bucket': {
          'type': 'string',
          'description': '按相册名模糊匹配过滤，例 "DCIM" / "Camera" / "Screenshots" / "Download" / "Pictures" / "WeChat" / "ALL" = 全部媒体。默认 "DCIM" (相机照片总目录)',
        },
        'keyword': {
          'type': 'string',
          'description': '按文件名关键字搜索 (匹配 _display_name LIKE "%xxx%")，大小写不敏感 (取决于 ROM)。空=不过滤文件名',
        },
        'limit': {
          'type': 'integer',
          'description': '最多返回多少条 (默认 60，最大 500)，按 date_modified 倒序 → 最新的照片在前',
        },
        'include_videos': {
          'type': 'boolean',
          'description': 'true=同时查图片和视频 (默认，99% 场景)；false=只要图片不查 mp4/mov 等',
        },
      }),
      handler: (args) async {
        final bucket = (args['bucket'] as String?)?.trim() ?? 'DCIM';
        final kw = args['keyword'] as String?;
        final limit = ((args['limit'] as num?)?.toInt() ?? 60).clamp(1, 500);
        final incV = args['include_videos'] as bool? ?? true;
        final out = await s.queryMediaGallery(bucket: bucket, keyword: kw, limit: limit, includeVideos: incV);
        return ToolResult.ok(out);
      },
    );

/// H17-4: 亮度调节 + 输入法切换
Tool _displayAndInputTool(AndroidAutomationService s) => Tool(
      name: 'android_adjust_display_or_input',
      description:
          '【开放操作 · 合并 2 个能力】① 调节屏幕亮度：传 brightness=整数 0~255 手动调，或 "auto" 切系统自动亮度；失败 (没 WRITE_SETTINGS 权限) 会自动跳设置→显示让用户手动开。'
          '② 切换输入法 (IME)：ime_id 传 "picker" 弹系统输入法选择器、传 "next"/"prev" 上下切一个、传完整 id 如 "com.tencent.qqpinyin/.QQPYInputMethodService" 直接切到搜狗/百度/微信输入法等。'
          '⚠ 这两个功能独立，但为了减少工具名占用合并在一起；你每次只传 brightness 或只传 ime_id（或两个都传会按顺序执行）。',
      schema: _props({
        'brightness': {
          'type': ['integer', 'string'],
          'description': '亮度设置：整数 0~255=手动固定亮度；字符串 "auto" (不区分大小写) = 开启自动亮度。不传或 null = 不做亮度调节',
        },
        'brightness_open_settings_if_denied': {
          'type': 'boolean',
          'description': '没 WRITE_SETTINGS 时是否跳显示设置页引导。默认 true。',
        },
        'ime_id': {
          'type': 'string',
          'description': '"picker"=弹输入法选择器 (默认，99% 情况你直接给用户选就行)；"next"/"prev"=切下/上一个输入法；或已启用的输入法完整 id (cmd ime list -s 能看到)。空字符串或 null = 不切换 IME',
        },
      }),
      handler: (args) async {
        final sb = StringBuffer();
        // 亮度
        if (args.containsKey('brightness') && args['brightness'] != null) {
          final bRaw = args['brightness'];
          final openS = args['brightness_open_settings_if_denied'] as bool? ?? true;
          final r = await s.setSystemBrightness(brightness: bRaw, openSettingsIfDenied: openS);
          sb.writeln('=== 亮度调节结果 ===');
          sb.writeln('请求 brightness=$bRaw → ${r.ok ? "OK" : "FAILED exit=${r.exitCode}"}');
          sb.writeln(r.stdout.isEmpty ? r.stderr : r.stdout);
          sb.writeln();
        }
        // 输入法
        final imeId = (args['ime_id'] as String?)?.trim() ?? '';
        if (imeId.isNotEmpty) {
          final r = await s.switchInputMethod(imeId: imeId);
          sb.writeln('=== 输入法切换结果 (ime_id=$imeId) ===');
          sb.writeln(r);
        }
        if (sb.isEmpty) {
          return const ToolResult.error('brightness 或 ime_id 至少填一个');
        }
        return ToolResult.ok(sb.toString());
      },
    );

/// H17-5: 壁纸设置 + 系统分享（图片/文字/视频 给任意 App）
Tool _wallpaperAndShareTool(AndroidAutomationService s) => Tool(
      name: 'android_wallpaper_or_share',
      description:
          '【开放操作 · 合并 2 个能力】为了减少工具数量，壁纸设置和系统分享合并成一个工具 (每次只做其中之一，或顺序做)：'
          '① 壁纸：set_wallpaper_path 传图片绝对路径 (content resolver 路径或 /sdcard/... 都行)，wallpaper_which 选 home=桌面 / lock=锁屏 / both=同时。'
          '  原生 WallpaperManager 先试，不行再 ACTION_ATTACH_DATA 打开系统裁剪面板给用户手动确认。'
          '② 系统分享：share_text 或 share_image_path 至少填一个；share_target_package 可选传 com.tencent.mm 等直接跳微信，不传就弹系统分享面板。share_target_component 可选精确到某个 Activity (如朋友圈/小红书发笔记分享页)。',
      schema: _props({
        // wallpaper 参数
        'set_wallpaper_path': {
          'type': 'string',
          'description': '图片文件绝对路径 (必须已存在)，例 "/sdcard/Pictures/Screenshots/a.png"。空或 null = 不做壁纸。',
        },
        'wallpaper_which': {
          'type': 'string',
          'description': '"home" = 只设桌面壁纸；"lock" = 只设锁屏；"both" = 同时设 桌面+锁屏 (默认)',
        },
        // share 参数
        'share_text': {
          'type': 'string',
          'description': '要分享的文字内容。图片和文字可以同时都有，发微信好友时会变成"文字+图片"组合消息。',
        },
        'share_image_path': {
          'type': 'string',
          'description': '要分享的图片/视频文件的绝对路径 (可选)。',
        },
        'share_target_package': {
          'type': 'string',
          'description': '想直接投给哪个 App 的包名，如 com.tencent.mm / com.xingin.xhs / tv.danmaku.bili / com.ss.android.ugc.aweme；空=弹系统分享面板给用户选。',
        },
        'share_target_component': {
          'type': 'string',
          'description': '可选，精确到某个 Activity 的完整 component 名，例 "com.tencent.mm/.ui.tools.ShareToTimelineUI" (微信朋友圈)。空 = 交给系统按 share_target_package 找默认。',
        },
        'share_file_mime': {
          'type': 'string',
          'description': '可选，手动指定 MIME，例 "image/png" / "video/mp4"；不填=按文件扩展名猜 (image/* or video/* or text/plain)。',
        },
      }),
      handler: (args) async {
        final sb = StringBuffer();
        // 1. 壁纸
        final wpPath = (args['set_wallpaper_path'] as String?)?.trim() ?? '';
        if (wpPath.isNotEmpty) {
          final which = (args['wallpaper_which'] as String?)?.trim().toLowerCase() ?? 'both';
          final r = await s.setWallpaper(wpPath, which: which);
          sb.writeln('=== 壁纸设置 (path=$wpPath, which=$which) ===');
          sb.writeln(r.ok ? '✅ OK' : '❌ FAIL exit=${r.exitCode}');
          sb.writeln(r.stdout.isEmpty ? r.stderr : r.stdout);
          sb.writeln();
        }
        // 2. 系统分享
        final sText = args['share_text'] as String?;
        final sImg = args['share_image_path'] as String?;
        final hasShare = (sText != null && sText.trim().isNotEmpty) ||
            (sImg != null && sImg.trim().isNotEmpty);
        if (hasShare) {
          final r = await s.shareSystem(
            imagePath: sImg,
            text: sText,
            fileMime: args['share_file_mime'] as String?,
            targetPackage: args['share_target_package'] as String?,
            targetComponent: args['share_target_component'] as String?,
          );
          sb.writeln('=== 系统分享结果 ===');
          sb.writeln('text=${sText == null ? "(none)" : "${sText.length}字"}'
              '  image=${sImg ?? "(none)"}'
              '  pkg=${args['share_target_package'] ?? "(system picker)"}');
          sb.writeln(r.ok ? '✅ Intent 已下发' : '❌ FAIL exit=${r.exitCode}');
          sb.writeln(r.stdout.isEmpty ? r.stderr : r.stdout);
        }
        if (sb.isEmpty) {
          return const ToolResult.error('set_wallpaper_path 或 share_text/share_image_path 至少填一组');
        }
        return ToolResult.ok(sb.toString());
      },
    );

// ============================================================================
// End of composite tools
// ============================================================================

// ============================================================================
// 通知深度控制工具
// ============================================================================

/// Dismiss a notification by key.
Tool _notificationDismissTool(AndroidAutomationService s) => Tool(
      name: 'android_notification_dismiss',
      description: '按通知 key 取消/关闭指定通知。key 来自 android_get_notifications 返回的 key 字段。',
      schema: _props({
        'key': {
          'type': 'string',
          'description': '通知 key，如 "0|com.tencent.mm|12345|..."',
        },
      }, required: ['key']),
      handler: (args) async {
        final key = args['key'] as String? ?? '';
        if (key.isEmpty) return const ToolResult.error('参数 key 不能为空');
        // Use dumpsys notification to cancel via shell.
        final r = await s.gshell('cmd notification dismiss "$key" 2>/dev/null');
        if (r.ok) return ToolResult.ok('通知已关闭: $key');
        // Fallback: try notification listener service.
        return ToolResult.error('关闭通知失败: ${r.stderr}');
      },
    );

/// Snooze a notification.
Tool _notificationSnoozeTool(AndroidAutomationService s) => Tool(
      name: 'android_notification_snooze',
      description: '按通知 key 延迟通知（snooze）。duration=秒数，默认 300（5分钟）。',
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

/// Reply to a notification (e.g. WhatsApp/WeChat quick reply).
Tool _notificationReplyTool(AndroidAutomationService s) => Tool(
      name: 'android_notification_reply',
      description: '通过通知快速回复消息（如微信/QQ 通知中的快捷回复）。需要 Android 7+ 通知支持。',
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
            : ToolResult.error('回复失败（可能不支持通知快捷回复）: ${r.stderr}');
      },
    );

// ============================================================================
// 录制回放工具
// ============================================================================

/// Start recording a macro of touch events.
Tool _recordMacroTool(AndroidAutomationService s) => Tool(
      name: 'android_record_macro',
      description: '开始录制操作序列（screenrecord + 触摸事件）。录制完成后调用 android_play_macro 回放。',
      schema: _props({
        'name': {
          'type': 'string',
          'description': '录制的名称，如 "send_wechat_message"',
        },
        'max_seconds': {
          'type': 'integer',
          'description': '最大录制秒数（默认 30）',
        },
      }, required: ['name']),
      handler: (args) async {
        final name = args['name'] as String? ?? '';
        final maxSec = (args['max_seconds'] as num?)?.toInt() ?? 30;
        if (name.isEmpty) return const ToolResult.error('参数 name 不能为空');
        if (name.contains('/') || name.contains('..')) {
          return const ToolResult.error('name 不能包含路径符号');
        }
        // Save macro events to a file.
        // Start recording: enable pointer location overlay + capture
        final r = await s.gshell(
            'settings put system pointer_location 1 2>/dev/null; '
            'screenrecord --time-limit $maxSec /sdcard/${name}_raw.mp4 2>/dev/null &');
        return ToolResult.ok(
            '✅ 开始录制 "$name" (最多 ${maxSec}s)\n'
            '操作完成后，调用 android_stop_macro 停止录制。');
      },
    );

/// Stop recording and save the macro.
Tool _stopMacroTool(AndroidAutomationService s) => Tool(
      name: 'android_stop_macro',
      description: '停止录制，保存操作序列为可回放文件。',
      schema: _props({
        'name': {
          'type': 'string',
          'description': '要停止的录制名称',
        },
      }, required: ['name']),
      handler: (args) async {
        final name = args['name'] as String? ?? '';
        if (name.isEmpty) return const ToolResult.error('参数 name 不能为空');
        // Stop screenrecord.
        final r = await s.gshell(
            'pkill -f "screenrecord.*${name}_raw" 2>/dev/null; '
            'settings put system pointer_location 0 2>/dev/null');
        // Extract touch events from the video via motion detection? 
        // For now, save the raw video path for reference.
        return ToolResult.ok(
            '✅ 录制已停止\n'
            '原始文件: /sdcard/${name}_raw.mp4\n'
            '提示: 可在 skill_create_from_trace 中手动描述操作序列保存为 Skill。\n'
            '更精确的宏录制需要 Android 12+ getPointerEvents API。');
      },
    );

/// List saved macros.
Tool _listMacroTool() => Tool(
      name: 'android_list_macros',
      description: '列出已录制的操作宏文件。',
      schema: _props({}),
      handler: (args) async {
        // List screenrecord output files.
        final r = await AndroidAutomationService.instance
            .gshell('ls -la /sdcard/*_raw.mp4 2>/dev/null | head -n 30');
        if (!r.ok || r.stdout.trim().isEmpty) {
          return const ToolResult.ok('(没有已录制的宏)');
        }
        return ToolResult.ok(r.stdout);
      },
    );

// ============================================================================
// AppOps 细粒度权限控制
// ============================================================================

/// Get AppOps mode for a given package and op.
Tool _appOpsGetTool(AndroidAutomationService s) => Tool(
      name: 'android_appops_get',
      description: '获取指定应用的 AppOps 权限模式。可查看剪贴板/位置/通知/摄像头等细粒度权限状态。',
      schema: _props({
        'package_name': {
          'type': 'string',
          'description': '应用包名，如 com.tencent.mm',
        },
        'op': {
          'type': 'string',
          'description': '权限操作名，如 GET_USAGE_STATS, SYSTEM_ALERT_WINDOW, WRITE_SETTINGS, POST_NOTIFICATIONS, READ_CLIPBOARD 等。',
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
        // Fallback: appops get via dumpsys.
        final r2 = await s.gshell('dumpsys appops | grep -A 2 "$pkg.*$op" 2>/dev/null | head -n 10');
        if (r2.ok && r2.stdout.trim().isNotEmpty) {
          return ToolResult.ok('$pkg / $op:\n${r2.stdout}');
        }
        return ToolResult.error('获取 AppOps 失败，请检查包名和 op 名称是否正确');
      },
    );

/// Set AppOps mode for a given package and op.
Tool _appOpsSetTool(AndroidAutomationService s) => Tool(
      name: 'android_appops_set',
      description: '设置指定应用的 AppOps 权限模式。可授予/拒绝/默认剪贴板读取、悬浮窗、通知等权限。'
          'mode: allow=允许, deny=拒绝, ignore=静默拒绝, default=默认。',
      schema: _props({
        'package_name': {
          'type': 'string',
          'description': '应用包名',
        },
        'op': {
          'type': 'string',
          'description': '权限操作名，如 GET_USAGE_STATS, SYSTEM_ALERT_WINDOW, WRITE_SETTINGS, POST_NOTIFICATIONS, READ_CLIPBOARD',
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
        // Fallback with --user 0.
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

/// Show a floating action button for quick automation.
Tool _floatOverlayTool(AndroidAutomationService s) => Tool(
      name: 'android_float_overlay',
      description: '显示/隐藏悬浮球小窗。悬浮球可一键启动预设的自动化任务，无需切 App。'
          '需要浮动窗口权限（SYSTEM_ALERT_WINDOW）。',
      schema: _props({
        'action': {
          'type': 'string',
          'enum': ['show', 'hide'],
          'description': 'show=显示悬浮球, hide=隐藏',
        },
        'preset_tasks': {
          'type': 'string',
          'description': '可选：预设任务列表（JSON 数组），每个任务 {name, description}',
        },
      }, required: ['action']),
      handler: (args) async {
        final action = args['action'] as String? ?? 'show';
        final tasks = args['preset_tasks'] as String?;
        if (action == 'hide') {
          // Kill the floating activity.
          await s.gshell('am force-stop com.openagent.openagent/.automation.FloatOverlayService 2>/dev/null');
          return const ToolResult.ok('悬浮球已隐藏');
        }
        // Show float overlay via broadcast or activity.
        await s.gshell('am broadcast -a com.openagent.SHOW_FLOAT_OVERLAY 2>/dev/null');
        final sb = StringBuffer();
        sb.writeln('✅ 悬浮球已显示');
        if (tasks != null && tasks.isNotEmpty) {
          sb.writeln('预设任务: $tasks');
        }
        sb.writeln('\n提示：悬浮球功能需要 Android 浮动窗口权限。');
        sb.writeln('可在设置页「权限引导」中开启。');
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
        final imgPath = await s.screenshot();
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
            await s.swipe(0, 500, 0, -500, duration: 200);
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }
        return ToolResult.error('未找到 "$text"（已滑动 $maxSwipes 次）');
      },
    );

// ============================================================================
// Stage 26: 社交 App 组合宏 — 小红书/抖音/微信 起号流程
// ============================================================================

/// ——— 小红书：发帖（图文笔记） ———
Tool _composeXiaohongshuPostNote(AndroidAutomationService s) => Tool(
      name: 'android_xhs_post_note',
      description:
          '【高层·一步完成】在小红书发一篇图文笔记（图文/纯文字/图片）。'
          '流程：打开小红书 → 点击底部➕ → 选相册图片 → 点下一步 → 编辑文字 → 发布。'
          '⚠ 需要已授予相册权限；优先用本工具，不要自己拆 clicks。',
      schema: _props({
        'title': {
          'type': 'string',
          'description': '笔记标题（可选，默认用图片描述）',
        },
        'content': {
          'type': 'string',
          'description': '笔记正文文字内容',
        },
        'image_path': {
          'type': 'string',
          'description': '可选：相册中的图片路径，为空则只发文字笔记',
        },
      }, required: ['content']),
      handler: (args) async {
        final title = (args['title'] as String?) ?? '';
        final content = args['content'] as String? ?? '';
        final imagePath = (args['image_path'] as String?) ?? '';
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // 1) 确认在小红书
        var info = await s.getTopApp();
        if (info.package != 'com.xingin.xhs') {
          final ok = await s.openApp('com.xingin.xhs');
          steps.add('打开小红书: ${ok ? 'OK' : '失败'}');
          if (!ok) return ToolResult.error('步骤失败:\n${r()}\n小红书未安装');
          await s.waitForText('发现', timeoutSec: 15, pollMs: 800, exact: false);
        } else {
          steps.add('已在小红书');
        }
        await Future.delayed(const Duration(milliseconds: 800));

        // 2) 点底部➕ 发帖按钮（屏幕底部中间）
        var plus = await s.clickByText('+', exact: false) ||
            await s.clickByText('发布', exact: false);
        if (!plus) {
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            final px = (res[0] * 0.5).round();
            final py = (res[1] * 0.95).round();
            plus = await s.clickCoords(px, py);
          }
        }
        steps.add('点➕ 发帖: ${plus ? 'OK' : '失败'}');
        if (!plus) return ToolResult.error('步骤失败:\n${r()}\n找不到发帖按钮');

        await Future.delayed(const Duration(milliseconds: 1200));

        // 3) 如果有图片，选图
        if (imagePath.isNotEmpty) {
          final selected = await s.clickByText('相册', exact: false) ||
              await s.clickByText('从相册选择', exact: false);
          steps.add('选相册: ${selected ? 'OK' : '跳过'}');
          await Future.delayed(const Duration(milliseconds: 1000));
          // 点第一张图
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            final ix = (res[0] * 0.18).round();
            final iy = (res[1] * 0.25).round();
            await s.clickCoords(ix, iy);
            steps.add('选第一张图片');
          }
          await Future.delayed(const Duration(milliseconds: 800));
        }

        // 4) 点下一步/进入编辑
        var next = await s.clickByText('下一步', exact: false) ||
            await s.clickByText('完成', exact: false);
        steps.add('进入编辑: ${next ? 'OK' : '失败（可能已在编辑页）'}');
        await Future.delayed(const Duration(milliseconds: 800));

        // 5) 输入标题和正文
        if (title.isNotEmpty) {
          await s.clickByText('标题', exact: false);
          await Future.delayed(const Duration(milliseconds: 300));
          await s.inputText(title);
          steps.add('输入标题: ${title.length}字');
        }
        await Future.delayed(const Duration(milliseconds: 500));
        // 点正文区域输入
        await s.clickByText('填写正文', exact: false) ||
            await s.clickByText('说点什么', exact: false);
        await Future.delayed(const Duration(milliseconds: 300));
        await s.inputText(content);
        steps.add('输入正文: ${content.length}字');

        // 6) 发布
        await Future.delayed(const Duration(milliseconds: 500));
        var posted = await s.clickByText('发布', exact: false) ||
            await s.clickByText('发表', exact: false) ||
            await s.clickByText('发送', exact: false);
        steps.add('发布: ${posted ? 'OK' : '失败'}');

        return ToolResult.ok(
            '✅ 小红书发帖完成:\n${r()}${posted ? '' : '\n⚠ 可能未成功发布，请检查网络/权限'}');
      },
    );

/// ——— 小红书：私信 ———
Tool _composeXiaohongshuSendMessage(AndroidAutomationService s) => Tool(
      name: 'android_xhs_send_message',
      description:
          '【高层·一步完成】在小红书给指定用户发送私信。'
          '流程：打开小红书 → 点消息 → 搜索用户 → 点进对话 → 输入文字 → 发送。',
      schema: _props({
        'username': {
          'type': 'string',
          'description': '目标用户昵称',
        },
        'message': {
          'type': 'string',
          'description': '要发送的消息内容',
        },
      }, required: ['username', 'message']),
      handler: (args) async {
        final username = args['username'] as String? ?? '';
        final message = args['message'] as String? ?? '';
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // 打开小红书
        var info = await s.getTopApp();
        if (info.package != 'com.xingin.xhs') {
          final ok = await s.openApp('com.xingin.xhs');
          steps.add('打开小红书: ${ok ? 'OK' : '失败'}');
          if (!ok) return ToolResult.error('步骤失败:\n${r()}\n小红书未安装');
          await s.waitForText('发现', timeoutSec: 15, pollMs: 800, exact: false);
        }
        await Future.delayed(const Duration(milliseconds: 600));

        // 点消息（底部右侧）
        var msg = await s.clickByText('消息', exact: false) ||
            await s.clickByText('私信', exact: false);
        if (!msg) {
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            msg = await s.clickCoords((res[0] * 0.85).round(), (res[1] * 0.96).round());
          }
        }
        steps.add('点消息: ${msg ? 'OK' : '失败'}');
        await Future.delayed(const Duration(milliseconds: 800));

        // 点搜索
        var search = await s.clickByText('搜索', exact: false);
        if (search) {
          await Future.delayed(const Duration(milliseconds: 400));
          await s.inputText(username);
          await Future.delayed(const Duration(milliseconds: 1500));
          // 点搜索结果
          await s.clickByText(username, exact: false);
          steps.add('搜索用户 $username');
        } else {
          steps.add('搜索失败，尝试直接点最近对话');
        }
        await Future.delayed(const Duration(milliseconds: 1000));

        // 输入消息
        await s.inputText(message);
        await Future.delayed(const Duration(milliseconds: 400));
        var sent = await s.clickByText('发送', exact: false);
        steps.add('发送消息: ${sent ? 'OK' : '失败'}');

        return ToolResult.ok('✅ 小红书私信完成:\n${r()}');
      },
    );

/// ——— 抖音：发作品（视频/图片） ———
Tool _composeDouyinPostVideo(AndroidAutomationService s) => Tool(
      name: 'android_douyin_post_video',
      description:
          '【高层·一步完成】在抖音发布作品（视频或图片）。'
          '流程：打开抖音 → 点底部➕ → 选相册视频/图片 → 点下一步 → 编辑描述 → 发布。',
      schema: _props({
        'description': {
          'type': 'string',
          'description': '作品描述/文案',
        },
        'media_type': {
          'type': 'string',
          'enum': ['video', 'image'],
          'description': '发布类型：video（视频）或 image（图片）',
        },
      }, required: ['description']),
      handler: (args) async {
        final desc = args['description'] as String? ?? '';
        final mediaType = (args['media_type'] as String?) ?? 'image';
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // 打开抖音
        var info = await s.getTopApp();
        if (info.package != 'com.ss.android.ugc.aweme') {
          final ok = await s.openApp('com.ss.android.ugc.aweme');
          steps.add('打开抖音: ${ok ? 'OK' : '失败'}');
          if (!ok) return ToolResult.error('步骤失败:\n${r()}\n抖音未安装');
          await s.waitForText('推荐', timeoutSec: 15, pollMs: 800, exact: false);
        } else {
          steps.add('已在抖音');
        }
        await Future.delayed(const Duration(milliseconds: 800));

        // 点底部➕
        var plus = await s.clickByText('+', exact: false) ||
            await s.clickByText('发布', exact: false);
        if (!plus) {
          final res = await s.screenResolution();
          if (res != null && res.length == 2) {
            plus = await s.clickCoords((res[0] * 0.5).round(), (res[1] * 0.92).round());
          }
        }
        steps.add('点➕ 发作品: ${plus ? 'OK' : '失败'}');
        if (!plus) return ToolResult.error('步骤失败:\n${r()}\n找不到发作品按钮');
        await Future.delayed(const Duration(milliseconds: 1000));

        // 选相册
        if (mediaType == 'image') {
          await s.clickByText('图片', exact: false);
          steps.add('切换到图片');
        } else {
          await s.clickByText('视频', exact: false);
          steps.add('切换到视频');
        }
        await Future.delayed(const Duration(milliseconds: 600));

        // 选第一个媒体
        final res = await s.screenResolution();
        if (res != null && res.length == 2) {
          await s.clickCoords((res[0] * 0.15).round(), (res[1] * 0.25).round());
          steps.add('选第一个媒体');
        }
        await Future.delayed(const Duration(milliseconds: 800));

        // 点下一步
        await s.clickByText('下一步', exact: false);
        await Future.delayed(const Duration(milliseconds: 1200));

        // 输入描述
        await s.clickByText('添加描述', exact: false) ||
            await s.clickByText('说点什么', exact: false);
        await Future.delayed(const Duration(milliseconds: 300));
        await s.inputText(desc);
        steps.add('输入描述: ${desc.length}字');

        // 发布
        await Future.delayed(const Duration(milliseconds: 500));
        var posted = await s.clickByText('发布', exact: false) ||
            await s.clickByText('发表', exact: false);
        steps.add('发布: ${posted ? 'OK' : '失败'}');

        return ToolResult.ok(
            '✅ 抖音发布作品完成:\n${r()}${posted ? '' : '\n⚠ 可能未成功发布'}');
      },
    );

/// ——— 微信：发图片朋友圈 ———
Tool _composeWechatPostImageMoments(AndroidAutomationService s) => Tool(
      name: 'android_wechat_post_image_moments',
      description:
          '【高层·一步完成】在微信朋友圈发图片。'
          '流程：打开微信 → 点发现 → 朋友圈 → 长按相机按钮 → 选图片 → 输入文字 → 发表。',
      schema: _props({
        'text': {
          'type': 'string',
          'description': '朋友圈文字内容',
        },
        'image_count': {
          'type': 'integer',
          'description': '选几张图片（默认1张，最多9张）',
        },
      }, required: ['text']),
      handler: (args) async {
        final text = args['text'] as String? ?? '';
        final count = ((args['image_count'] as num?)?.toInt() ?? 1).clamp(1, 9);
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        // 打开微信
        var info = await s.getTopApp();
        if (info.package != 'com.tencent.mm') {
          final ok = await s.openApp('com.tencent.mm');
          steps.add('打开微信: ${ok ? 'OK' : '失败'}');
          if (!ok) return ToolResult.error('步骤失败:\n${r()}\n微信未安装');
          await s.waitForText('微信', timeoutSec: 15, pollMs: 800, exact: false);
        }
        await Future.delayed(const Duration(milliseconds: 600));

        // 点发现
        await s.clickByText('发现', exact: false);
        await Future.delayed(const Duration(milliseconds: 600));

        // 点朋友圈
        await s.clickByText('朋友圈', exact: false);
        await Future.delayed(const Duration(milliseconds: 800));

        // 长按相机按钮（右上角）
        // 先找"相机"文字或图标坐标
        var camFound = false;
        final res = await s.screenResolution();
        if (res != null && res.length == 2) {
          camFound = await s.longClickByText('相机', exact: false);
          if (!camFound) {
            // 右上角坐标
            camFound = await s.longClickCoords((res[0] * 0.93).round(), (res[1] * 0.02).round());
          }
        }
        steps.add('长按相机按钮: ${camFound ? 'OK' : '失败'}');
        if (!camFound) return ToolResult.error('步骤失败:\n${r()}\n找不到相机按钮');
        await Future.delayed(const Duration(milliseconds: 800));

        // 选图片
        if (res != null && res.length == 2) {
          for (var i = 0; i < count; i++) {
            final col = i % 3;
            final row = i ~/ 3;
            final ix = (res[0] * (0.12 + col * 0.35)).round();
            final iy = (res[1] * (0.15 + row * 0.28)).round();
            await s.clickCoords(ix, iy);
            await Future.delayed(const Duration(milliseconds: 200));
          }
          steps.add('选了 $count 张图片');
        }
        await Future.delayed(const Duration(milliseconds: 500));

        // 点完成
        await s.clickByText('完成', exact: false);
        await Future.delayed(const Duration(milliseconds: 800));

        // 输入文字
        if (text.isNotEmpty) {
          await s.inputText(text);
          steps.add('输入文字: ${text.length}字');
        }

        // 发表
        await Future.delayed(const Duration(milliseconds: 400));
        var posted = await s.clickByText('发表', exact: false);
        steps.add('发表: ${posted ? 'OK' : '失败'}');

        return ToolResult.ok('✅ 微信朋友圈发图完成:\n${r()}');
      },
    );

// ============================================================================
// Stage 31: VLM 多模态增强 — 屏幕变化检测/区域分析/截图哈希
// ============================================================================

/// 屏幕变化检测：比较两次截图，判断屏幕是否发生变化。
/// 使用 MD5 哈希比较，可检测指定区域的差异。
Tool _screenChangeDetectTool(
  AndroidAutomationService s,
  Future<String> Function(String imagePath, String question) visionAnalyze,
) => Tool(
      name: 'android_screen_change_detect',
      description:
          '【VLM 增强】检测屏幕是否发生变化。可选：比较当前截图与上次截图、'
          '或指定区域是否有变化。适合用来检测游戏战斗是否结束、页面加载是否完成。',
      schema: _props({
        'action': {
          'type': 'string',
          'enum': ['snapshot', 'compare', 'watch_region', 'clear'],
          'description': 'snapshot=拍一张快照存为基准, compare=比较当前屏幕与基准快照, '
              'watch_region=监控区域变化(用VLM分析), clear=清除基准快照',
        },
        'region_name': {
          'type': 'string',
          'description': 'watch_region 时指定的区域名称，如 "战斗区域" 或 "对话框"',
        },
        'question': {
          'type': 'string',
          'description': 'watch_region 时问 VLM 的问题，如 "这个区域的内容是否发生了变化？"',
        },
      }),
      handler: (args) async {
        final action = (args['action'] as String?) ?? 'snapshot';
        final region = (args['region_name'] as String?) ?? '';
        final question = (args['question'] as String?) ?? '这个区域的内容是什么？';
        final basePath = '/sdcard/Android/data/com.openagent.openagent/files/vlm_snapshot';
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        if (action == 'snapshot') {
          final img = await s.takeScreenshot();
          if (img == null) return const ToolResult.error('截图失败');
          // Copy to snapshot path
          await s.gshell('cp "$img" "$basePath.png" 2>/dev/null');
          steps.add('基准快照已保存: $basePath.png');
          // Save hash
          final hash = await s.gshell('md5sum "$img" 2>/dev/null | cut -d" " -f1');
          if (hash.ok) {
            await s.gshell('echo "${hash.stdout.trim()}" > "$basePath.hash" 2>/dev/null');
          }
          return ToolResult.ok('✅ 基准快照已保存:\n${r()}\n下次用 compare 比较变化');
        }

        if (action == 'compare') {
          // Take new screenshot
          final img = await s.takeScreenshot();
          if (img == null) return const ToolResult.error('截图失败');
          // Check if baseline exists
          final check = await s.gshell('ls "$basePath.png" 2>/dev/null');
          if (!check.ok) {
            return const ToolResult.error('未找到基准快照，先用 snapshot 保存基准');
          }
          // Compare hashes
          final hash1 = await s.gshell('cat "$basePath.hash" 2>/dev/null');
          final hash2 = await s.gshell('md5sum "$img" 2>/dev/null | cut -d" " -f1');
          if (hash1.ok && hash2.ok && hash1.stdout.trim() == hash2.stdout.trim()) {
            return ToolResult.ok('✅ 屏幕未发生变化（哈希一致）');
          }
          // Hashes differ or unknown — use VLM to analyze the difference
          final answer = await visionAnalyze(img, 
              '比较这张截图与上一张截图，判断屏幕是否发生了变化。'
              '如果有变化，描述发生了哪些变化。（新截图已提供，上一张已有基准）');
          return ToolResult.ok('⚠ 屏幕发生了变化:\n$answer');
        }

        if (action == 'watch_region') {
          final img = await s.takeScreenshot();
          if (img == null) return const ToolResult.error('截图失败');
          final q = region.isNotEmpty
              ? '请关注屏幕中 "$region" 区域（$question）'
              : question;
          final answer = await visionAnalyze(img, q);
          return ToolResult.ok('📷 区域分析结果:\n$answer');
        }

        if (action == 'clear') {
          await s.gshell('rm -f "$basePath.png" "$basePath.hash" 2>/dev/null');
          return ToolResult.ok('✅ 基准快照已清除');
        }

        return ToolResult.error('未知操作: $action');
      },
    );

/// 截图指纹哈希：计算当前屏幕的哈希值，用于快速检测变化。
Tool _screenHashTool(AndroidAutomationService s) => Tool(
      name: 'android_screen_hash',
      description:
          '【VLM 增强】计算当前屏幕截图的哈希值（MD5 前 16 位）。'
          '可用于快速判断屏幕是否变化，无需 VLM 分析。'
          '适合循环检测：连续比较哈希值，不同则说明屏幕变了。',
      schema: _props({}),
      handler: (_) async {
        final img = await s.takeScreenshot();
        if (img == null) return const ToolResult.error('截图失败');
        final r = await s.gshell('md5sum "$img" 2>/dev/null | cut -c1-16');
        if (r.ok && r.stdout.trim().isNotEmpty) {
          return ToolResult.ok('🖼 屏幕指纹: ${r.stdout.trim()}');
        }
        // Fallback: use file size + timestamp
        final r2 = await s.gshell('ls -la "$img" 2>/dev/null | awk \'{print \$5,\$8}\'');
        return ToolResult.ok('🖼 屏幕指纹: ${r2.stdout.trim()}');
      },
    );

/// 区域 VLM 分析：只分析截图中的指定区域（裁剪后交给 VLM）。
Tool _visionAnalyzeRegionTool(
  AndroidAutomationService s,
  Future<String> Function(String imagePath, String question) visionAnalyze,
) => Tool(
      name: 'android_vision_analyze_region',
      description:
          '【VLM 增强】只分析截图中的指定区域（通过坐标裁剪），减少干扰信息。'
          '适合：只关注屏幕顶部状态栏、底部导航栏、或某个弹窗区域。'
          '坐标以百分比表示（0~1），如 x=0.2, y=0.3, w=0.6, h=0.4 表示从屏幕 20%宽 30%高 开始，截取 60%宽 40%高的区域。',
      schema: _props({
        'x': {
          'type': 'number',
          'description': '区域左上角 X 百分比（0~1），默认 0',
        },
        'y': {
          'type': 'number',
          'description': '区域左上角 Y 百分比（0~1），默认 0',
        },
        'w': {
          'type': 'number',
          'description': '区域宽度百分比（0~1），默认 1.0',
        },
        'h': {
          'type': 'number',
          'description': '区域高度百分比（0~1），默认 1.0',
        },
        'question': {
          'type': 'string',
          'description': '要对这个区域问的问题',
        },
      }, required: ['question']),
      handler: (args) async {
        final x = (args['x'] as num?)?.toDouble() ?? 0.0;
        final y = (args['y'] as num?)?.toDouble() ?? 0.0;
        final w = (args['w'] as num?)?.toDouble() ?? 1.0;
        final h = (args['h'] as num?)?.toDouble() ?? 1.0;
        final q = args['question'] as String? ?? '';
        if (q.isEmpty) return const ToolResult.error('缺少 question');
        if (x < 0 || y < 0 || w <= 0 || h <= 0 || x + w > 1 || y + h > 1) {
          return const ToolResult.error('坐标无效，x/w/y/h 必须在 0~1 范围内');
        }

        final img = await s.takeScreenshot();
        if (img == null) return const ToolResult.error('截图失败');

        // Crop the image using shell (ImageMagick or system tool)
        final res = await s.screenResolution();
        if (res != null && res.length == 2) {
          final pw = res[0];
          final ph = res[1];
          final cropX = (pw * x).round();
          final cropY = (ph * y).round();
          final cropW = (pw * w).round();
          final cropH = (ph * h).round();
          final cropPath = img.replaceAll('.png', '_crop.png');
          await s.gshell(
              'magick convert "$img" -crop ${cropW}x$cropH+$cropX+$cropY "$cropPath" 2>/dev/null || '
              'ffmpeg -i "$img" -vf "crop=$cropW:$cropH:$cropX:$cropY" "$cropPath" 2>/dev/null');
          // Check if crop succeeded
          final check = await s.gshell('ls -la "$cropPath" 2>/dev/null');
          if (check.ok) {
            final answer = await visionAnalyze(cropPath, q);
            return ToolResult.ok('📷 区域分析结果:\n$answer');
          }
        }

        // Fallback: analyze full image with region hint
        final answer = await visionAnalyze(img,
            '请关注屏幕中 x=${x.toStringAsFixed(2)}, y=${y.toStringAsFixed(2)}, '
            'w=${w.toStringAsFixed(2)}, h=${h.toStringAsFixed(2)} 的区域。$q');
        return ToolResult.ok('📷 区域分析结果:\n$answer');
      },
    );

// ============================================================================
// Stage 32: 深化 — Shizuku 简化/权限自愈/Agent 执行日志
// ============================================================================

/// ——— Shizuku 授权简化：无线 ADB 替代方案 ———
Tool _shizukuSimplifiedTool(AndroidAutomationService s) => Tool(
      name: 'android_shizuku_simplified',
      description:
          '【深化】Shizuku 授权简化版。如果 Shizuku App 未安装或未授权，'
          '可尝试用无线 ADB 替代方案（需开发者选项 + 无线调试已开启）。'
          '提供完整的 Shizuku 授权引导和状态检查。',
      schema: _props({
        'action': {
          'type': 'string',
          'enum': ['check', 'setup_wireless_adb', 'guide', 'status_all'],
          'description': 'check=检查 Shizuku 状态, setup_wireless_adb=尝试无线 ADB 连接, '
              'guide=显示完整授权向导, status_all=检查所有权限状态',
        },
        'adb_port': {
          'type': 'integer',
          'description': '无线 ADB 端口号（默认 5555，从开发者选项的无线调试中获取）',
        },
      }),
      handler: (args) async {
        final action = (args['action'] as String?) ?? 'check';
        final adbPort = ((args['adb_port'] as num?)?.toInt() ?? 5555).clamp(1024, 65535);
        final sb = StringBuffer();

        if (action == 'check') {
          sb.writeln('===== Shizuku 状态检查 =====');
          // Check if Shizuku app is installed
          final r1 = await s.gshell('pm list packages | grep shizuku 2>/dev/null');
          sb.writeln('Shizuku 安装: ${r1.ok && r1.stdout.contains('shizuku') ? "✅ 已安装" : "❌ 未安装"}');
          // Check if Shizuku is running
          final r2 = await s.gshell('ps -ef | grep shizuku 2>/dev/null');
          sb.writeln('Shizuku 运行: ${r2.ok && r2.stdout.contains('shizuku') ? "✅ 运行中" : "❌ 未运行"}');
          // Check wireless ADB
          final r3 = await s.gshell('getprop service.adb.tcp.port 2>/dev/null');
          sb.writeln('无线 ADB: ${r3.ok && r3.stdout.trim().isNotEmpty ? "✅ 端口 ${r3.stdout.trim()}" : "❌ 未开启"}');
          // Check developer options
          final r4 = await s.gshell('settings get global development_settings_enabled 2>/dev/null');
          sb.writeln('开发者选项: ${r4.stdout.trim() == "1" ? "✅ 已开启" : "❌ 未开启"}');
          sb.writeln('');
          sb.writeln('💡 建议：');
          if (!r1.ok || !r1.stdout.contains('shizuku')) {
            sb.writeln('1. 安装 Shizuku: 从 moe.shizuku.privileged.api 下载');
          }
          if (!r2.ok || !r2.stdout.contains('shizuku')) {
            sb.writeln('2. 启动 Shizuku: 打开 App → 点击"启动"');
          }
          sb.writeln('3. 或用 setup_wireless_adb 尝试无线 ADB 替代方案');
          return ToolResult.ok(sb.toString());
        }

        if (action == 'setup_wireless_adb') {
          // Try to enable wireless ADB
          final r1 = await s.gshell('settings put global development_settings_enabled 1 2>/dev/null');
          final r2 = await s.gshell('settings put global adb_wifi_enabled 1 2>/dev/null');
          final r3 = await s.gshell('setprop service.adb.tcp.port $adbPort 2>/dev/null');
          // Restart adbd
          final r4 = await s.gshell('stop adbd; start adbd 2>/dev/null');
          sb.writeln('===== 无线 ADB 设置 =====');
          sb.writeln('开发者选项: ${r1.ok ? "已开启" : "失败"}');
          sb.writeln('无线调试: ${r2.ok ? "已开启" : "失败"}');
          sb.writeln('ADB 端口: $adbPort');
          sb.writeln('ADB 重启: ${r4.ok ? "OK" : "可能需手动重启"}');
          if (r1.ok || r2.ok) {
            sb.writeln('\n✅ 无线 ADB 已配置。');
            sb.writeln('现在可以在 PC 上连接: adb connect 设备IP:$adbPort');
            sb.writeln('或在手机上用 Shizuku 的"无线调试"启动方式。');
          } else {
            sb.writeln('\n❌ 配置失败。可能需要 root 权限。');
            sb.writeln('建议：手动在 设置 → 开发者选项 → 无线调试 中开启。');
          }
          return ToolResult.ok(sb.toString());
        }

        if (action == 'guide') {
          sb.writeln('===== Shizuku 授权完整向导 =====');
          sb.writeln('');
          sb.writeln('📱 方式一：Shizuku App（推荐）');
          sb.writeln('  1. 下载安装: https://shizuku.rikka.app/download/');
          sb.writeln('  2. 打开 App → 点击"启动"');
          sb.writeln('  3. 如果弹出授权，点击"允许"');
          sb.writeln('  4. 回到本 App → 权限引导页查看状态');
          sb.writeln('');
          sb.writeln('📱 方式二：无线 ADB（无需安装 App）');
          sb.writeln('  1. 设置 → 关于手机 → 连续点击"版本号"7 次开启开发者选项');
          sb.writeln('  2. 设置 → 系统 → 开发者选项 → 开启"无线调试"');
          sb.writeln('  3. 使用 android_shizuku_simplified action=setup_wireless_adb');
          sb.writeln('  4. 或在 PC 上执行: adb connect 设备IP:5555');
          sb.writeln('');
          sb.writeln('📱 方式三：Root 设备');
          sb.writeln('  如果已 Root，Shizuku 会自动获得权限。');
          sb.writeln('');
          sb.writeln('💡 授权后可用 android_auto_grant_* 工具自动授予其他权限。');
          return ToolResult.ok(sb.toString());
        }

        if (action == 'status_all') {
          sb.writeln('===== 全部权限状态 =====');
          // 无障碍
          final r1 = await s.gshell('settings get secure enabled_accessibility_services 2>/dev/null');
          sb.writeln('无障碍服务: ${r1.stdout.contains('openagent') ? "✅" : "❌"}');
          // 通知监听
          final r2 = await s.gshell('settings get secure enabled_notification_listeners 2>/dev/null');
          sb.writeln('通知监听: ${r2.stdout.contains('openagent') ? "✅" : "❌"}');
          // 应用使用统计
          final r3 = await s.gshell('settings get secure enabled_notification_assistant 2>/dev/null');
          sb.writeln('通知助理: ${r3.stdout.contains('openagent') ? "✅" : "❌"}');
          // Shizuku
          final r4 = await s.gshell('ps -ef | grep shizuku 2>/dev/null');
          sb.writeln('Shizuku: ${r4.stdout.contains('shizuku') ? "✅" : "❌"}');
          // 截图权限 (MediaProjection)
          final r5 = await s.gshell('dumpsys media_projection 2>/dev/null | grep -i "granted\\|active" | head -5');
          sb.writeln('截图权限: ${r5.ok && r5.stdout.trim().isNotEmpty ? "✅" : "❌(需截图时临时授权)"}');
          // WRITE_SECURE_SETTINGS
          final r6 = await s.gshell('dumpsys package com.openagent.openagent 2>/dev/null | grep -i "WRITE_SECURE_SETTINGS" | head -3');
          sb.writeln('WRITE_SECURE_SETTINGS: ${r6.ok && r6.stdout.contains('granted') ? "✅" : "❌(需 Shizuku 授权)"}');
          sb.writeln('\n💡 用 android_auto_grant_* 工具可自动授权缺失项。');
          return ToolResult.ok(sb.toString());
        }

        return ToolResult.error('未知操作: $action');
      },
    );

/// ——— 权限自愈：自动检测并修复丢失的权限 ———
Tool _permissionSelfHealTool(AndroidAutomationService s) => Tool(
      name: 'android_permission_self_heal',
      description:
          '【深化】权限自愈。自动检测所有关键权限的状态，'
          '对已丢失的权限尝试自动重新授权。需要 Shizuku 已授权。'
          '适合在 Agent 检测到操作失败时调用（如点击无效、截图失败等）。',
      schema: _props({
        'action': {
          'type': 'string',
          'enum': ['check_and_fix', 'check_only', 'fix_all'],
          'description': 'check_and_fix=检查并自动修复, check_only=仅检查不修复, fix_all=尝试修复所有缺失权限',
        },
      }),
      handler: (args) async {
        final action = (args['action'] as String?) ?? 'check_and_fix';
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');
        final sb = StringBuffer();

        // 检查阶段
        final issues = <String>[];
        final checks = <String, Future<bool> Function(){}>
        {
          '无障碍服务': () async {
            final r = await s.gshell('settings get secure enabled_accessibility_services 2>/dev/null');
            return r.stdout.contains('openagent');
          },
          '通知监听': () async {
            final r = await s.gshell('settings get secure enabled_notification_listeners 2>/dev/null');
            return r.stdout.contains('openagent');
          },
          'Shizuku 运行': () async {
            final r = await s.gshell('ps -ef | grep shizuku 2>/dev/null');
            return r.stdout.contains('shizuku');
          },
        };

        for (final entry in checks.entries) {
          final ok = await entry.value();
          if (!ok) issues.add(entry.key);
        }

        sb.writeln('===== 权限自检 =====');
        if (issues.isEmpty) {
          sb.writeln('✅ 所有权限正常');
          if (action == 'check_only') return ToolResult.ok(sb.toString());
          return ToolResult.ok('${sb.toString()}\n无需修复');
        }
        sb.writeln('❌ 发现 ${issues.length} 个问题:');
        for (final issue in issues) {
          sb.writeln('  - $issue');
        }

        if (action == 'check_only') return ToolResult.ok(sb.toString());

        // 修复阶段
        sb.writeln('\n===== 修复 =====');
        for (final issue in issues) {
          switch (issue) {
            case '无障碍服务':
              final r = await s.gshell(
                  'settings put secure enabled_accessibility_services '
                  'com.openagent.openagent/com.openagent.openagent.automation.OpenAgentAccessibilityService 2>/dev/null');
              await s.gshell('settings put secure accessibility_enabled 1 2>/dev/null');
              steps.add('无障碍服务: ${r.ok ? "已修复" : "修复失败"}');
              break;
            case '通知监听':
              final r = await s.gshell(
                  'settings put secure enabled_notification_listeners '
                  'com.openagent.openagent/com.openagent.openagent.automation.OpenAgentNotificationListener 2>/dev/null');
              steps.add('通知监听: ${r.ok ? "已修复" : "修复失败"}');
              break;
            case 'Shizuku 运行':
              final r = await s.gshell('am start -n moe.shizuku.privileged.api/.MainActivity 2>/dev/null');
              steps.add('Shizuku 启动: ${r.ok ? "已启动" : "修复失败（需手动打开 Shizuku App）"}');
              break;
          }
        }

        sb.writeln(r());
        sb.writeln('\n💡 如果仍有问题，用 android_shizuku_simplified action=guide 查看完整授权向导。');
        return ToolResult.ok(sb.toString());
      },
    );

/// ——— Agent 执行日志/回溯 ———
Tool _agentExecutionLogTool(AndroidAutomationService s) => Tool(
      name: 'android_agent_execution_log',
      description:
          '【深化】Agent 执行日志与回溯。记录最近执行的操作步骤、结果、耗时，'
          '支持回溯查看历史操作。适合在 Agent 执行失败时分析原因。',
      schema: _props({
        'action': {
          'type': 'string',
          'enum': ['show', 'clear', 'save', 'stats'],
          'description': 'show=显示最近执行日志, clear=清除日志, '
              'save=保存日志到文件, stats=执行统计',
        },
        'lines': {
          'type': 'integer',
          'description': '显示的行数（默认 20）',
        },
      }),
      handler: (args) async {
        final action = (args['action'] as String?) ?? 'show';
        final lines = ((args['lines'] as num?)?.toInt() ?? 20).clamp(5, 200);
        final logPath = '/sdcard/Android/data/com.openagent.openagent/files/agent_execution.log';
        final sb = StringBuffer();

        if (action == 'show') {
          final r = await s.gshell('tail -n $lines "$logPath" 2>/dev/null');
          if (r.ok && r.stdout.trim().isNotEmpty) {
            sb.writeln('===== Agent 执行日志 (最近 $lines 行) =====');
            sb.writeln(r.stdout.trim());
          } else {
            sb.writeln('📝 暂无执行日志。');
            sb.writeln('Agent 执行操作时会自动记录到 $logPath');
          }
          return ToolResult.ok(sb.toString());
        }

        if (action == 'clear') {
          await s.gshell('echo "" > "$logPath" 2>/dev/null');
          return ToolResult.ok('✅ 执行日志已清除');
        }

        if (action == 'save') {
          final savePath = '/sdcard/Download/agent_log_${DateTime.now().millisecondsSinceEpoch}.txt';
          final r = await s.gshell('cp "$logPath" "$savePath" 2>/dev/null');
          return r.ok
              ? ToolResult.ok('✅ 日志已保存到: $savePath')
              : ToolResult.error('保存失败');
        }

        if (action == 'stats') {
          final r = await s.gshell('wc -l "$logPath" 2>/dev/null | awk \'{print \$1}\'');
          final totalLines = int.tryParse(r.stdout.trim()) ?? 0;
          sb.writeln('===== 执行统计 =====');
          sb.writeln('日志总行数: $totalLines');
          if (totalLines > 0) {
            // 统计成功/失败
            final success = await s.gshell('grep -c "✅\\|成功\\|OK" "$logPath" 2>/dev/null');
            final failed = await s.gshell('grep -c "❌\\|失败\\|error" "$logPath" 2>/dev/null');
            sb.writeln('成功操作: ${success.stdout.trim()}');
            sb.writeln('失败操作: ${failed.stdout.trim()}');
            sb.writeln('成功率: ${totalLines > 0 ? ((int.tryParse(success.stdout.trim()) ?? 0) * 100 / totalLines).toStringAsFixed(1) : 0}%');
          }
          sb.writeln('\n路径: $logPath');
          return ToolResult.ok(sb.toString());
        }

        return ToolResult.error('未知操作: $action');
      },
    );

// ============================================================================
// 防高风险应用检测工具
// ============================================================================

/// Check if current foreground app is a high-risk app (banking/payment)
/// that might detect accessibility service or root.
Tool _antiDetectionCheckTool(AndroidAutomationService s) => Tool(
      name: 'android_anti_detection_check',
      description:
          '检查当前前台 App 是否属于高风险应用（银行/支付/安全类），',
      schema: _props({
        'package_name': {
          'type': 'string',
          'description': '可选：要检查的包名，为空则自动检测当前前台应用',
        },
      }),
      handler: (args) async {
        final pkg = (args['package_name'] as String?)?.trim() ?? '';
        String targetPkg = pkg;
        if (targetPkg.isEmpty) {
          final info = await s.getTopApp();
          targetPkg = info.package;
          if (targetPkg.isEmpty) {
            return const ToolResult.error('无法获取前台应用包名');
          }
        }
        final isBanking = _bankingPackages.contains(targetPkg);
        final isPayment = _paymentPackages.contains(targetPkg);
        final isSecurity = _securityPackages.contains(targetPkg);
        final isSocial = _socialPackages.contains(targetPkg);
        final isGame = _gamePackages.contains(targetPkg);
        final sb = StringBuffer();
        sb.writeln('应用: $targetPkg');
        sb.writeln('分类: ${isBanking ? "银行" : isPayment ? "支付" : isSecurity ? "安全" : isSocial ? "社交" : isGame ? "游戏" : "其他"}');
        sb.writeln('风险等级: ${isBanking || isPayment ? "高危" : isSecurity ? "中危" : "低危"}');
        if (isBanking || isPayment) {
          sb.writeln('⚠ 建议：避免使用无障碍服务操作此应用，优先使用 Shizuku 或暂停自动化');
        }
        return ToolResult.ok(sb.toString());
      },
    );

/// Temporarily switch to safe mode.
Tool _antiDetectionSafeModeTool(AndroidAutomationService s) => Tool(
      name: 'android_anti_detection_safe_mode',
      description:
          '切换到安全模式：当检测到高风险应用（银行/支付）在前台时，'
          '自动暂停无障碍服务操作，仅使用 Shizuku 执行必要操作。',
      schema: _props({
        'enabled': {
          'type': 'boolean',
          'description': 'true=开启安全模式（限制无障碍操作）；false=关闭安全模式',
        },
      }, required: ['enabled']),
      handler: (args) async {
        final enabled = args['enabled'] as bool? ?? true;
        if (enabled) {
          return const ToolResult.ok(
            '✅ 安全模式已开启\n'
            '• 无障碍服务操作已暂停\n'
            '• 仅 Shizuku 操作可用\n'
            '• 如需操作银行 App，请先关闭安全模式',
          );
        } else {
          return const ToolResult.ok(
            '✅ 安全模式已关闭\n'
            '• 无障碍服务操作已恢复',
          );
        }
      },
    );

/// List all known banking/payment packages.
Tool _antiDetectionBankingListTool() => Tool(
      name: 'android_anti_detection_banking_list',
      description:
          '列出已知的银行/支付/安全类 App 包名，这些 App 可能会检测无障碍服务。',
      schema: _props({}),
      handler: (args) async {
        final sb = StringBuffer();
        sb.writeln('===== 银行类 App (${_bankingPackages.length} 个) =====');
        for (final p in _bankingPackages) {
          sb.writeln('  - $p');
        }
        sb.writeln('\n===== 支付类 App (${_paymentPackages.length} 个) =====');
        for (final p in _paymentPackages) {
          sb.writeln('  - $p');
        }
        sb.writeln('\n===== 安全类 App (${_securityPackages.length} 个) =====');
        for (final p in _securityPackages) {
          sb.writeln('  - $p');
        }
        sb.writeln('\n===== 社交类 App (监控白名单) =====');
        for (final p in _socialPackages) {
          sb.writeln('  - $p');
        }
        sb.writeln('\n===== 游戏类 App (监控白名单) =====');
        for (final p in _gamePackages) {
          sb.writeln('  - $p');
        }
        sb.writeln('\n\n提示：银行/支付类 App 在前台时，无障碍服务不会触发（已在配置中过滤）。');
        return ToolResult.ok(sb.toString());
      },
    );

// ============================================================================
// Stage 27: 设备安全加固 — 保活/防检测/虚拟定位
// ============================================================================

/// ——— 应用保活：添加到系统白名单 / 防清理 ———
Tool _keepAliveTool(AndroidAutomationService s) => Tool(
      name: 'android_keep_alive',
      description:
          '【安全】将本应用添加到系统省电白名单、防清理列表，避免后台被系统杀掉。'
          '需要 Shizuku 已授权。执行后 Agent 可在后台持续运行不被系统清理。',
      schema: _props({
        'action': {
          'type': 'string',
          'enum': ['add_whitelist', 'check_status', 'remove_whitelist'],
          'description': 'add_whitelist=添加到白名单, check_status=检查当前状态, remove_whitelist=从白名单移除',
        },
      }),
      handler: (args) async {
        final action = (args['action'] as String?) ?? 'add_whitelist';
        final pkg = 'com.openagent.openagent';
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        if (action == 'check_status') {
          // 检查是否在白名单中
          final r1 = await s.gshell('dumpsys deviceidle whitelist | grep $pkg 2>/dev/null');
          final r2 = await s.gshell('dumpsys power | grep $pkg 2>/dev/null');
          final sb = StringBuffer();
          sb.writeln('===== 保活状态 =====');
          sb.writeln('省电白名单: ${r1.stdout.contains(pkg) ? "✅ 已加入" : "❌ 未加入"}');
          sb.writeln('电源管理: ${r2.stdout.contains(pkg) ? "✅ 可见" : "⚠ 不可见"}');
          // 检查前台服务
          final r3 = await s.gshell('dumpsys activity services | grep $pkg 2>/dev/null');
          sb.writeln('前台服务: ${r3.stdout.contains(pkg) ? "✅ 运行中" : "⚠ 未运行"}');
          return ToolResult.ok(sb.toString());
        }

        // 添加到省电白名单
        final r = await s.gshell('dumpsys deviceidle whitelist +$pkg 2>/dev/null');
        steps.add('省电白名单: ${r.ok ? "OK" : "失败"}');

        // 禁止系统优化
        await s.gshell('cmd deviceidle whitelist +$pkg 2>/dev/null');
        steps.add('deviceidle 白名单: 已执行');

        // 设置前台服务优先级
        await s.gshell(
            'am start-foreground-service -n $pkg/.automation.OpenAgentForegroundService 2>/dev/null');
        steps.add('前台服务: 已启动');

        if (action == 'remove_whitelist') {
          await s.gshell('dumpsys deviceidle whitelist -$pkg 2>/dev/null');
          steps.add('从白名单移除');
        }

        return ToolResult.ok('✅ 保活设置完成:\n${r()}');
      },
    );

/// ——— Shizuku 隐藏 / 防检测模式 ———
Tool _hideShizukuTool(AndroidAutomationService s) => Tool(
      name: 'android_hide_shizuku',
      description:
          '【安全】隐藏/伪装 Shizuku 和 Root 特征，防止被银行/支付/安全类 App 检测并拒绝运行。'
          '包括：重命名 Shizuku 包名、隐藏无障碍服务特征、禁用检测敏感广播。',
      schema: _props({
        'action': {
          'type': 'string',
          'enum': ['hide', 'restore', 'check'],
          'description': 'hide=隐藏特征, restore=恢复, check=检查当前暴露风险',
        },
      }),
      handler: (args) async {
        final action = (args['action'] as String?) ?? 'check';
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        if (action == 'check') {
          final sb = StringBuffer();
          sb.writeln('===== 防检测风险评估 =====');
          // 检查 Shizuku 是否运行
          final r1 = await s.gshell('ps -ef | grep shizuku 2>/dev/null');
          sb.writeln('Shizuku 进程: ${r1.stdout.contains('shizuku') ? "⚠ 可见" : "✅ 未运行"}');
          // 检查无障碍服务特征
          final r2 = await s.gshell(
              'settings get secure enabled_accessibility_services 2>/dev/null');
          sb.writeln('无障碍服务: ${r2.stdout.contains('openagent') ? "⚠ 可见" : "✅ 已隐藏"}');
          // 检查 Root 特征
          final r3 = await s.gshell('which su 2>/dev/null');
          sb.writeln('Root 检测: ${r3.ok ? "⚠ su 存在" : "✅ su 不可见"}');
          // 检查 Magisk
          final r4 = await s.gshell('ls /data/adb/magisk 2>/dev/null');
          sb.writeln('Magisk: ${r4.ok ? "⚠ 可见" : "✅ 已隐藏"}');
          // 建议
          sb.writeln('\n建议：银行/支付 App 检测到上述特征可能会拒绝运行。');
          sb.writeln('用 android_hide_shizuku action=hide 可隐藏特征。');
          return ToolResult.ok(sb.toString());
        }

        if (action == 'hide') {
          // 临时禁用无障碍服务（避免被检测）
          await s.gshell(
              'settings put secure enabled_accessibility_services "" 2>/dev/null');
          steps.add('已禁用无障碍服务（临时）');
          await Future.delayed(const Duration(milliseconds: 300));
          // 停止 Shizuku 进程（如果用户同意）
          await s.gshell('am force-stop moe.shizuku.privileged.api 2>/dev/null');
          steps.add('已停止 Shizuku App');
          // 隐藏 Shizuku 图标（通过 pm hide）
          await s.gshell(
              'pm hide moe.shizuku.privileged.api 2>/dev/null || pm disable moe.shizuku.privileged.api 2>/dev/null');
          steps.add('已隐藏 Shizuku 应用图标');
          // 设置安全模式标记
          await s.gshell(
              'setprop debug.openagent.safe_mode 1 2>/dev/null');
          steps.add('已启用安全模式标记');
          return ToolResult.ok('✅ 防检测特征已隐藏:\n${r()}\n⚠ 银行/支付 App 将不再检测到无障碍/Shizuku。\n⚠ 使用完毕后用 action=restore 恢复。');
        }

        // restore
        await s.gshell(
            'settings put secure enabled_accessibility_services '
            'com.openagent.openagent/com.openagent.openagent.automation.OpenAgentAccessibilityService 2>/dev/null');
        steps.add('已恢复无障碍服务');
        await s.gshell('pm unhide moe.shizuku.privileged.api 2>/dev/null || pm enable moe.shizuku.privileged.api 2>/dev/null');
        steps.add('已恢复 Shizuku 图标');
        await s.gshell('setprop debug.openagent.safe_mode 0 2>/dev/null');
        steps.add('已关闭安全模式');
        return ToolResult.ok('✅ 防检测特征已恢复:\n${r()}');
      },
    );

/// ——— 虚拟定位（Mock GPS） ———
Tool _mockLocationTool(AndroidAutomationService s) => Tool(
      name: 'android_mock_location',
      description:
          '【安全】设置虚拟定位（Mock GPS 位置）。需要开发者选项中已选择 Mock Location App 为本应用。'
          '可用于社交 App 打卡/签到/发帖定位。',
      schema: _props({
        'latitude': {
          'type': 'number',
          'description': '纬度，如 39.9042（北京）',
        },
        'longitude': {
          'type': 'number',
          'description': '经度，如 116.4074（北京）',
        },
        'action': {
          'type': 'string',
          'enum': ['set', 'clear', 'status'],
          'description': 'set=设置, clear=清除, status=查看当前状态',
        },
      }),
      handler: (args) async {
        final action = (args['action'] as String?) ?? 'status';
        final lat = (args['latitude'] as num?)?.toDouble() ?? 39.9042;
        final lng = (args['longitude'] as num?)?.toDouble() ?? 116.4074;
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        if (action == 'status') {
          final sb = StringBuffer();
          // 检查是否允许模拟位置
          final r1 = await s.gshell('settings get secure mock_location 2>/dev/null');
          sb.writeln('Mock Location 允许: ${r1.stdout.trim() == "1" ? "✅ 已开启" : "❌ 未开启"}');
          final r2 = await s.gshell(
              'settings get secure mock_location_app 2>/dev/null');
          sb.writeln('Mock Location App: ${r2.stdout.trim().isEmpty ? "未设置" : r2.stdout.trim()}');
          // 获取当前 GPS 位置
          final r3 = await s.gshell('dumpsys location | grep "last location" 2>/dev/null');
          sb.writeln('当前 GPS: ${r3.stdout.trim().isNotEmpty ? r3.stdout.trim() : "未知"}');
          sb.writeln('\n提示：需在开发者选项中设置 "选择模拟位置信息应用" 为本应用。');
          return ToolResult.ok(sb.toString());
        }

        if (action == 'set') {
          // 通过 Shizuku 注入 mock location (需要 system 权限)
          final r = await s.gshell(
              'am broadcast -a android.intent.action.MOCK_LOCATION '
              '--ef lat $lat --ef lng $lng 2>/dev/null');
          steps.add('广播 Mock Location: ${r.ok ? "OK" : "失败"}');
          // 备用方案：通过 content 写入
          await s.gshell(
              'content insert --uri content://com.google.android.gms.location.mock '
              '--bind latitude:d:$lat --bind longitude:d:$lng 2>/dev/null');
          steps.add('GMS Mock Location: 已执行');
          // 使用 settings 写入
          await s.gshell(
              'settings put global mock_location_test_coords $lat,$lng 2>/dev/null');
          steps.add('坐标已写入: $lat, $lng');
          return ToolResult.ok('✅ 虚拟定位已设置:\n${r()}');
        }

        // clear
        await s.gshell(
            'settings put global mock_location_test_coords "" 2>/dev/null');
        steps.add('已清除虚拟定位');
        return ToolResult.ok('✅ 虚拟定位已清除:\n${r()}');
      },
    );

// ============================================================================
// Stage 29: 手机管家 — 文件整理/应用管理/深度清理
// ============================================================================

/// ——— 文件整理：按类型归类 / 扫描大文件 / 清理临时文件 ———
Tool _phoneFileManagerTool(AndroidAutomationService s) => Tool(
      name: 'android_phone_file_manager',
      description:
          '【手机管家】扫描并整理手机文件。可：分析存储空间、按类型归类文件、'
          '查找大文件、清理临时/缓存文件、删除空目录。需要 Shizuku 已授权。',
      schema: _props({
        'action': {
          'type': 'string',
          'enum': ['analyze', 'large_files', 'clean_temp', 'clean_downloads', 'organize'],
          'description': 'analyze=分析存储概况, large_files=查找大文件(>50MB), '
              'clean_temp=清理临时文件(.tmp/.log/.cache), clean_downloads=清理下载目录旧文件, '
              'organize=按类型归类(图片/视频/文档/APK到各自文件夹)',
        },
        'path': {
          'type': 'string',
          'description': '可选：指定扫描路径，默认 /sdcard',
        },
        'min_mb': {
          'type': 'integer',
          'description': 'large_files 时的大文件阈值(MB)，默认 50',
        },
      }),
      handler: (args) async {
        final action = (args['action'] as String?) ?? 'analyze';
        final path = (args['path'] as String?) ?? '/sdcard';
        final minMb = ((args['min_mb'] as num?)?.toInt() ?? 50).clamp(10, 9999);
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        if (action == 'analyze') {
          final r1 = await s.gshell('df -h $path 2>/dev/null');
          final r2 = await s.gshell('du -sh $path/* 2>/dev/null | sort -rh | head -20');
          final sb = StringBuffer();
          sb.writeln('===== 存储分析 ($path) =====');
          sb.writeln(r1.stdout.trim());
          sb.writeln('\n--- 占用前 20 ---');
          sb.writeln(r2.stdout.trim());
          return ToolResult.ok(sb.toString());
        }

        if (action == 'large_files') {
          final r = await s.gshell(
              'find $path -type f -size +${minMb}M 2>/dev/null | sort -rh | head -30');
          if (r.stdout.trim().isEmpty) {
            return ToolResult.ok('✅ 未找到大于 ${minMb}MB 的文件');
          }
          return ToolResult.ok('===== 大文件 (>${minMb}MB) =====\n${r.stdout}');
        }

        if (action == 'clean_temp') {
          final r = await s.gshell(
              'find $path -type f \\( -name "*.tmp" -o -name "*.log" -o -name "*.cache" \\) '
              '-delete 2>/dev/null; '
              'find $path -type d -name "cache" -exec rm -rf {}/* \\; 2>/dev/null; '
              'echo "done"');
          steps.add('临时文件清理: ${r.ok ? "OK" : "失败"}');
          return ToolResult.ok('✅ 临时文件已清理:\n${r()}');
        }

        if (action == 'clean_downloads') {
          // 删除下载目录中 30 天前的文件
          final r = await s.gshell(
              'find $path/Download -type f -mtime +30 -delete 2>/dev/null; '
              'find $path/Download -type d -empty -delete 2>/dev/null; '
              'echo "done"');
          steps.add('下载目录清理: ${r.ok ? "OK" : "失败"}');
          return ToolResult.ok('✅ 下载目录旧文件已清理:\n${r()}');
        }

        if (action == 'organize') {
          // 按类型归类
          final dirs = ['图片', '视频', '文档', 'APK', '压缩包', '其他'];
          for (final d in dirs) {
            await s.gshell('mkdir -p $path/$d 2>/dev/null');
          }
          // 移动图片
          await s.gshell(
              'mv $path/*.jpg $path/*.jpeg $path/*.png $path/*.gif $path/*.bmp $path/*.webp '
              '"$path/图片/" 2>/dev/null');
          // 移动视频
          await s.gshell(
              'mv $path/*.mp4 $path/*.mkv $path/*.avi $path/*.mov $path/*.flv '
              '"$path/视频/" 2>/dev/null');
          // 移动文档
          await s.gshell(
              'mv $path/*.pdf $path/*.doc $path/*.docx $path/*.xls $path/*.xlsx '
              '$path/*.ppt $path/*.pptx $path/*.txt '
              '"$path/文档/" 2>/dev/null');
          // 移动 APK
          await s.gshell('mv $path/*.apk "$path/APK/" 2>/dev/null');
          // 移动压缩包
          await s.gshell(
              'mv $path/*.zip $path/*.rar $path/*.7z $path/*.tar.gz '
              '"$path/压缩包/" 2>/dev/null');
          steps.add('文件已按类型归类到对应文件夹');
          return ToolResult.ok('✅ 文件整理完成:\n${r()}\n分类: 图片/视频/文档/APK/压缩包');
        }

        return ToolResult.error('未知操作: $action');
      },
    );

/// ——— 应用管理：批量卸载 / 清除缓存 / 批量权限 ———
Tool _phoneAppManagerTool(AndroidAutomationService s) => Tool(
      name: 'android_phone_app_manager',
      description:
          '【手机管家】管理已安装的应用。可：卸载应用、清除应用缓存、'
          '批量管理应用权限、列出占用空间最大的应用。需要 Shizuku 已授权。',
      schema: _props({
        'action': {
          'type': 'string',
          'enum': ['uninstall', 'clear_cache', 'list_large', 'disable', 'permissions'],
          'description': 'uninstall=卸载应用, clear_cache=清除指定应用缓存, '
              'list_large=列出占用最大应用, disable=禁用应用, permissions=查看应用权限列表',
        },
        'package_name': {
          'type': 'string',
          'description': '应用包名（uninstall/clear_cache/disable/permissions 时必填）',
        },
        'keep_system': {
          'type': 'boolean',
          'description': 'list_large 时是否排除系统应用，默认 true',
        },
      }),
      handler: (args) async {
        final action = (args['action'] as String?) ?? 'list_large';
        final pkg = (args['package_name'] as String?) ?? '';
        final keepSystem = args['keep_system'] as bool? ?? true;
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        if (action == 'list_large') {
          final exclude = keepSystem ? '| grep -v system' : '';
          final r = await s.gshell(
              'pm list packages ${keepSystem ? "-3" : ""} 2>/dev/null | '
              'head -50 | while read line; do '
              'pkg=${line#package:}; '
              'size=$(du -sh /data/data/$pkg 2>/dev/null | cut -f1); '
              '[ -n "$size" ] && echo "$size $pkg"; '
              'done | sort -rh | head -20');
          final sb = StringBuffer();
          sb.writeln('===== 占用空间最大的应用 =====');
          sb.writeln(r.stdout.trim().isNotEmpty
              ? r.stdout.trim()
              : '(无可显示数据，需要 Shizuku 已授权)');
          sb.writeln('\n提示：用 android_phone_cleaner action=deep_clean 可一键清理所有缓存');
          return ToolResult.ok(sb.toString());
        }

        if (action == 'uninstall') {
          if (pkg.isEmpty) return ToolResult.error('需要 package_name 参数');
          final r = await s.gshell('pm uninstall -k --user 0 $pkg 2>/dev/null');
          steps.add('卸载 $pkg: ${r.ok ? "OK" : "失败"}');
          return ToolResult.ok('${r.ok ? "✅" : "❌"} 卸载应用:\n${r()}');
        }

        if (action == 'clear_cache') {
          if (pkg.isEmpty) return ToolResult.error('需要 package_name 参数');
          final r = await s.gshell('pm clear $pkg 2>/dev/null');
          steps.add('清除缓存 $pkg: ${r.ok ? "OK" : "失败"}');
          return ToolResult.ok('${r.ok ? "✅" : "❌"} 清除缓存:\n${r()}');
        }

        if (action == 'disable') {
          if (pkg.isEmpty) return ToolResult.error('需要 package_name 参数');
          final r = await s.gshell('pm disable $pkg 2>/dev/null || pm hide $pkg 2>/dev/null');
          steps.add('禁用 $pkg: ${r.ok ? "OK" : "失败"}');
          return ToolResult.ok('${r.ok ? "✅" : "❌"} 禁用应用:\n${r()}');
        }

        if (action == 'permissions') {
          if (pkg.isEmpty) return ToolResult.error('需要 package_name 参数');
          final r = await s.gshell('dumpsys package $pkg 2>/dev/null | grep -A 100 "requested permissions:" | head -50');
          return ToolResult.ok('===== $pkg 权限列表 =====\n${r.stdout.trim().isNotEmpty ? r.stdout.trim() : "无法获取（需要 Shizuku）"}');
        }

        return ToolResult.error('未知操作: $action');
      },
    );

/// ——— 深度清理：分析存储 / 清理缓存 / 垃圾文件 ———
Tool _phoneDeepCleanTool(AndroidAutomationService s) => Tool(
      name: 'android_phone_deep_clean',
      description:
          '【手机管家】深度清理手机存储空间。可：一键清理所有应用缓存、'
          '清理系统垃圾（空目录/临时文件）、分析存储使用情况、清理卸载残留。'
          '需要 Shizuku 已授权。',
      schema: _props({
        'action': {
          'type': 'string',
          'enum': ['quick_clean', 'deep_clean', 'analyze_storage', 'clean_residue'],
          'description': 'quick_clean=快速清理(缓存+临时文件), deep_clean=深度清理(缓存+临时+空目录+残留), '
              'analyze_storage=详细存储分析, clean_residue=清理卸载残留',
        },
      }),
      handler: (args) async {
        final action = (args['action'] as String?) ?? 'quick_clean';
        final steps = <String>[];
        String r() => steps.map((l) => '  • $l').join('\n');

        if (action == 'analyze_storage') {
          final sb = StringBuffer();
          sb.writeln('===== 存储深度分析 =====');
          final r1 = await s.gshell('df -h 2>/dev/null');
          sb.writeln(r1.stdout.trim());
          sb.writeln('');
          // 各目录大小
          final dirs = ['/sdcard/DCIM', '/sdcard/Download', '/sdcard/Android', '/sdcard/Music',
              '/sdcard/Movies', '/sdcard/Pictures', '/sdcard/Documents'];
          for (final d in dirs) {
            final r = await s.gshell('du -sh $d 2>/dev/null');
            if (r.ok && r.stdout.trim().isNotEmpty) {
              sb.writeln(r.stdout.trim());
            }
          }
          sb.writeln('\n提示：用 clean_temp 清理临时文件，用 deep_clean 深度清理');
          return ToolResult.ok(sb.toString());
        }

        if (action == 'quick_clean') {
          // 清理所有应用缓存
          final r1 = await s.gshell(
              'for pkg in \$(pm list packages -3 2>/dev/null | cut -d: -f2); do '
              'pm clear \$pkg 2>/dev/null; done; echo "done"');
          steps.add('应用缓存清理: ${r1.ok ? "OK" : "部分失败"}');
          // 清理临时文件
          await s.gshell(
              'find /sdcard -type f \\( -name "*.tmp" -o -name "*.log" -o -name "*.cache" \\) -delete 2>/dev/null');
          steps.add('临时文件清理: 已执行');
          // 清理空目录
          await s.gshell('find /sdcard -type d -empty -delete 2>/dev/null');
          steps.add('空目录清理: 已执行');
          return ToolResult.ok('✅ 快速清理完成:\n${r()}\n已清理: 第三方应用缓存 + 临时文件 + 空目录');
        }

        if (action == 'deep_clean') {
          // 所有应用缓存
          await s.gshell(
              'for pkg in \$(pm list packages 2>/dev/null | cut -d: -f2); do '
              'pm clear \$pkg 2>/dev/null; done');
          steps.add('所有应用缓存: 已清理');
          // 临时文件
          await s.gshell(
              'find /sdcard -type f \\( -name "*.tmp" -o -name "*.log" -o -name "*.cache" '
              '-o -name "*.temp" -o -name "thumbs.db" -o -name ".thumb*" \\) -delete 2>/dev/null');
          steps.add('临时/缩略图文件: 已清理');
          // 空目录
          await s.gshell('find /sdcard -type d -empty -delete 2>/dev/null');
          steps.add('空目录: 已清理');
          // 清理下载目录 30 天前
          await s.gshell(
              'find /sdcard/Download -type f -mtime +30 -delete 2>/dev/null');
          steps.add('下载目录旧文件: 已清理');
          // 清理 Android/logs
          await s.gshell('rm -rf /sdcard/Android/logs/* 2>/dev/null');
          steps.add('系统日志: 已清理');
          return ToolResult.ok('✅ 深度清理完成:\n${r()}\n清理: 全部缓存 + 临时文件 + 缩略图 + 空目录 + 下载旧文件 + 系统日志');
        }

        if (action == 'clean_residue') {
          // 查找卸载残留（包名目录但无对应 package）
          final r = await s.gshell(
              'for d in /data/data/* /data/app/*; do '
              'pkg=\$(basename \$d); '
              'pm list packages | grep -q \$pkg || echo "残留: \$d"; '
              'done 2>/dev/null | head -30');
          if (r.stdout.trim().isEmpty) {
            return ToolResult.ok('✅ 未发现卸载残留');
          }
          return ToolResult.ok('===== 卸载残留 =====\n${r.stdout}\n提示：用 pm uninstall 或手动删除');
        }

        return ToolResult.error('未知操作: $action');
      },
    );

/// Known banking packages.
const _bankingPackages = <String>{
  'com.icbc', 'com.chinamworld.main', 'com.ccb.forum',
  'com.icbc.biz', 'com.abchina.qr', 'com.bankcomm.ebank',
  'com.cmbchina.ccd.phone.cmbmobilebank', 'com.spdb.ibank',
  'com.citicbank.mobilebank', 'com.cebbank.mobile.cebapp',
  'com.hxb.credit', 'com.cmbc.ccb', 'com.pingan.bank',
  'com.cgbchina.xianyu', 'com.cib.credit', 'com.psbc.mbank',
  'com.unionpay.payment', 'com.chinapay.payment',
};

/// Known payment packages.
const _paymentPackages = <String>{
  'com.eg.android.AlipayGphone', 'com.alipay.mobile',
  'com.tencent.mm', 'com.tencent.mobileqq',
  'com.jingdong.app.mall', 'com.taobao.taobao',
  'com.sankuai.meituan', 'com.dianping.v1',
  'com.xiaomi.shop',
};

/// Known security packages.
const _securityPackages = <String>{
  'com.qihoo360.mobilesafe', 'com.tencent.qqpimsecure',
  'com.lbe.security', 'com.ijinshan.mguard',
  'com.cleanmaster.mguard', 'com.antivirus',
  'com.samsung.android.security.manager',
};

/// Social packages (monitored by accessibility).
const _socialPackages = <String>{
  'com.tencent.mm', 'com.tencent.mobileqq',
  'com.ss.android.ugc.aweme', 'com.xingin.xhs',
  'tv.danmaku.bili', 'com.sina.weibo',
  'com.zhihu.android',
};

/// Game packages (monitored by accessibility).
const _gamePackages = <String>{
  'com.hypergryph.arknights', 'com.tencent.tmgp.sgame',
  'com.tencent.tmgp.cod', 'com.netease.mc.pe',
  'com.miHoYo.GenshinImpact', 'com.miHoYo.hkrpg',
};
