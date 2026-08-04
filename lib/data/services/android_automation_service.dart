// Dart-side wrapper around the Android Automation MethodChannel.
//
// Mirrors the 10+ methods exposed by AutomationChannel.kt (com.openagent.automation).
// Every call is best-effort — methods return a nullable status so the higher
// Tool layer can translate failures into a readable ToolResult for the Agent.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import 'file_storage_service.dart';

class AndroidAutomationService {
  AndroidAutomationService._();
  static final AndroidAutomationService instance = AndroidAutomationService._();

  static const _channel = MethodChannel('com.openagent.automation');

  /// 权限状态缓存，减少重复查询系统。
  AutomationPermissionStatus? _cachedStatus;
  DateTime _cacheTimestamp = DateTime(2000);
  static const Duration _cacheTtl = Duration(seconds: 30);

  /// 使权限缓存失效，下次查询将重新获取。
  void invalidatePermissionCache() {
    _cacheTimestamp = DateTime(2000);
  }

  /// 获取缓存的权限状态（如果未过期），否则返回 null。
  AutomationPermissionStatus? get cachedPermissionStatus {
    if (_cachedStatus != null &&
        DateTime.now().difference(_cacheTimestamp) < _cacheTtl) {
      return _cachedStatus;
    }
    return null;
  }

  /// 统一权限检查入口：检查指定权限是否已授予，未授予时自动尝试授权。
  /// 返回 (isGranted, message)。
  Future<({bool granted, String message})> ensurePermission(PermissionKind kind) async {
    final status = await refreshStatus();
    switch (kind) {
      case PermissionKind.accessibility:
        if (status.accessibilityEnabled) return (granted: true, message: '无障碍服务已启用');
        // 尝试自动启用
        final r = await gshell(
            'settings put secure enabled_accessibility_services '
            'com.openagent.openagent/com.openagent.openagent.automation.OpenAgentAccessibilityService 2>/dev/null');
        if (r.ok) await gshell('settings put secure accessibility_enabled 1');
        invalidatePermissionCache();
        final refreshed = await refreshStatus();
        return (granted: refreshed.accessibilityEnabled, message: refreshed.accessibilityEnabled ? '无障碍服务已启用' : '无法自动启用无障碍服务，请手动在设置中开启');
      case PermissionKind.shizuku:
        final r = await gshell('ps -ef | grep shizuku 2>/dev/null');
        final ok = r.stdout.contains('shizuku');
        return (granted: ok, message: ok ? 'Shizuku 运行中' : 'Shizuku 未运行，请先启动 Shizuku');
      case PermissionKind.notification:
        if (status.notificationListenerGranted) return (granted: true, message: '通知监听已启用');
        await gshell(
            'settings put secure enabled_notification_listeners '
            'com.openagent.openagent/com.openagent.openagent.automation.OpenAgentNotificationListener 2>/dev/null');
        await gshell(
            'settings put secure enabled_notification_assistant '
            'com.openagent.openagent/com.openagent.openagent.automation.OpenAgentNotificationListener 2>/dev/null');
        invalidatePermissionCache();
        final refreshed = await refreshStatus();
        return (granted: refreshed.notificationListenerGranted, message: refreshed.notificationListenerGranted ? '通知监听已启用' : '无法自动启用通知监听');
      case PermissionKind.usageStats:
        return (granted: status.usageStatsGranted, message: status.usageStatsGranted ? '使用统计权限已授予' : '未授予使用统计权限');
      case PermissionKind.writeSecure:
        final r = await gshell('pm grant com.openagent.openagent android.permission.WRITE_SECURE_SETTINGS 2>/dev/null');
        return (granted: r.ok, message: r.ok ? 'WRITE_SECURE_SETTINGS 已授予' : '未授予 WRITE_SECURE_SETTINGS（需要 Shizuku/Root）');
      case PermissionKind.dump:
        final r = await gshell('pm grant com.openagent.openagent android.permission.DUMP 2>/dev/null');
        return (granted: r.ok, message: r.ok ? 'DUMP 权限已授予' : '未授予 DUMP 权限（需要 Shizuku/Root）');
    }
  }

  /// Throws on non-Android platforms (which is expected — callers should gate
  /// on [isSupported] before invoking anything else).
  bool get isSupported =>
      defaultTargetPlatform == TargetPlatform.android;

  // ---- Permission checks / intents -----------------------------------------

  /// Refreshes the runtime permission & backend status for the permission UI.
  ///
  /// Strategy: first call the aggregate `android_get_permission_status` (added
  /// in v1.1 of the MethodChannel); fall back to individual booleans when
  /// running on a Kotlin host that still ships the older bridge. Also merges
  /// in [AutomationPermissionStatus.warningDismissed] from AppConfig (it's
  /// persisted to disk, not a runtime Android flag).
  ///
  /// 使用缓存：30 秒内重复调用返回缓存结果，减少系统查询。
  Future<AutomationPermissionStatus> refreshStatus() async {
    if (!isSupported) return const AutomationPermissionStatus();
    // 优先返回缓存
    final cached = cachedPermissionStatus;
    if (cached != null) return cached;

    final storage = FileStorageService();
    final saved = await storage.loadAppConfig();

    // Try aggregate method first (newer hosts).
    try {
      final m = await _channel
          .invokeMapMethod<String, dynamic>('android_get_permission_status');
      if (m != null && m.isNotEmpty) {
        _cachedStatus = AutomationPermissionStatus(
          accessibilityEnabled: m['accessibility_enabled'] == true,
          shizukuGranted: m['shizuku_granted'] == true,
          screenshotGranted: (m['screenshot_granted'] == true) ||
              saved.automation.screenshotGranted,
          usageStatsGranted: m['usage_stats_granted'] == true,
          warningDismissed: saved.automation.warningDismissed,
        );
        _cacheTimestamp = DateTime.now();
        return _cachedStatus!;
      }
    } catch (_) {
      // ignore — fall back to legacy two-bool call below.
    }

    final a11y = await _channel.invokeMethod<bool>(
            'is_accessibility_enabled') ??
        false;
    final shizuku =
        await _channel.invokeMethod<bool>('is_shizuku_available') ?? false;
    _cachedStatus = AutomationPermissionStatus(
      accessibilityEnabled: a11y,
      shizukuGranted: shizuku,
      screenshotGranted: saved.automation.screenshotGranted,
      warningDismissed: saved.automation.warningDismissed,
    );
    _cacheTimestamp = DateTime.now();
    return _cachedStatus!;
  }

  /// Raw aggregate permission/status map — used by [androidGetPermissionStatus]
  /// Tool so the Agent can double-check what it's allowed to do.
  Future<Map<String, dynamic>> getPermissionStatusMap() async {
    if (!isSupported) return {};
    final m = await _channel
        .invokeMapMethod<String, dynamic>('android_get_permission_status');
    return Map<String, dynamic>.from(m ?? const {});
  }

  /// Returns the currently-foreground app (package + activity). Used by the
  /// Agent to sanity-check "I am in the right App" before issuing clicks.
  Future<TopAppInfo> getTopApp() async {
    if (!isSupported) return const TopAppInfo(package: '', activity: '');
    final r = await _channel.invokeMapMethod<String, dynamic>('android_top_app') ??
        <String, dynamic>{};
    return TopAppInfo(
      package: (r['package'] as String?) ?? '',
      activity: (r['activity'] as String?) ?? '',
    );
  }

  /// Raw passthrough to `Runtime.exec` (or Shizuku when available). Only for
  /// power-users / L2 dispatch.
  Future<ShellResult> gshell(String command) async {
    if (!isSupported) return const ShellResult(exitCode: -1, ok: false, stdout: '', stderr: 'platform-not-android');
    final r = await _channel.invokeMapMethod<String, dynamic>(
          'android_gshell',
          {'command': command},
        ) ??
        const <String, dynamic>{};
    return ShellResult(
      exitCode: (r['exit_code'] as int?) ?? -1,
      ok: r['ok'] == true,
      stdout: (r['stdout'] as String?) ?? '',
      stderr: (r['stderr'] as String?) ?? '',
    );
  }

