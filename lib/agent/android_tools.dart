// Android automation Agent tools — wrap [AndroidAutomationService] calls
// in the Agent [Tool] interface so the ReAct runtime can dispatch them.
//
// Tool naming matches the plan document; each tool includes a short Chinese
// description so the 0.6B–4B on-device model learns to pick the right one.
library android_tools;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/services/android_automation_service.dart';
import 'agent_runtime.dart';

part 'android_tools/android_tools_base.dart';
part 'android_tools/android_tools_compose.dart';
part 'android_tools/android_tools_system.dart';
part 'android_tools/android_tools_advanced.dart';
part 'android_tools/android_tools_permission.dart';
part 'android_tools/android_tools_phone_manager.dart';

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