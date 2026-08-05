/// Adaptive inference scheduler.
///
/// Selects the appropriate inference profile based on current device state
/// (battery, temperature, thermal level).  Dynamically adjusts model choice,
/// token limits, and feature flags to balance performance against power
/// consumption and thermal constraints.
///
/// Priority: P0 (part of System-Level Optimization).

import 'dart:async';

import 'agent_runtime.dart' show ToolResult;
import '../data/services/device_monitor_service.dart';

/// Inference profile describing the operating parameters for a given device
/// state.
class InferenceProfile {
  final String modelId;
  final int maxTokens;
  final int maxSteps;
  final bool enableVlm;
  final bool enableWebSearch;
  final Duration idleTimeout;

  const InferenceProfile({
    required this.modelId,
    this.maxTokens = 1024,
    this.maxSteps = 20,
    this.enableVlm = true,
    this.enableWebSearch = true,
    this.idleTimeout = const Duration(minutes: 5),
  });

  /// High-performance profile — charging, cool device.
  static const highPerformance = InferenceProfile(
    modelId: 'Qwen2.5-4B-MNN',
    maxTokens: 2048,
    maxSteps: 50,
    enableVlm: true,
    enableWebSearch: true,
    idleTimeout: Duration(minutes: 10),
  );

  /// Normal profile — acceptable battery and temperature.
  static const normal = InferenceProfile(
    modelId: 'Qwen2.5-4B-MNN',
    maxTokens: 1024,
    maxSteps: 20,
    enableVlm: true,
    enableWebSearch: true,
    idleTimeout: Duration(minutes: 5),
  );

  /// Power-saving profile — low battery, not charging.
  static const powerSaving = InferenceProfile(
    modelId: 'Qwen3-0.6B-MNN',
    maxTokens: 512,
    maxSteps: 10,
    enableVlm: false,
    enableWebSearch: false,
    idleTimeout: Duration(minutes: 2),
  );

  /// Thermal-throttled profile - device is overheating.
  static const thermalThrottled = InferenceProfile(
    modelId: 'Qwen3-0.6B-MNN',
    maxTokens: 256,
    maxSteps: 5,
    enableVlm: false,
    enableWebSearch: false,
    idleTimeout: Duration(minutes: 1),
  );

  /// Ultra-lite profile - very low-end devices (<4GB RAM).
  /// Uses the smallest model, minimal tokens, and disables all heavy features.
  static const ultraLite = InferenceProfile(
    modelId: 'Qwen3-0.6B-MNN',
    maxTokens: 256,
    maxSteps: 3,
    enableVlm: false,
    enableWebSearch: false,
    idleTimeout: Duration(minutes: 1),
  );
}

/// Callback types for scheduler events.
typedef ProfileChangeCallback = void Function(InferenceProfile profile);
typedef InferenceRequestCallback = Future<ToolResult> Function(
    String modelId, String prompt, InferenceProfile profile);

/// Adaptive inference scheduler that selects profiles based on device state.
class InferenceScheduler {
  InferenceScheduler({DeviceMonitorService? monitor})
      : _monitor = monitor ?? DeviceMonitorService();

  final DeviceMonitorService _monitor;
  InferenceProfile _currentProfile = InferenceProfile.normal;
  final List<ProfileChangeCallback> _onProfileChange = [];

  /// Current active profile.
  InferenceProfile get currentProfile => _currentProfile;

  /// Start monitoring and adaptive scheduling.
  void start() {
    _monitor.start();
    _monitor.stateStream.listen(_onDeviceStateChanged);
  }

  /// Stop monitoring.
  void stop() {
    _monitor.stop();
  }

  /// Register a callback for profile changes.
  void onProfileChange(ProfileChangeCallback callback) {
    _onProfileChange.add(callback);
  }

  /// Select the appropriate profile for the current device state.
  InferenceProfile selectProfile(DeviceState state) {
    if (state.isOverheating) {
      return InferenceProfile.thermalThrottled;
    }
    // Ultra-lite for very low memory devices (<2GB available).
    if (state.availableMemoryMb < 2048) {
      return InferenceProfile.ultraLite;
    }
    if (state.isLowPower) {
      return InferenceProfile.powerSaving;
    }
    if (state.canUseHighPerformance) {
      return InferenceProfile.highPerformance;
    }
    return InferenceProfile.normal;
  }

  void _onDeviceStateChanged(DeviceState state) {
    final newProfile = selectProfile(state);
    if (newProfile != _currentProfile) {
      _currentProfile = newProfile;
      for (final cb in _onProfileChange) {
        cb(newProfile);
      }
    }
  }

  /// Dispose resources.
  void dispose() {
    stop();
    _monitor.dispose();
  }
}
