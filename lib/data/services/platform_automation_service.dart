// Platform automation service abstraction layer.
//
// Design principle: platform differences are abstracted here, not scattered
// in UI code. The interface is intentionally narrow — only the `isSupported`
// gate is shared. Platform-specific capabilities are exposed via separate
// capability interfaces (LiveActivityHost, ShortcutHost) that services opt
// into, so chat_page.dart never holds concrete platform types.

/// Core contract for any platform automation service.
///
/// Both [AndroidAutomationService] and [IosAutomationService] implement this.
/// UI code should depend on this interface (or a List of it) rather than
/// concrete platform types.
abstract class PlatformAutomationService {
  /// Whether this service is supported on the current platform.
  bool get isSupported;

  /// Human-readable platform name for display / logging.
  String get platformName;
}

/// Capability interface for platforms that support Live Activities (iOS 16.1+).
///
/// Services that implement this can start/update/end Live Activities.
abstract class LiveActivityHost {
  bool get isActivityActive;

  Future<bool> startActivity({required String title, required String content});
  Future<bool> updateActivity(String content);
  Future<bool> endActivity();
}

/// Capability interface for platforms that support Siri Shortcuts.
///
/// Services that implement this can donate/list/trigger/delete shortcuts
/// and receive shortcut invocations from the system.
abstract class ShortcutHost {
  Future<bool> donateShortcut({
    required String id,
    required String title,
    required String description,
    String? phrase,
  });

  Future<List<Map<String, dynamic>>> listShortcuts();
  Future<bool> triggerShortcut(String url);
  Future<bool> deleteShortcut(String id);

  /// Start listening for incoming shortcut invocations from the system.
  void startListening();
}
