/// Device state monitoring service.
///
/// Periodically samples device metrics (battery, temperature, memory, CPU
/// frequency) and emits events when thresholds are crossed.  Used by
/// [InferenceScheduler] to adapt inference parameters to the current
/// device state.
///
/// Priority: P0 (part of System-Level Optimization).

import 'dart:async';
import 'dart:io' show Platform;

/// Thermal levels for decision-making.
enum ThermalLevel { normal, warm, hot, critical }

/// Device state snapshot.
class DeviceState {
  final int batteryPercent;
  final bool isCharging;
  final double temperatureCelsius;
  final bool screenOn;
  final bool userPresent;
  final int availableMemoryMb;
  final int cpuFrequencyMhz;
  final ThermalLevel thermalLevel;

  const DeviceState({
    this.batteryPercent = 100,
    this.isCharging = true,
    this.temperatureCelsius = 30.0,
    this.screenOn = true,
    this.userPresent = true,
    this.availableMemoryMb = 2048,
    this.cpuFrequencyMhz = 2000,
    this.thermalLevel = ThermalLevel.normal,
  });

  /// Whether the device is in a power-saving state.
  bool get isLowPower => batteryPercent < 20 && !isCharging;

  /// Whether the device is overheating.
  bool get isOverheating =>
      thermalLevel == ThermalLevel.hot || thermalLevel == ThermalLevel.critical;

  /// Whether high-performance inference is appropriate.
  bool get canUseHighPerformance =>
      isCharging && !isOverheating && thermalLevel == ThermalLevel.normal;
}

/// Monitors device state at a configurable interval.
class DeviceMonitorService {
  DeviceMonitorService({this.sampleIntervalSec = 30});

  final int sampleIntervalSec;

  StreamController<DeviceState>? _controller;
  Timer? _timer;
  DeviceState _lastState = const DeviceState();

  /// Stream of device state changes.  Emits only when the state changes
  /// significantly (battery Δ > 5%, temperature Δ > 2°C, or thermal level
  /// change).
  Stream<DeviceState> get stateStream {
    _controller ??= StreamController<DeviceState>.broadcast();
    return _controller!.stream;
  }

  /// Current (last sampled) device state.
  DeviceState get currentState => _lastState;

  /// Start periodic sampling.
  void start() {
    _timer?.cancel();
    _sample(); // Immediate first sample.
    _timer =
        Timer.periodic(Duration(seconds: sampleIntervalSec), (_) => _sample());
  }

  /// Stop periodic sampling.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Force an immediate sample.
  Future<void> sampleNow() async => _sample();

  void _sample() {
    // On real devices this would read from /sys/class/power_supply/,
    // /sys/class/thermal/, /proc/meminfo, etc.  For now we simulate
    // with reasonable defaults.
    final newState = _readDeviceState();
    if (_hasSignificantChange(newState, _lastState)) {
      _lastState = newState;
      _controller?.add(newState);
    }
  }

  /// Read actual device state.  Falls back to defaults on non-Android.
  DeviceState _readDeviceState() {
    if (!Platform.isAndroid) {
      return const DeviceState();
    }

    // In production, these would be read from:
    // - Battery: /sys/class/power_supply/battery/capacity
    // - Temperature: /sys/class/thermal/thermal_zone0/temp
    // - Memory: /proc/meminfo (MemAvailable)
    // - CPU: /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq
    // - Screen: dumpsys power | grep mScreenOn
    try {
      // TODO: implement real device file reads via MethodChannel or shell.
      return const DeviceState();
    } catch (_) {
      return const DeviceState();
    }
  }

  /// Whether the state change is significant enough to emit.
  bool _hasSignificantChange(DeviceState a, DeviceState b) {
    if (a.thermalLevel != b.thermalLevel) return true;
    if ((a.batteryPercent - b.batteryPercent).abs() > 5) return true;
    if ((a.temperatureCelsius - b.temperatureCelsius).abs() > 2.0) return true;
    if (a.isCharging != b.isCharging) return true;
    return false;
  }

  /// Dispose resources.
  void dispose() {
    stop();
    _controller?.close();
  }
}
