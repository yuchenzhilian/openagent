// Dart-side wrapper for iOS automation via MethodChannel.
//
// Mirrors the pattern of AndroidAutomationService but for iOS. Since iOS has
// no AccessibilityService equivalent, the automation surface is limited to:
//   - Siri Shortcuts integration (donate / list / trigger / delete)
//   - URL scheme deep-linking (open URL / open App)
//   - Live Activities (start / update / end) for keep-alive UI
//
// All calls are best-effort - methods return nullable results so the Tool
// layer can translate failures into readable ToolResults for the Agent.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A shortcut invocation received from Siri / Shortcuts app.
class ShortcutInvocation {
  const ShortcutInvocation({
    required this.id,
    required this.title,
    required this.userInfo,
  });

  final String id;
  final String title;
  final Map<String, dynamic> userInfo;
}

class IosAutomationService {
  IosAutomationService._();
  static final IosAutomationService instance = IosAutomationService._();

  static const _channel = MethodChannel('com.openagent.ios.automation');

  /// Whether this service is supported on the current platform.
  bool get isSupported => defaultTargetPlatform == TargetPlatform.iOS;

  /// Stream of shortcut invocations received from Siri / Shortcuts app.
  ///
  /// When the user triggers a donated shortcut via Siri, the native
  /// AppDelegate sends a `shortcut_invoked` method call which this
  /// service forwards to this stream as a [ShortcutInvocation].
  Stream<ShortcutInvocation> get shortcutInvocations =>
      _shortcutController.stream;
  final _shortcutController = StreamController<ShortcutInvocation>.broadcast();

  /// Call once at app startup (e.g. in initState) to begin listening for
  /// incoming `shortcut_invoked` callbacks from the native side.
  void startListening() {
    if (!isSupported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shortcut_invoked') {
        final args = call.arguments as Map? ?? {};
        _shortcutController.add(ShortcutInvocation(
          id: args['id'] as String? ?? '',
          title: args['title'] as String? ?? '',
          userInfo: Map<String, dynamic>.from(args['userInfo'] as Map? ?? {}),
        ));
      }
      return null;
    });
  }

  /// Whether a Live Activity is currently active.
  bool _activityActive = false;
  bool get isActivityActive => _activityActive;

  // ---- Shortcuts ----------------------------------------------------------

  /// Register (donate) a Siri Shortcut so it appears in the Shortcuts app
  /// and can be triggered by voice via Siri.
  ///
  /// [id] must be unique within the app. [title] is the user-visible name.
  /// [description] is shown in the Shortcuts app. [phrase] is the suggested
  /// Siri voice phrase (e.g. "用 OpenAgent 搜索").
  Future<bool> donateShortcut({
    required String id,
    required String title,
    required String description,
    String? phrase,
  }) async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('shortcut_donate', {
        'id': id,
        'title': title,
        'description': description,
        if (phrase != null) 'phrase': phrase,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// List all previously donated Shortcuts.
  Future<List<Map<String, dynamic>>> listShortcuts() async {
    if (!isSupported) return const [];
    try {
      final result = await _channel.invokeMethod<List>('shortcut_list');
      if (result == null) return const [];
      return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on PlatformException {
      return const [];
    }
  }

  /// Trigger a system-level action via URL scheme (e.g. tel:, sms:, maps:).
  /// This is the iOS equivalent of Android's `am start` / `sendIntent`.
  Future<bool> triggerShortcut(String url) async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('shortcut_trigger', {
        'url': url,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Delete a previously donated Shortcut by id.
  Future<bool> deleteShortcut(String id) async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('shortcut_delete', {
        'id': id,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  // ---- URL / App opening --------------------------------------------------

  /// Open a URL (http/https/deeplink/custom-scheme) via UIApplication.shared.open.
  Future<bool> openUrl(String url) async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('open_url', {
        'url': url,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Open a third-party app via its URL scheme (e.g. "weixin://", "snssdk1128://").
  /// Returns false if the app is not installed or the scheme is invalid.
  Future<bool> openApp(String scheme) async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('open_app', {
        'scheme': scheme,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  // ---- Live Activities ----------------------------------------------------

  /// Start a Live Activity for Agent keep-alive. The activity appears in the
  /// Lock Screen and Dynamic Island while the Agent is running.
  ///
  /// [title] is the activity title (e.g. "Agent 运行中").
  /// [content] is the status text (e.g. "正在思考...").
  Future<bool> startActivity({
    required String title,
    required String content,
  }) async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('live_activity_start', {
        'title': title,
        'content': content,
      });
      if (result == true) _activityActive = true;
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Update the Live Activity content (e.g. "正在执行工具: calculator").
  Future<bool> updateActivity(String content) async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('live_activity_update', {
        'content': content,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// End the Live Activity (call when the Agent finishes its task).
  Future<bool> endActivity() async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('live_activity_end');
      if (result == true) _activityActive = false;
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Dispose resources (call in app dispose).
  void dispose() {
    _shortcutController.close();
  }
}
