// Tests for Direction 10: Power & thermal management.
import 'package:flutter_test/flutter_test.dart';
import 'package:openagent/data/services/device_monitor_service.dart';
import 'package:openagent/agent/inference_scheduler.dart';

void main() {
  group('DeviceState', () {
    test('isLowPower', () { expect(DeviceState(batteryPercent: 15, isCharging: false).isLowPower, isTrue); });
    test('isLowPower false when charging', () { expect(DeviceState(batteryPercent: 15, isCharging: true).isLowPower, isFalse); });
    test('isOverheating', () { expect(DeviceState(thermalLevel: ThermalLevel.hot).isOverheating, isTrue); });
    test('canUseHighPerformance', () { expect(DeviceState(isCharging: true, thermalLevel: ThermalLevel.normal).canUseHighPerformance, isTrue); });
  });

  group('InferenceProfile', () {
    test('normal', () { expect(InferenceProfile.normal.maxTokens, 1024); });
    test('powerSaving', () { expect(InferenceProfile.powerSaving.modelId, 'Qwen3-0.6B-MNN'); });
    test('thermalThrottled', () { expect(InferenceProfile.thermalThrottled.maxTokens, 256); });
    test('highPerformance', () { expect(InferenceProfile.highPerformance.maxTokens, 2048); });
  });

  group('InferenceScheduler', () {
    test('selectProfile', () {
      final s = InferenceScheduler();
      expect(s.selectProfile(DeviceState(thermalLevel: ThermalLevel.hot)).modelId, 'Qwen3-0.6B-MNN');
      expect(s.selectProfile(DeviceState(batteryPercent: 15, isCharging: false)).modelId, 'Qwen3-0.6B-MNN');
      expect(s.selectProfile(DeviceState(isCharging: true, thermalLevel: ThermalLevel.normal)).modelId, 'Qwen2.5-4B-MNN');
    });
  });

  group('DeviceMonitorService', () {
    test('start/stop', () { final m = DeviceMonitorService(sampleIntervalSec: 60); expect(() => m.start(), returnsNormally); expect(() => m.stop(), returnsNormally); m.dispose(); });
  });
}