  Future<void> openAccessibilitySettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('open_accessibility_settings');
  }

  /// Opens the Shizuku app (if installed) or falls back to the Play Store
  /// listing so the user can download it. Returns true if the intent launched.
  Future<bool> openShizukuApp() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('open_shizuku_app') ?? false;
  }

  /// Opens Settings → Apps with usage access (PACKAGE_USAGE_STATS).
  /// Used by the permission guide page to let the user enable "查前台App".
  Future<void> openUsageAccessSettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('open_usage_access_settings');
  }

  // ---- Safe mode (anti-detection) ------------------------------------------

  /// 设置安全模式。开启时无障碍服务跳过所有手势执行。
  Future<bool> setSafeMode(bool enabled) async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('android_set_safe_mode', {'enabled': enabled}) ?? false;
  }

  /// 查询当前是否处于安全模式。
  Future<bool> isSafeMode() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('android_is_safe_mode') ?? false;
  }

  // ---- Automation actions --------------------------------------------------

  Future<bool> openApp(String packageName) async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>(
          'android_open_app',
          {'package_name': packageName},
        ) ??
        false;
  }

  Future<bool> clickByText(String text, {bool exact = true}) async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>(
          'android_click_by_text',
          {'text': text, 'exact': exact},
        ) ??
        false;
  }

  Future<bool> clickById(String viewId) async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>(
          'android_click_by_id',
          {'view_id': viewId},
        ) ??
        false;
  }

  Future<bool> clickCoords(int x, int y) async {
    if (!isSupported) return false;
    final ok = await _channel.invokeMethod<bool>(
          'android_click_coords',
          {'x': x, 'y': y},
        ) ??
        false;
    if (ok) return true;
    // L2 fallback: Shizuku shell `input tap x y` — works even when
    // AccessibilityService.dispatchGesture is blocked by fullscreen
    // exclusive games, FLAG_SECURE, or system restrictions.
    final shell = await gshell('input tap $x $y');
    return shell.ok && shell.exitCode == 0;
  }

  /// 长按指定文字的控件（通过 AccessibilityService 查找节点）。
  Future<bool> longClickByText(String text, {bool exact = true}) async {
    if (!isSupported) return false;
    // dump UI first to find the node
    final dump = await dumpUi();
    if (dump.isEmpty) return false;
    // Try to find coordinates through dump
    // Simple approach: clickByText to get coords, then long press
    // Since we can't get coords directly, fall back to shell approach
    // Use accessibility service to perform long click on the node
    final ok = await _channel.invokeMethod<bool>('android_long_click_by_text', {
      'text': text,
      'exact': exact,
    }) ?? false;
    if (ok) return true;
    // Fallback: find the text via grep in dump, extract coordinates
    final lines = dump.map((n) => n.toString()).toList();
    for (final line in lines) {
      if (exact ? line.contains('text="$text"') : line.contains(text)) {
        final xMatch = RegExp(r'x=(\d+)').firstMatch(line);
        final yMatch = RegExp(r'y=(\d+)').firstMatch(line);
        if (xMatch != null && yMatch != null) {
          final x = int.parse(xMatch.group(1)!);
          final y = int.parse(yMatch.group(1)!);
          return longPress(x, y);
        }
      }
    }
    return false;
  }

  Future<bool> swipe(
    int x1,
    int y1,
    int x2,
    int y2, {
    int durationMs = 300,
  }) async {
    if (!isSupported) return false;
    final ok = await _channel.invokeMethod<bool>('android_swipe', {
          'x1': x1,
          'y1': y1,
          'x2': x2,
          'y2': y2,
          'duration_ms': durationMs,
        }) ??
        false;
    if (ok) return true;
    final shell =
        await gshell('input swipe $x1 $y1 $x2 $y2 $durationMs');
    return shell.ok && shell.exitCode == 0;
  }

  Future<bool> scrollForward() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('android_scroll_forward') ??
        false;
  }

  Future<bool> inputText(String text) async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>(
          'android_input_text',
          {'text': text},
        ) ??
        false;
  }

  Future<bool> pressKey(AndroidKey key) async {
    if (!isSupported) return false;
    final ok = await _channel.invokeMethod<bool>(
          'android_press_key',
          {'key': _keyToString(key)},
        ) ??
        false;
    if (ok) return true;
    final code = _keyToKeycode(key);
    if (code == null) return false;
    final shell = await gshell('input keyevent $code');
    return shell.ok && shell.exitCode == 0;
  }

  /// Polls [dumpUiSummary] until [text] appears (contain match) or
  /// [timeoutSec] elapses. Returns true if the text was found before
  /// timeout; false otherwise. Used by the Agent to wait for a page load
  /// or a certain button to become visible before the next step.
  Future<bool> waitForText(
    String text, {
    int timeoutSec = 10,
    int pollMs = 500,
    bool exact = false,
  }) async {
    if (!isSupported) return false;
    final deadline =
        DateTime.now().add(Duration(seconds: timeoutSec));
    final needle = text.toLowerCase();
    while (DateTime.now().isBefore(deadline)) {
      final dump = await dumpUiSummary(limit: 200);
      final hay = dump.toLowerCase();
      final found = exact
          ? hay.split('\n').any((l) => l.trim() == needle)
          : hay.contains(needle);
      if (found) return true;
      await Future<void>.delayed(Duration(milliseconds: pollMs));
    }
    return false;
  }

  /// Returns a JSON-compatible flat list of every UI node in the currently
  /// active window. Each node has: text, id, className, pkg, bounds
  /// (left/top/right/bottom), clickable/scrollable/editable flags.
  Future<List<Map<String, dynamic>>> dumpUi() async {
    if (!isSupported) return [];
    final out = await _channel.invokeListMethod<dynamic>('android_dump_ui');
    if (out == null) return [];
    return out
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);
  }

  /// Dumps the UI tree as a human-readable summary for the Agent prompt.
  Future<String> dumpUiSummary({int limit = 80}) async {
    final nodes = await dumpUi();
    if (nodes.isEmpty) return '（无法获取 UI 树，请先开启无障碍权限）';
    final sb = StringBuffer('UI 控件 (前 $limit / 共 ${nodes.length} 项):\n');
    var i = 0;
    for (final n in nodes) {
      if (i++ >= limit) break;
      final t = (n['text'] as String? ?? '').trim();
      final cd = (n['content_description'] as String? ?? '').trim();
      final text = t.isNotEmpty ? t : cd;
      final id = n['id'] as String? ?? '';
      final clickable = n['clickable'] == true ? '↯可点' : '';
      final editable = n['editable'] == true ? '✎可输' : '';
      final scrollable = n['scrollable'] == true ? '↕可滑' : '';
      final b = n['bounds'];
      final bounds = b is List && b.length == 4
          ? '[${b[0]},${b[1]}→${b[2]},${b[3]}]'
          : '';
      final flags = [clickable, editable, scrollable]
          .where((s) => s.isNotEmpty)
          .join(' ');
      sb.writeln('  $i. ${text.isNotEmpty ? "\"$text\"" : '(无文字)'} '
          '${id.isNotEmpty ? "id=$id " : ""}'
          '$flags $bounds'.trim());
    }
    return sb.toString();
  }

  Future<List<String>> listInstalledPackages() async {
    if (!isSupported) return const [];
    final out = await _channel.invokeListMethod<String>('android_list_packages');
    return List<String>.unmodifiable(out ?? const []);
  }

  Future<List<int>?> screenResolution() async {
    if (!isSupported) return null;
    final out = await _channel.invokeListMethod<int>('android_screen_resolution');
    return out?.toList();
  }

  /// Captures the full screen into a PNG stored in the app cache directory.
  /// Returns the absolute file path, or null on failure (no permission).
  Future<String?> takeScreenshot() async {
    if (!isSupported) return null;
    return await _channel.invokeMethod<String?>('android_screenshot');
  }

  Future<bool> installApk(String apkPath) async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>(
          'android_install_apk',
          {'apk_path': apkPath},
        ) ??
        false;
  }

  // ==========================================================================
  // 开放通用能力：给 VLM 自主决策留足空间
  // ==========================================================================

  /// 长按屏幕坐标 [durationMs] 毫秒。
  /// 优先用 AccessibilityService.dispatchGesture 长按；失败回退到 shell input swipe 同点拖
  Future<bool> longPress(int x, int y, {int durationMs = 800}) async {
    if (!isSupported) return false;
    final ok = await _channel.invokeMethod<bool>('android_long_press', {
          'x': x,
          'y': y,
          'duration_ms': durationMs,
        }) ??
        false;
    if (ok) return true;
    // shell fallback: 同起点终点 swipe = 长按效果
    final shell = await gshell(
      'input swipe $x $y $x $y $durationMs',
    );
    return shell.ok && shell.exitCode == 0;
  }

  /// 长按坐标别名（供组合宏工具使用）。
  Future<bool> longClickCoords(int x, int y, {int durationMs = 800}) async {
    return longPress(x, y, durationMs: durationMs);
  }

  /// 自定义路径手势：按 [points] 数组顺序画一条手势路径。
  /// points 每项是 {'x': int, 'y': int}，点数量 ≥ 2 才能形成路径。
  /// 总时长 [totalDurationMs] 会平均分配到每段线段。
  Future<bool> customGesture(
    List<Map<String, int>> points, {
    int totalDurationMs = 500,
  }) async {
    if (!isSupported) return false;
    if (points.length < 2) return false;
    final ok = await _channel.invokeMethod<bool>('android_custom_gesture', {
          'points': points,
          'duration_ms': totalDurationMs,
        }) ??
        false;
    if (ok) return true;
    // shell fallback：逐段 swipe（精度会差一些但能用）
    final segDur = (totalDurationMs / (points.length - 1)).round();
    var lastOk = true;
    for (var i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final r = await gshell(
        'input swipe ${p1['x']} ${p1['y']} ${p2['x']} ${p2['y']} $segDur',
      );
      if (!(r.ok && r.exitCode == 0)) lastOk = false;
    }
    return lastOk;
  }

  /// 读剪贴板（shell + service 双通道，返回文本或空）。
  Future<String> getClipboard() async {
    if (!isSupported) return '';
    final out = await _channel.invokeMethod<String?>('android_get_clipboard');
    if (out != null && out.isNotEmpty) return out;
    // shell fallback (某些 ROM 需要 service call clipboard 2 / cmd clipboard get)
    final r1 = await gshell('cmd clipboard get');
    if (r1.ok && r1.stdout.trim().isNotEmpty) return r1.stdout.trim();
    return '';
  }

  /// 写剪贴板。
  Future<bool> setClipboard(String text) async {
    if (!isSupported) return false;
    final ok = await _channel.invokeMethod<bool>(
          'android_set_clipboard',
          {'text': text},
        ) ??
        false;
    if (ok) return true;
    // shell fallback: service call clipboard 1 s16 "text"
    final escaped = text.replaceAll('"', '\\"').replaceAll("'", "\\'");
    final r = await gshell('am broadcast -a clipper.set -e text "$escaped"');
    if (r.ok) return true;
    final r2 = await gshell('cmd clipboard set "$escaped"');
    return r2.ok;
  }

  // ==========================================================================
  // H10 开放原子能力：完全交给 (LLM+VLM) 自由组合，不做任何流程硬编码
  // ==========================================================================

  /// 发送任意 Android Intent（最通用的原子能力）。
  /// 参数都是可选的，具体取值参考 `adb shell am start ...` 文档。
  /// 用途：打开 DeepLink (scheme://...)、调起第三方 App 指定 Activity、
  ///       打电话/发短信/发邮件、分享文本/图片到任意 App、打开系统设置页面等。
  Future<ShellResult> sendIntent({
    String? action, // 如 android.intent.action.VIEW / DIAL / SENDTO
    String? data,   // 如 tel:10086 / https://... / sms:... / smsto:
    String? type,   // 如 text/plain / image/*
    List<String>? categories, // 如 android.intent.category.BROWSABLE
    String? component, // 如 com.tencent.mm/.ui.LauncherUI
    Map<String, String>? extrasString, // -e key value
    Map<String, int>? extrasInt,      // --ei key value
    Map<String, bool>? extrasBool,    // --ez key value
    String? package,  // -p 限制到某包
    bool waitForResult = false, // -W
  }) async {
    if (!isSupported) {
      return ShellResult(ok: false, exitCode: -1, stdout: '', stderr: 'not supported');
    }
    final parts = <String>['am', 'start'];
    if (waitForResult) parts.add('-W');
    if (action != null) { parts.add('-a'); parts.add(action); }
    if (data != null)   { parts.add('-d'); parts.add("'$data'"); }
    if (type != null)   { parts.add('-t'); parts.add(type); }
    if (package != null){ parts.add('-p'); parts.add(package); }
    if (component != null) { parts.add('-n'); parts.add(component); }
    categories?.forEach((c) { parts.add('-c'); parts.add(c); });
    extrasString?.forEach((k, v) {
      parts.add('-e'); parts.add(k); parts.add("'${v.replaceAll("'", "\\'")}'");
    });
    extrasInt?.forEach((k, v) { parts.add('--ei'); parts.add(k); parts.add('$v'); });
    extrasBool?.forEach((k, v) { parts.add('--ez'); parts.add(k); parts.add(v ? 'true' : 'false'); });
    return gshell(parts.join(' '));
  }

  /// 文件系统：读 / 写 / 列目录 / 删除。
  /// 典型路径：/sdcard/ /sdcard/Download/ /sdcard/Pictures/
  ///          应用内部：/data/data/com.openagent.openagent/files/ (需Root或本App)
  Future<String> fileRead(String path) async =>
      (await gshell('cat "$path"')).stdout;
  Future<bool> fileWrite(String path, String content, {bool append = false}) async {
    final esc = content.replaceAll("'", "'\\''");
    final op = append ? '>>' : '>';
    final r = await gshell("echo '$esc' $op '$path'");
    return r.ok && r.exitCode == 0;
  }
  Future<List<String>> fileListDir(String path) async {
    final r = await gshell('ls -la "$path"');
    if (!(r.ok && r.exitCode == 0)) return const [];
    return r.stdout.split('\n').where((l) => l.trim().isNotEmpty).toList();
  }
  Future<bool> fileDelete(String path) async {
    final r = await gshell('rm -rf "$path"');
    return r.ok && r.exitCode == 0;
  }
  Future<bool> fileExists(String path) async {
    final r = await gshell('[ -e "$path" ] && echo 1 || echo 0');
    return r.stdout.trim() == '1';
  }

  /// 查询 App 详情 (pm dump + dumpsys package)：
  /// 版本号、安装时间、targetSdk、权限列表、所有 Activity/Service 导出组件、当前uid等。
  /// 给 LLM 足够原始信息让它自己判断"这个 App 能做什么"。
  Future<String> appInfo(String packageName, {bool verbose = false}) async {
    final sb = StringBuffer();
    final r1 = await gshell('dumpsys package $packageName');
    if (r1.ok) {
      sb.writeln('===== dumpsys package $packageName =====');
      sb.writeln(verbose ? r1.stdout :
          r1.stdout.split('\n').take(80).join('\n'));
    }
    final r2 = await gshell('pm list packages -f | grep -i "$packageName"');
    if (r2.ok && r2.stdout.trim().isNotEmpty) {
      sb.writeln('\n===== APK path =====\n${r2.stdout}');
    }
    if (verbose) {
      final r3 = await gshell('pm dump $packageName | head -n 200');
      if (r3.ok) sb.writeln('\n===== pm dump =====\n${r3.stdout}');
    }
    return sb.toString();
  }

  /// 读取通知栏当前所有通知（免Root但需要用户授权"通知访问"）。
  /// 返回每个通知的：包名、标题、文字、时间、是否可清除。
  /// LLM 可以基于推送内容自主决策（比如收到微信消息自动回复、收到验证码自动填）。
  Future<String> getNotifications({int limit = 30}) async {
    if (!isSupported) return '';
    final out = await _channel.invokeMethod<String>('android_get_notifications', {
      'limit': limit,
    });
    if (out != null && out.trim().isNotEmpty) return out;
    // shell fallback (需要 Root 或 NotificationListenerService): dumpsys notification
    final r = await gshell('dumpsys notification --noredact 2>/dev/null | head -n ${limit * 10}');
    return r.stdout;
  }

  /// WindowManager 底层 Dump：
  /// 当前焦点 Activity/AppToken、所有真实显示的窗口 (WindowState)、
  ///   每个窗口的包名/Layer/Surface/可见区域/输入法窗口/状态栏/导航栏。
  /// 和 android_dump_ui (Accessibility View 树) 互补：
  ///   某些游戏/视频 App 的 View 树是空的但 Window 层可以看到真实的 Layer 信息、
  ///   悬浮窗/分屏/PiP 也能看到。LLM 把两个 dump 交叉比对，判断更准。
  Future<String> dumpWindows({int limitLines = 200}) async {
    final focus = await gshell('dumpsys window windows | grep -E "mCurrentFocus|mFocusedApp|mInputMethodTarget|STATUS_BAR|NAVIGATION_BAR" 2>/dev/null');
    final full = await gshell('dumpsys window windows 2>/dev/null | head -n $limitLines');
    final sb = StringBuffer();
    sb.writeln('===== WindowManager 焦点 =====');
    sb.writeln(focus.stdout.trim().isEmpty ? '(dumpsys不可用)' : focus.stdout);
    sb.writeln('\n===== WindowManager 详细 (前 $limitLines 行) =====');
    sb.writeln(full.stdout);
    return sb.toString();
  }

  // ==========================================================================
  // H11 补充开放原子：联系人 / 电量网络 / 双卡短信 / 传感器
  // ==========================================================================

  /// 联系人查询（通过原生 ContentResolver + shell content query 双通道）。
  /// [kw] 模糊搜索 display_name / phone / email；空=返回最近 N 条。
  /// 原生层没权限或失败时自动退化为 shell content query (需要 READ_CONTACTS 或 Root)。
  Future<String> queryContacts({String kw = '', int limit = 50}) async {
    final sb = StringBuffer();
    final escaped = kw.replaceAll("'", "''");
    // Shell fallback (most devices work if permission granted; Root always works)
    final where = kw.isEmpty ? '' : "display_name LIKE '%$escaped%' OR data1 LIKE '%$escaped%'";
    final selectionArgs = kw.isEmpty ? '' : "WHERE $where";
    final r1 = await gshell(
      "content query --uri content://com.android.contacts/data --projection display_name:data1:mimetype:contact_id $selectionArgs --limit $limit 2>/dev/null",
    );
    if (r1.ok && r1.stdout.trim().isNotEmpty) {
      sb.writeln('===== 联系人 (shell content resolver, limit=$limit) =====');
      sb.writeln(r1.stdout);
    } else {
      sb.writeln('(shell content 查询不可用，请授予 读取联系人 权限或 Root)');
    }
    // 顺带查一下电话本 raw_contacts 计数
    final r2 = await gshell(
      "content query --uri content://com.android.contacts/raw_contacts --projection _id:display_name --limit $limit 2>/dev/null",
    );
    if (r2.ok && r2.stdout.trim().isNotEmpty) {
      sb.writeln('\n===== RawContacts (仅 display_name, limit=$limit) =====');
      sb.writeln(r2.stdout);
    }
    return sb.toString();
  }

  /// 设备当前电量 + 网络 + 硬件状态：电量%、是否充电、电压、温度、
  ///   移动网络/WiFi 开关状态+IP+信号、蓝牙/GPS/NFC、屏幕亮度/旋转锁。
  /// 给 LLM 完整信息让它自己判断"现在是不是应该开 WiFi 省电？"、
  ///   "电量 10% 还刷视频要提醒用户吗？"等各种场景。
  Future<String> getDeviceStatus() async {
    final sb = StringBuffer();
    final r1 = await gshell('dumpsys battery 2>/dev/null');
    if (r1.ok) {
      sb.writeln('===== Battery =====');
      // 只保留最关键 20 行，其余省略
      sb.writeln(r1.stdout.split('\n').take(25).join('\n'));
    }
    final r2 = await gshell('dumpsys connectivity 2>/dev/null | head -n 40');
    if (r2.ok) {
      sb.writeln('\n===== Connectivity (前 40 行) =====');
      sb.writeln(r2.stdout);
    }
    final r3 = await gshell(
      "dumpsys wifi 2>/dev/null | grep -E 'mWifiInfo|RSSI|SSID|BSSID|MacAddress|NetworkAgentInfo|networkId' | head -n 20",
    );
    if (r3.ok && r3.stdout.trim().isNotEmpty) {
      sb.writeln('\n===== WiFi =====');
      sb.writeln(r3.stdout);
    }
    final r4 = await gshell(
      "dumpsys telephony.registry 2>/dev/null | grep -E 'mServiceState|mDataConnectionState|mSignalStrength|mAllCellInfo' | head -n 20",
    );
    if (r4.ok && r4.stdout.trim().isNotEmpty) {
      sb.writeln('\n===== Telephony / Mobile =====');
      sb.writeln(r4.stdout);
    }
    final r5 = await gshell(
      "settings get system screen_brightness; settings get system accelerometer_rotation; "
      "dumpsys bluetooth_manager 2>/dev/null | grep -E 'state:|adapter.*name' | head -n 5; "
      "dumpsys location 2>/dev/null | grep -E 'mProviders|mCurrentProvider|passive|network|gps' | head -n 10",
    );
    if (r5.ok && r5.stdout.trim().isNotEmpty) {
      sb.writeln('\n===== System (brightness/rotation/bluetooth/gps) =====');
      sb.writeln(r5.stdout);
    }
    return sb.toString();
  }

  /// 发短信 (SmsManager 原生 + shell service call sms 双通道，可选双卡订阅)。
  /// [simSlot] 1=卡1 / 2=卡2 / 0=默认 (需要 READ_PHONE_STATE / SEND_SMS 权限)。
  /// 同时支持查询最近 N 条短信 (箱: inbox=收件箱 / sent=已发送)。
  Future<ShellResult> sendSms({
    required String phone,
    required String message,
    int simSlot = 0,
  }) async {
    final p = phone.replaceAll("'", "''");
    final m = message.replaceAll("'", "\\'");
    // 先试原生方法 (通过 shell service call sms 或 Java API)
    if (simSlot > 0) {
      final r = await gshell(
        "service call sms 5 i32 $simSlot s16 '$p' s16 'null' s16 '$m' s16 'null' s16 'null' 2>/dev/null",
      );
      if (r.ok && !r.stdout.toLowerCase().contains('exception')) return r;
    }
    // 默认卡: service call sms 5 i32 0 / service call isms
    final r2 = await gshell(
      "service call sms 5 s16 '$p' s16 'null' s16 '$m' s16 'null' s16 'null' 2>/dev/null",
    );
    if (r2.ok) return r2;
    // 最后的降级：用 smsto: + SENDTO intent (会弹用户确认，不自动)
    return sendIntent(
      action: 'android.intent.action.SENDTO',
      data: 'smsto:$p',
      extrasString: {'sms_body': message},
    );
  }

  Future<String> queryRecentSms({String box = 'inbox', int limit = 20}) async {
    final uri = box == 'sent' ? 'content://sms/sent' : 'content://sms/inbox';
    final r = await gshell(
      "content query --uri $uri --projection date:address:body:type:read --sort 'date DESC' --limit $limit 2>/dev/null",
    );
    final sb = StringBuffer();
    if (r.ok && r.stdout.trim().isNotEmpty) {
      sb.writeln('===== SMS 短信 ($box, limit=$limit) =====');
      sb.writeln(r.stdout);
    } else {
      sb.writeln('(短信查询不可用：请授予 READ_SMS 权限或开启 Root)');
      final fallback = await gshell(
        "dumpsys activity service com.android.mms/.service.SmsReceiverService 2>/dev/null | head -n $limit",
      );
      if (fallback.ok && fallback.stdout.trim().isNotEmpty) {
        sb.writeln('\nSMS 调试信息 (dumpsys fallback):\n${fallback.stdout}');
      }
    }
    return sb.toString();
  }

  /// 传感器列表 + 实时采样：列举手机所有 Sensor (加速度/陀螺仪/磁场/
  ///   光/接近/重力/线性加速度/旋转矢量/气压/心率/步数/温度 等)
  ///   并可以对指定几个传感器采样 N 次 (默认 1 次最新值即可)。
  /// LLM 可以基于这些原始数据自由判断"手机是不是在桌子上(接近+低加速度)？"、
  ///   "是不是在走路/跑步？"、"晚上关灯了吗(光传感器<5lux)？"等。
  Future<String> getSensors({
    bool listAll = true,
    List<int> sampleTypes = const [],
    int samplesPerSensor = 1,
  }) async {
    final sb = StringBuffer();
    if (listAll) {
      final r = await gshell(
        "dumpsys sensorservice 2>/dev/null | grep -E 'Sensor |Name:|vendor |Type:' | head -n 80",
      );
      if (r.ok && r.stdout.trim().isNotEmpty) {
        sb.writeln('===== 手机传感器列表 =====');
        sb.writeln(r.stdout);
      } else {
        sb.writeln('(sensorservice dump 不可用)');
      }
      final r2 = await gshell(
        "dumpsys sensorservice 2>/dev/null | grep -E '0x[0-9a-f]+ |^  [A-Z]' | head -n 60",
      );
      if (r2.ok && r2.stdout.trim().isNotEmpty) {
        sb.writeln('\n===== 传感器详情/采样率 =====');
        sb.writeln(r2.stdout);
      }
    }
    // 实时采样：循环 dumpsys 多次抓最新值 (不同 ROM Sensor HAL 输出格式不完全一致，所以保留原始文本)
    if (sampleTypes.isNotEmpty || samplesPerSensor > 1) {
      final types = sampleTypes.isEmpty ? '1,4,5,9,10' : sampleTypes.join(',');
      // type编号: 1=加速度 2=磁场 3=方向(已deprecated) 4=陀螺仪 5=光 6=气压 8=接近 9=重力 10=线性加速度 11=旋转矢量 18=步检 19=步数
      sb.writeln('\n===== 传感器实时采样 (types=$types, 每次 200ms) =====');
      for (var i = 0; i < samplesPerSensor.clamp(1, 30); i++) {
        final snap = await gshell(
          "dumpsys sensorservice 2>/dev/null | grep -E 'SensorEvent|last |events |values' | head -n 30",
        );
        sb.writeln('--- sample #${i + 1} ---');
        sb.writeln(snap.stdout);
        if (samplesPerSensor > 1) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    }
    return sb.toString();
  }

  // ==========================================================================
  // H15 系统原子补全 ×6：最近任务 / WiFi 扫描 / 双卡详情 / Frag 栈 / Toast 历史 / 杀进程冷启动
  // ==========================================================================

  /// 最近任务列表 (Recent Tasks / Overview)：最近 N 个用过的 App，返回包名+Activity+启动时间。
  ///   Android 11+ 系统限制第三方 App 读 UsageStats/RECENTS，
  ///   所以这里 3 条通道并行：1) dumpsys activity recents (shell user 可见)；2) dumpsys activity activities top ResumedActivities (最可靠)；3) activity tasks (旧版兼容)。
  Future<String> getRecentTasks({int limit = 20}) async {
    final sb = StringBuffer();
    final r1 = await gshell(
      "dumpsys activity recents 2>/dev/null | grep -E 'RecentTaskInfo|baseIntent|realActivity|firstActiveTime|callingPkg|taskId|topActivity' | head -n ${limit * 6}",
    );
    if (r1.ok && r1.stdout.trim().isNotEmpty) {
      sb.writeln('===== dumpsys activity recents (limit=$limit) =====');
      sb.writeln(r1.stdout);
    }
    final r2 = await gshell(
      "dumpsys activity activities 2>/dev/null | grep -E 'ResumedActivity|mResumedActivity|TaskRecord|mFocusedApp|mLastPausedActivity' | head -n ${limit * 4}",
    );
    if (r2.ok && r2.stdout.trim().isNotEmpty) {
      sb.writeln('\n===== Activity 栈 + 焦点 (真实当前/最近) =====');
      sb.writeln(r2.stdout);
    }
    final r3 = await gshell("am stack list 2>/dev/null | head -n $limit");
    if (r3.ok && r3.stdout.trim().isNotEmpty) {
      sb.writeln('\n===== am stack list =====');
      sb.writeln(r3.stdout);
    }
    if (sb.isEmpty) {
      sb.writeln('(最近任务不可用：请授予 QUERY_ALL_PACKAGES / PACKAGE_USAGE_STATS，或开 Root/Shizuku)');
    }
    return sb.toString();
  }

  /// 当前前台 Activity 完整 Fragment 栈 + ViewRootImpl 列表：
  ///   给 LLM 看"微信当前到底在哪个Fragment"、"DialogFragment 弹没弹"、"是哪个 ViewRootImpl 持有焦点"等细粒度判断。
  Future<String> dumpActivityFragments({int limitLines = 160}) async {
    final r1 = await gshell(
      "dumpsys activity top 2>/dev/null | head -n $limitLines",
    );
    final sb = StringBuffer();
    if (r1.ok && r1.stdout.trim().isNotEmpty) {
      sb.writeln('===== dumpsys activity top (前 $limitLines 行, 含 Fragment 栈) =====');
      sb.writeln(r1.stdout);
    }
    final r2 = await gshell(
      "dumpsys SurfaceFlinger --list 2>/dev/null | head -n 80",
    );
    if (r2.ok && r2.stdout.trim().isNotEmpty) {
      sb.writeln('\n===== SurfaceFlinger Layer 列表 (含 Dialog/PiP/子窗口) =====');
      sb.writeln(r2.stdout);
    }
    return sb.toString();
  }

  /// WiFi 扫描结果 (dumpsys wifi + wpa_supplicant/scan cache)：附近所有 SSID/BSSID/信号强度/加密方式/信道。
  ///   无 Root 时系统可能只返回已连接/保存的几个，Shizuku/Root 能看到完整周边。
  Future<String> getWifiScan({int limit = 60}) async {
    final sb = StringBuffer();
    final r1 = await gshell(
      "dumpsys wifi 2>/dev/null | grep -E 'mScanResults|scanResults|BSSID|SSID|level|frequency|capabilities' | head -n ${limit * 4}",
    );
    if (r1.ok && r1.stdout.trim().isNotEmpty) {
      sb.writeln('===== WiFi Scan (dumpsys wifi, limit=$limit) =====');
      sb.writeln(r1.stdout);
    }
    final r2 = await gshell("cmd -w wifi list-scan-results 2>/dev/null | head -n $limit");
    if (r2.ok && r2.stdout.trim().isNotEmpty) {
      sb.writeln('\n===== cmd wifi list-scan-results =====');
      sb.writeln(r2.stdout);
    }
    if (sb.isEmpty) sb.writeln('(WiFi 扫描不可用：请授予 ACCESS_FINE_LOCATION + 开 WiFi，或用 Root/Shizuku)');
    return sb.toString();
  }

  /// 双卡 / IMSI / IMEI / Subscription 详情：
  ///   LLM 可以知道"当前卡1是移动5G卡、卡2是电信4G 2018XXXX"，sendSms 选卡时就不会选错。
  ///   无 READ_PHONE_STATE 权限时用 dumpsys telephony 降级返回部分信息 (不暴露完整 IMEI/IMSI)。
  Future<String> getSimInfo() async {
    final sb = StringBuffer();
    final r1 = await gshell(
      "dumpsys telephony.registry 2>/dev/null | grep -Ei 'subscriptionId|mImei|mSubscriberId|carrier|phoneId|slotId|mSimState|mDataRoaming|mVoiceData|mPhoneType|mIccId' | head -n 60",
    );
    if (r1.ok && r1.stdout.trim().isNotEmpty) {
      sb.writeln('===== Telephony Registry (卡/SIM/IMSI/IMEI 脱敏版) =====');
      sb.writeln(r1.stdout);
    }
    final r2 = await gshell(
      "dumpsys isms 2>/dev/null | grep -E 'IccSmsInterfaceManager|subscriptionId|carrierId|mIccId|iccId' | head -n 30",
    );
    if (r2.ok && r2.stdout.trim().isNotEmpty) {
      sb.writeln('\n===== ISMS (短信卡订阅详情) =====');
      sb.writeln(r2.stdout);
    }
    final r3 = await gshell("service call iphonesubinfo 1 2>/dev/null; service call iphonesubinfo 2 2>/dev/null | head -n 12");
    if (r3.ok && r3.stdout.trim().isNotEmpty) {
      sb.writeln('\n===== iphonesubinfo (若有 READ_PHONE_STATE 则含 IMEI/IMSI 原文) =====');
      sb.writeln(r3.stdout);
    }
    if (sb.isEmpty) sb.writeln('(SIM 信息不可用：请授予 READ_PHONE_STATE 或 Root)');
    return sb.toString();
  }

  /// Toast 历史 / Notification Log (部分 ROM dumpsys 能拿到)：
  ///   诊断"刚才后台 App 弹了个 验证码 Toast 没捕获到""刚才抖音弹出了 登录过期 的 Toast"之类的场景。
  Future<String> getToastHistory({int limit = 50}) async {
    final sb = StringBuffer();
    final r1 = await gshell(
      "dumpsys activity service com.android.server.notification 2>/dev/null | grep -iE 'toast|enqueueToast|show:|packageName|text|duration' | head -n ${limit * 3}",
    );
    if (r1.ok && r1.stdout.trim().isNotEmpty) {
      sb.writeln('===== NotificationManagerService Toast 痕迹 (部分 ROM 可用) =====');
      sb.writeln(r1.stdout);
    }
    final r2 = await gshell(
      "dumpsys window windows 2>/dev/null | grep -iE 'Toast|toast|TYPE_TOAST' | head -n $limit",
    );
    if (r2.ok && r2.stdout.trim().isNotEmpty) {
      sb.writeln('\n===== WindowManager 中当前可见的 Toast 窗口 =====');
      sb.writeln(r2.stdout);
    }
    final r3 = await gshell(
      "dumpsys notificationlogging 2>/dev/null | head -n ${limit * 3}",
    );
    if (r3.ok && r3.stdout.trim().isNotEmpty) {
      sb.writeln('\n===== NotificationLogging (通知日志) =====');
      sb.writeln(r3.stdout);
    }
    if (sb.isEmpty) sb.writeln('(Toast/通知历史不可用：部分 ROM 只保留 10s 内的 Toast，或需要 NotificationListener 权限)');
    return sb.toString();
  }

  /// 应用冷启动 (先杀再启) + 杀后台进程：
  ///   am force-stop 彻底杀掉缓存进程，然后 am start -n / monkey -p 干净启动。
  ///   LLM 可以自己判断"微信卡死了要不要强制重启"、"某 App 出 Bug 了要冷启动清缓存"。
  Future<ShellResult> killAndRestartApp(String packageName, {bool killOnly = false}) async {
    if (packageName.trim().isEmpty) {
      return ShellResult(ok: false, exitCode: -1, stdout: '', stderr: 'packageName 不能为空');
    }
    final kill = await gshell('am force-stop $packageName 2>/dev/null; am kill $packageName 2>/dev/null; echo killed_$packageName');
    if (killOnly) return kill;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final start = await openAppWithResult(packageName);
    if (start.ok) return start;
    // 第二个 fallback: monkey 1 次启动
    final monkey = await gshell('monkey -p $packageName -c android.intent.category.LAUNCHER 1 2>/dev/null');
    return ShellResult(
      ok: monkey.ok,
      exitCode: monkey.exitCode,
      stdout: 'force-stop 输出:\n${kill.stdout}\nmonkey fallback 输出:\n${monkey.stdout}',
      stderr: monkey.stderr,
    );
  }

  Future<ShellResult> openAppWithResult(String packageName) async {
    final r = await gshell(
      "monkey -p $packageName -c android.intent.category.LAUNCHER 1 2>/dev/null",
    );
    if (r.ok && !r.stdout.toLowerCase().contains('no activities found to run')) return r;
    // Fallback 2: 通过 PackageManager.getLaunchIntentForPackage 等效 cmd
    return gshell(
      "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER $packageName 2>/dev/null",
    );
  }

  // ==========================================================================
  // H16：运行时权限自检 + 申请引导 + 权限整体状态快照
  // ==========================================================================

  /// 检查一组 Android 权限的授予情况（通过原生 Context.checkSelfPermission），
  ///   同时会跑 shell dumpsys package 交叉验证（应对多用户/profile 场景）。
  ///   返回每行是 "permission.name = GRANTED|DENIED|NEVER_ASKED"
  ///   [perms] 为空时默认检查"我们 manifest 里所有声明过的运行时危险权限"。
  Future<String> checkPermissions({List<String> perms = const []}) async {
    final sb = StringBuffer();
    // Shell fallback: dumpsys package per-user permission flags
    final r1 = await gshell(
      "dumpsys package ${_pkgName()} 2>/dev/null | grep -E 'requested permissions|install permissions|runtime permissions|User [0-9]+:' | head -n 120",
    );
    if (r1.ok && r1.stdout.trim().isNotEmpty) {
      sb.writeln('===== dumpsys package 权限状态 (交叉验证) =====');
      sb.writeln(r1.stdout);
    }
    // 原生 Context.checkSelfPermission (通过 MethodChannel)
    try {
      final native = await _channel.invokeMethod<String>(
        'android_check_permissions',
        <String, dynamic>{'permissions': perms},
      );
      if (native != null && native.trim().isNotEmpty) {
        sb.writeln('\n===== 原生 Context.checkSelfPermission 结果 =====');
        sb.writeln(native);
      }
    } catch (_) {
      // 旧版 APK 可能没实现这个 method，忽略用 shell 结果就行
    }
    // 如果 perms 为空，另外直接通过 cmd appops 看一下常用的危险权限状态
    if (perms.isEmpty) {
      final r2 = await gshell(
        "cmd appops get ${_pkgName()} 2>/dev/null | head -n 80",
      );
      if (r2.ok && r2.stdout.trim().isNotEmpty) {
        sb.writeln('\n===== appops 状态 (后台运行/相机/麦克风/位置/短信/通话/通知等细粒度) =====');
        sb.writeln(r2.stdout);
      }
      // 三个特殊开关：无障碍、通知监听、UsageStats、SYSTEM_ALERT、WRITE_SETTINGS、MediaProjection
      final r3 = await gshell(
        "dumpsys accessibility 2>/dev/null | grep -iE 'OpenAgent|installedAccessibilityServices|enabledAccessibilityServices' | head -n 5;"
        "dumpsys notification 2>/dev/null | grep -iE 'notification_listeners|listener:' | head -n 10;"
        "dumpsys location 2>/dev/null | grep -iE 'location enabled|current user.*gps' | head -n 5;"
        "settings get global overlay_displayed 2>/dev/null;"
        "settings get secure enabled_accessibility_services 2>/dev/null;"
        "settings get secure enabled_notification_listeners 2>/dev/null",
      );
      if (r3.ok && r3.stdout.trim().isNotEmpty) {
        sb.writeln('\n===== 特殊开关（Accessibility / NotificationListener / FloatWindow / Location）=====');
        sb.writeln(r3.stdout);
      }
    }
    return sb.toString();
  }

  /// 请求运行时权限（优先通过原生 MethodChannel 调 ContextCompat.requestPermissions；
  ///   如果 Activity 前台不可用，则 fallback 打开系统应用详情页让用户点授权）。
  ///   代码层绝不替用户决定"要不要授权某权限"，全由你 (LLM) 指定请求哪几个。
  Future<ShellResult> requestRuntimePermissions(List<String> perms, {bool openSettingsIfNeeded = true}) async {
    try {
      final r = await _channel.invokeMethod<String>(
        'android_request_permissions',
        <String, dynamic>{'permissions': perms},
      );
      if (r != null && r.trim().isNotEmpty) {
        return ShellResult(ok: true, exitCode: 0, stdout: r, stderr: '');
      }
    } catch (e) {
      // method not implemented => fall through to settings intent
    }
    if (!openSettingsIfNeeded) {
      return ShellResult(ok: false, exitCode: -2, stdout: '', stderr: '原生权限申请通道不可用，openSettingsIfNeeded=false 已禁用跳转设置');
    }
    // 用户没在前台或者原生没实现：跳到应用详情页，让用户自己点"权限"
    final intentR = await sendIntent(
      action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
      data: 'package:${_pkgName()}',
      categories: const ['android.intent.category.DEFAULT'],
      waitForResult: false,
    );
    return ShellResult(
      ok: intentR.ok,
      exitCode: intentR.exitCode,
      stdout: '已跳转应用详情页，请手动授予权限 (需要用户操作)。要申请的权限:\n  - ${perms.join('\n  - ')}\n'
          '跳转输出:\n${intentR.stdout}',
      stderr: intentR.stderr,
    );
  }

  static String _pkgName() {
    return const String.fromEnvironment('APP_PKG', defaultValue: 'com.openagent.openagent');
  }

  // ==========================================================================
  // H17-1：硬件信息（型号/SDK/ABIs/CPU/内存/存储/屏幕密度/IMEI脱敏/指纹）
  // ==========================================================================

  Future<String> getHardwareInfo() async {
    final sb = StringBuffer();
    final r1 = await gshell(
      "getprop ro.product.model; getprop ro.product.brand; getprop ro.product.device; getprop ro.product.manufacturer;"
      "getprop ro.build.version.sdk; getprop ro.build.version.release; getprop ro.build.version.codename;"
      "getprop ro.product.cpu.abilist; getprop ro.product.cpu.abi; getprop ro.hardware;"
      "getprop ro.build.fingerprint; getprop ro.build.flavor; getprop ro.build.type;",
    );
    if (r1.ok && r1.stdout.trim().isNotEmpty) {
      sb.writeln('===== getprop 设备型号 / SDK / CPU 架构 =====');
      sb.writeln(r1.stdout);
    }
    final r2 = await gshell(
      "cat /proc/meminfo 2>/dev/null | head -n 20;"
      "cat /proc/cpuinfo 2>/dev/null | grep -E 'Hardware|Processor|model name|BogoMIPS|CPU implementer' | head -n 15;"
      "lscpu 2>/dev/null | head -n 25",
    );
    if (r2.ok && r2.stdout.trim().isNotEmpty) {
      sb.writeln('\n===== CPU 信息 + 内存 =====');
      sb.writeln(r2.stdout);
    }
    final r3 = await gshell(
      "df -h 2>/dev/null | grep -E ' /data\$| /storage/emulated| /sdcard|Filesystem|/mnt/runtime' | head -n 15;"
      "sm list-disks adoptable 2>/dev/null; sm list-volumes 2>/dev/null | head -n 20;",
    );
    if (r3.ok && r3.stdout.trim().isNotEmpty) {
      sb.writeln('\n===== 存储空间 (data / 内置 sdcard / 可扩展) =====');
      sb.writeln(r3.stdout);
    }
    final r4 = await gshell(
      "dumpsys display 2>/dev/null | grep -E 'DisplayDeviceInfo|mDisplayInfo|Display Info|width:|height:|density:|refreshRate|resolution' | head -n 25;"
      "wm size 2>/dev/null; wm density 2>/dev/null;",
    );
    if (r4.ok && r4.stdout.trim().isNotEmpty) {
      sb.writeln('\n===== 屏幕参数 (分辨率/dpi/刷新率) =====');
      sb.writeln(r4.stdout);
    }
    // 原生 Build 字段 (更准确的版本号/Build.SERIAL 脱敏等)
    try {
      final native = await _channel.invokeMethod<String>('android_get_build_info');
      if (native != null && native.trim().isNotEmpty) {
        sb.writeln('\n===== 原生 Build.* 字段 =====');
        sb.writeln(native);
      }
    } catch (_) {
      // 非关键信息，忽略
    }
    return sb.toString();
  }

  // ==========================================================================
  // H17-2：通话记录 / 相册 DCIM / Download 查询
  // ==========================================================================

  Future<String> getCallLog({String box = 'all', int limit = 30}) async {
    final sb = StringBuffer();
    final selection = switch (box) {
      'outgoing' => "WHERE type=2",
      'incoming' => "WHERE type=1",
      'missed' => "WHERE type=3",
      _ => '',
    };
    final r = await gshell(
      "content query --uri content://call_log/calls --projection date:number:name:type:duration:is_read:presentation $selection --sort 'date DESC' --limit $limit 2>/dev/null",
    );
    if (r.ok && r.stdout.trim().isNotEmpty) {
      sb.writeln('===== 通话记录 (box=$box, limit=$limit) =====');
      sb.writeln(r.stdout);
    } else {
      sb.writeln('(通话记录读取失败：请授予 READ_CALL_LOG 权限，或开 Root/Shizuku)');
    }
    // Fallback dumpsys 看一下最近来电状态
    final r2 = await gshell(
      "dumpsys telecom 2>/dev/null | grep -iE 'Call#|state=|handle=|TIME:' | head -n 40;"
      "dumpsys activity service com.android.server.telecom 2>/dev/null | head -n $limit",
    );
    if (r2.ok && r2.stdout.trim().isNotEmpty) {
      sb.writeln('\n===== Telecom / InCallService 当前通话 =====');
      sb.writeln(r2.stdout);
    }
    return sb.toString();
  }

  /// 查询手机媒体库（DCIM / Pictures / Download / Screenshots / Camera / ALL）
  ///   返回原始 content resolver 行：_data / _display_name / date_modified / mime_type / _size / bucket_display_name。
  Future<String> queryMediaGallery({
    String bucket = 'DCIM', // DCIM / Pictures / Download / Screenshots / Camera / ALL
    String? keyword,
    int limit = 60,
    bool includeVideos = true,
  }) async {
    final sb = StringBuffer();
    final mimeFilter = includeVideos
        ? "mime_type LIKE 'image/%' OR mime_type LIKE 'video/%'"
        : "mime_type LIKE 'image/%'";
    final kw = (keyword ?? '').trim();
    final kwFilter = kw.isEmpty ? '' : " AND (_display_name LIKE '%${kw.replaceAll("'", "''")}%')";
    final bucketFilter = bucket.toUpperCase() == 'ALL'
        ? ''
        : bucket.trim().isEmpty
            ? ''
            : " AND bucket_display_name LIKE '%${bucket.replaceAll("'", "''")}%'";
    final where = "WHERE ($mimeFilter)$bucketFilter$kwFilter";
    final r1 = await gshell(
      "content query --uri content://media/external/file --projection _id:_data:_display_name:date_modified:mime_type:_size:bucket_display_name:width:height $where --sort 'date_modified DESC' --limit $limit 2>/dev/null",
    );
    if (r1.ok && r1.stdout.trim().isNotEmpty) {
      sb.writeln('===== 媒体库 (media/external/file, bucket=$bucket, limit=$limit) =====');
      sb.writeln(r1.stdout);
    } else {
      sb.writeln('(media content 查询不可用，降级为文件系统 ls)');
    }
    // 无论成功与否，顺带用 ls 列出 DCIM/Pictures/Download 目录最近 30 个文件作为兜底（shell user 权限通常能看到）
    final ls = await gshell(
      "ls -lt /sdcard/DCIM/ 2>/dev/null | head -n 30;"
      "echo '---Pictures---'; ls -lt /sdcard/Pictures/ 2>/dev/null | head -n 20;"
      "echo '---Screenshots---'; ls -lt /sdcard/Pictures/Screenshots/ 2>/dev/null | head -n 20;"
      "echo '---Download---'; ls -lt /sdcard/Download/ 2>/dev/null | head -n 30;"
      "echo '---Camera---'; ls -lt /sdcard/DCIM/Camera/ 2>/dev/null | head -n 30",
    );
    if (ls.ok && ls.stdout.trim().isNotEmpty) {
      sb.writeln('\n===== 文件系统兜底 (ls -lt 最近 N 个) =====');
      sb.writeln(ls.stdout);
    }
    return sb.toString();
  }

  // ==========================================================================
  // H17-3：壁纸设置 / 系统亮度调节 / 输入法切换 / 截屏后分享
  // ==========================================================================

  /// 调节屏幕亮度。[brightness] 0=最暗 255=最亮；或传 "auto" 切自动亮度。
  ///   无 WRITE_SETTINGS 权限时：先尝试 settings put，失败再跳转设置页让用户手动开。
  Future<ShellResult> setSystemBrightness({
    Object brightness = 'auto', // int 0..255 或字符串 "auto"
    bool openSettingsIfDenied = true,
  }) async {
    late final ShellResult r;
    if (brightness.toString().trim().toLowerCase() == 'auto') {
      r = await gshell(
        "settings put system screen_brightness_mode 1 2>/dev/null; echo mode_auto=\$?",
      );
    } else {
      final b = (brightness is num ? brightness.toInt() : int.tryParse(brightness.toString()) ?? -1)
          .clamp(0, 255);
      r = await gshell(
        "settings put system screen_brightness_mode 0 2>/dev/null; settings put system screen_brightness $b 2>/dev/null; echo brightness=$b",
      );
    }
    // 二次确认是否写入成功
    final verify = await gshell(
      "settings get system screen_brightness; settings get system screen_brightness_mode",
    );
    if (verify.ok &&
        (verify.stdout.contains(brightness.toString()) ||
            verify.stdout.contains('screen_brightness'))) {
      return ShellResult(
        ok: r.ok,
        exitCode: r.exitCode,
        stdout: '${r.stdout}\n当前亮度实际值 (get):\n${verify.stdout}',
        stderr: r.stderr,
      );
    }
    if (!openSettingsIfDenied) {
      return ShellResult(
        ok: false,
        exitCode: -1,
        stdout: '亮度写入失败，已禁用设置页跳转。当前：\n${verify.stdout}',
        stderr: 'need WRITE_SETTINGS',
      );
    }
    final r2 = await sendIntent(
      action: 'android.settings.DISPLAY_SETTINGS',
      categories: const ['android.intent.category.DEFAULT'],
    );
    return ShellResult(
      ok: false,
      exitCode: r2.exitCode,
      stdout: '亮度调节失败 (缺少 WRITE_SETTINGS 权限)，已跳转"设置→显示"请手动开关或允许修改系统设置。当前亮度：\n${verify.stdout}',
      stderr: 'need WRITE_SETTINGS',
    );
  }

  /// 切换输入法 (IME)：传给 [imeId] 指定某个已启用输入法，或传 "next"/"prev"/"picker"。
  ///   imeId 形如 com.tencent.qqpinyin/.QQPYInputMethodService / com.google.android.inputmethod.pinyin/.PinyinIME
  ///   通过 cmd ime list -s 可以查到所有 id。
  Future<String> switchInputMethod({String imeId = 'picker'}) async {
    final listR = await gshell("cmd ime list -s 2>/dev/null");
    final sb = StringBuffer();
    sb.writeln('===== 已启用输入法列表 =====');
    sb.writeln(listR.ok && listR.stdout.isNotEmpty ? listR.stdout : '(cmd ime 不可用，需 Root 或 adb shell permissions)');
    final id = imeId.trim();
    if (id == 'picker') {
      final r = await gshell("cmd ime show-input-method-picker 2>/dev/null");
      sb.writeln('\n===== 已弹出系统输入法选择器 =====');
      sb.writeln(r.stdout.isNotEmpty ? r.stdout : '(shell 用户也没有权限弹 picker，请手动下拉通知栏改输入法)');
      return sb.toString();
    }
    if (id == 'next' || id == 'prev') {
      final r = await gshell(id == 'next'
          ? "cmd ime next 2>/dev/null; dumpsys input_method 2>/dev/null | grep -iE 'mCurMethodId|mIdToMethodMap' | head -n 15"
          : "ime set prev 2>/dev/null; cmd ime prev 2>/dev/null; dumpsys input_method 2>/dev/null | grep -iE 'mCurMethodId|mIdToMethodMap' | head -n 15");
      sb.writeln('\n===== IME ${id.toUpperCase()} 尝试结果 =====');
      sb.writeln(r.stdout);
      return sb.toString();
    }
    final r = await gshell("cmd ime set $id 2>/dev/null; echo set_$id");
    sb.writeln('\n===== 切换到 $id 结果 =====');
    sb.writeln(r.stdout);
    final cur = await gshell("dumpsys input_method 2>/dev/null | grep -iE 'mCurMethodId|mCurMethod|ime_enabled_input_methods' | head -n 10");
    if (cur.ok && cur.stdout.isNotEmpty) {
      sb.writeln('\n===== 当前生效 IME =====');
      sb.writeln(cur.stdout);
    }
    return sb.toString();
  }

  /// 系统分享：把一张图片/一段文字/一个文件路径分享出去 (Intent.ACTION_SEND)。
  ///   你 (LLM) 指定 target_package 可以直接分享到微信/抖音/小红书指定 Activity；
  ///   target_package 为空则弹系统分享面板给用户选。
  Future<ShellResult> shareSystem({
    String? imagePath,
    String? text,
    String? fileMime,
    String? targetPackage,
    String? targetComponent, // e.g. com.tencent.mm/.ui.tools.ShareToTimelineUI
  }) async {
    if ((imagePath == null || imagePath.isEmpty) && (text == null || text.isEmpty)) {
      return ShellResult(ok: false, exitCode: -1, stdout: '', stderr: 'image_path 和 text 至少填一个');
    }
    final extras = <String, String>{};
    if (text != null && text.isNotEmpty) extras['android.intent.extra.TEXT'] = text;
    if (text != null && text.isNotEmpty && text.length > 80) {
      extras['android.intent.extra.SUBJECT'] = text.substring(0, 80);
    } else if (text != null && text.isNotEmpty) {
      extras['android.intent.extra.SUBJECT'] = text;
    }
    final type = fileMime ??
        (imagePath != null && imagePath.isNotEmpty
            ? (imagePath.toLowerCase().endsWith('.mp4') ||
                    imagePath.toLowerCase().endsWith('.mov') ||
                    imagePath.toLowerCase().endsWith('.mkv'))
                ? 'video/*'
                : 'image/*'
            : 'text/plain');
    return sendIntent(
      action: 'android.intent.action.SEND',
      type: type,
      package: targetPackage,
      component: targetComponent,
      extrasString: extras,
    );
  }

  /// 设置壁纸：把一张图片 (绝对路径) 设为桌面壁纸 / 锁屏壁纸 / 同时两者。
  ///   无权限时 fallback 为用 ACTION_ATTACH_DATA 打开系统壁纸设置。
  Future<ShellResult> setWallpaper(String imagePath, {String which = 'both' /* home | lock | both */}) async {
    final p = imagePath.trim();
    if (p.isEmpty) return ShellResult(ok: false, exitCode: -1, stdout: '', stderr: 'image_path 为空');
    final f = File(p);
    if (!await f.exists()) {
      return ShellResult(ok: false, exitCode: -2, stdout: '', stderr: '图片路径不存在: $p');
    }
    // 原生 WallpaperManager 优先 (通过 channel)
    try {
      final r = await _channel.invokeMethod<String>('android_set_wallpaper', <String, dynamic>{
          'path': p,
          'which': which,
        });
        if (r != null && r.toLowerCase().contains('ok')) {
          return ShellResult(ok: true, exitCode: 0, stdout: '✅ 壁纸已设置 ($which)\n$r', stderr: '');
        }
      } catch (_) {
        // 壁纸设置失败，尝试 fallback 方法
      }
    final intentR = await sendIntent(
      action: 'android.intent.action.ATTACH_DATA',
      data: 'file://$p',
      type: 'image/*',
      extrasString: {'mimeType': 'image/*'},
    );
    return ShellResult(
      ok: intentR.ok,
      exitCode: intentR.exitCode,
      stdout: '原生 WallpaperManager 设置可能被系统拒绝，已打开系统壁纸裁剪面板请手动确认。'
          '原路径: $p  设置目标: $which\n跳转输出: ${intentR.stdout}',
      stderr: intentR.stderr,
    );
  }

  static String _keyToString(AndroidKey k) => switch (k) {
        AndroidKey.home => 'home',
        AndroidKey.back => 'back',
        AndroidKey.recent => 'recent',
        AndroidKey.volumeUp => 'volume_up',
        AndroidKey.volumeDown => 'volume_down',
        AndroidKey.power => 'power',
        AndroidKey.enter => 'enter',
        AndroidKey.delete => 'del',
      };

  /// Official android.view.KeyEvent integer keycodes used by the
  /// `input keyevent` shell command (the L2 Shizuku fallback for
  /// hardware keys when Accessibility dispatchGesture is blocked).
  static int? _keyToKeycode(AndroidKey k) => switch (k) {
        AndroidKey.home => 3,
        AndroidKey.back => 4,
        AndroidKey.recent => 187,
        AndroidKey.volumeUp => 24,
        AndroidKey.volumeDown => 25,
        AndroidKey.power => 26,
        AndroidKey.enter => 66,
        AndroidKey.delete => 67,
      };
}

/// 权限类型枚举，用于统一权限检查入口。
enum PermissionKind {
  accessibility,   // 无障碍服务
  shizuku,         // Shizuku 授权
  notification,    // 通知监听
  usageStats,      // 使用统计权限
  writeSecure,     // WRITE_SECURE_SETTINGS
  dump,            // DUMP 权限
}

enum AndroidKey {
  home,
  back,
  recent,
  volumeUp,
  volumeDown,
  power,
  enter,
  delete,
}

/// Current foreground app (package + class name) returned by [AndroidAutomationService.getTopApp].
class TopAppInfo {
  const TopAppInfo({required this.package, required this.activity});
  final String package;
  final String activity;
}

/// Result of an arbitrary shell command executed via [AndroidAutomationService.gshell].
class ShellResult {
  const ShellResult({
    required this.exitCode,
    required this.ok,
    required this.stdout,
    required this.stderr,
  });
  final int exitCode;
  final bool ok;
  final String stdout;
  final String stderr;
}
