// Device capability benchmark tests (Direction 1 Step 5).
import 'package:flutter_test/flutter_test.dart';
import 'package:openagent/data/services/device_capability_service.dart';

void main() {
  group('DeviceCapabilityService benchmark', () {
    test('detect returns non-empty backends', () async {
      final service = DeviceCapabilityService();
      final cap = await service.detect();
      expect(cap.availableBackends, isNotEmpty);
      expect(cap.availableBackends.contains(ComputeBackend.cpu), isTrue);
    });

    test('recommendedBackend prioritizes NPU', () {
      final cap = const DeviceCapability(
        hasNpu: true,
        gpuVendor: GpuVendor.adreno,
        memoryBandwidthGbps: 25,
        availableBackends: [ComputeBackend.cpu, ComputeBackend.opencl, ComputeBackend.npu],
      );
      expect(cap.recommendedBackend, ComputeBackend.npu);
    });

    test('recommendedBackend falls back to OpenCL for Adreno', () {
      final cap = const DeviceCapability(
        gpuVendor: GpuVendor.adreno,
        memoryBandwidthGbps: 25,
        availableBackends: [ComputeBackend.cpu, ComputeBackend.opencl, ComputeBackend.vulkan],
      );
      expect(cap.recommendedBackend, ComputeBackend.opencl);
    });

    test('supportsOpenCL/Vulkan', () {
      final cap = const DeviceCapability(availableBackends: [ComputeBackend.cpu, ComputeBackend.opencl]);
      expect(cap.supportsOpenCL, isTrue);
      expect(cap.supportsVulkan, isFalse);
    });

    test('setCapability overrides detect', () async {
      final service = DeviceCapabilityService();
      service.setCapability(const DeviceCapability(gpuVendor: GpuVendor.mali, memoryBandwidthGbps: 12));
      final cap = await service.detect();
      expect(cap.gpuVendor, GpuVendor.mali);
      expect(cap.memoryBandwidthGbps, 12);
    });
  });
}