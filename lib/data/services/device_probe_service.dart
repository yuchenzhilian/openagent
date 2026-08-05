// Dart-side wrapper for the DeviceProbe MethodChannel.
//
// Calls the native Kotlin DeviceProbe to read real device hardware metrics
// (memory, CPU cores/frequency, GPU vendor, battery, thermal state) and
// provides a typed [DeviceProbeInfo] result.
//
// Falls back to conservative defaults on non-Android platforms or when the
// MethodChannel is unavailable (e.g. in unit tests).

import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';

/// Snapshot of real device hardware metrics from the native layer.
class DeviceProbeInfo {
  final int totalMemoryMb;
  final int availableMemoryMb;
  final bool lowMemory;
  final int cpuCoreCount;
  final int cpuBigCoreCount;
  final int cpuMaxFreqMhz;
  final String gpuVendor; // adreno / mali / powervr / unknown
  final String gpuModel;
  final int batteryPercent;
  final bool isCharging;
  final int thermalStatus; // PowerManager.THERMAL_STATUS_*
  final double temperatureCelsius;
  final int sdkInt;
  final String abi;

  const DeviceProbeInfo({
    this.totalMemoryMb = 4096,
    this.availableMemoryMb = 2048,
    this.lowMemory = false,
    this.cpuCoreCount = 8,
    this.cpuBigCoreCount = 4,
    this.cpuMaxFreqMhz = 2000,
    this.gpuVendor = 'unknown',
    this.gpuModel = 'unknown',
    this.batteryPercent = 100,
    this.isCharging = true,
    this.thermalStatus = 0,
    this.temperatureCelsius = 30.0,
    this.sdkInt = 28,
    this.abi = 'arm64-v8a',
  });

  factory DeviceProbeInfo.fromJson(Map<String, dynamic> j) => DeviceProbeInfo(
        totalMemoryMb: (j['total_memory_mb'] as num?)?.toInt() ?? 4096,
        availableMemoryMb: (j['available_memory_mb'] as num?)?.toInt() ?? 2048,
        lowMemory: j['low_memory'] as bool? ?? false,
        cpuCoreCount: (j['cpu_core_count'] as num?)?.toInt() ?? 8,
        cpuBigCoreCount: (j['cpu_big_core_count'] as num?)?.toInt() ?? 4,
        cpuMaxFreqMhz: (j['cpu_max_freq_mhz'] as num?)?.toInt() ?? 2000,
        gpuVendor: (j['gpu_vendor'] as String?) ?? 'unknown',
        gpuModel: (j['gpu_model'] as String?) ?? 'unknown',
        batteryPercent: (j['battery_percent'] as num?)?.toInt() ?? 100,
        isCharging: j['is_charging'] as bool? ?? true,
        thermalStatus: (j['thermal_status'] as num?)?.toInt() ?? 0,
        temperatureCelsius:
            (j['temperature_celsius'] as num?)?.toDouble() ?? 30.0,
        sdkInt: (j['sdk_int'] as num?)?.toInt() ?? 28,
        abi: (j['abi'] as String?) ?? 'arm64-v8a',
      );

  /// Whether the GPU is Adreno (Qualcomm) — good OpenCL support.
  bool get isAdreno => gpuVendor == 'adreno';

  /// Whether the GPU is Mali (ARM) — OpenCL support varies.
  bool get isMali => gpuVendor == 'mali';

  /// Thermal status: 0 = none, 1-6 = mild to severe throttling.
  bool get isOverheating => thermalStatus >= 3;

  /// Low power: battery < 20% and not charging.
  bool get isLowPower => batteryPercent < 20 && !isCharging;
}

/// Service that calls the native DeviceProbe via MethodChannel.
class DeviceProbeService {
  static const _channel = MethodChannel('com.openagent.openagent/device_probe');

  static DeviceProbeService? _instance;
  DeviceProbeService._();
  factory DeviceProbeService() => _instance ??= DeviceProbeService._();

  DeviceProbeInfo? _cached;
  bool _probed = false;

  /// Synchronous access to the last cached probe result.
  /// Returns null if [probe] has not been called yet.
  DeviceProbeInfo? get cachedInfo => _cached;

  /// Probe the device once and cache the result. Subsequent calls return
  /// the cache unless [force] is true.
  Future<DeviceProbeInfo> probe({bool force = false}) async {
    if (_probed && !force && _cached != null) return _cached!;

    if (!Platform.isAndroid) {
      _cached = const DeviceProbeInfo();
      _probed = true;
      return _cached!;
    }

    try {
      final raw = await _channel.invokeMethod<String>('probe');
      if (raw != null && raw.isNotEmpty) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _cached = DeviceProbeInfo.fromJson(json);
      } else {
        _cached = const DeviceProbeInfo();
      }
    } catch (_) {
      // MethodChannel not available (tests, desktop) — use defaults.
      _cached = const DeviceProbeInfo();
    }

    _probed = true;
    return _cached!;
  }

  /// Clear the cache so the next [probe] call hits the native layer again.
  void invalidate() {
    _cached = null;
    _probed = false;
  }
}
