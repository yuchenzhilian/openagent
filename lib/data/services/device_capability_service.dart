/// Device capability detection service.
enum GpuVendor { adreno, mali, apple, powerVr, unknown }
enum ComputeBackend { cpu, opencl, vulkan, metal, npu }

class DeviceCapability {
  final GpuVendor gpuVendor; final String gpuModel; final double memoryBandwidthGbps;
  final bool hasNpu; final String npuModel; final List<ComputeBackend> availableBackends;
  final double thermalLevel; final int totalMemoryMb;
  const DeviceCapability({this.gpuVendor = GpuVendor.unknown, this.gpuModel = '', this.memoryBandwidthGbps = 0, this.hasNpu = false, this.npuModel = '', this.availableBackends = const [ComputeBackend.cpu], this.thermalLevel = 0, this.totalMemoryMb = 4096});
  bool get supportsOpenCL => availableBackends.contains(ComputeBackend.opencl);
  bool get supportsVulkan => availableBackends.contains(ComputeBackend.vulkan);
  bool get supportsMetal => availableBackends.contains(ComputeBackend.metal);
  ComputeBackend get recommendedBackend { if (hasNpu) return ComputeBackend.npu; if (supportsMetal) return ComputeBackend.metal; if (gpuVendor == GpuVendor.adreno && memoryBandwidthGbps > 20) return ComputeBackend.opencl; if (gpuVendor == GpuVendor.mali && supportsVulkan) return ComputeBackend.vulkan; return ComputeBackend.cpu; }
}

class DeviceCapabilityService {
  DeviceCapability _capability = const DeviceCapability(); bool _initialized = false;
  DeviceCapability get capability => _capability;

  Future<DeviceCapability> detect() async {
    if (_initialized) return _capability;
    _capability = const DeviceCapability(gpuVendor: GpuVendor.unknown, memoryBandwidthGbps: 15, availableBackends: [ComputeBackend.cpu, ComputeBackend.opencl, ComputeBackend.vulkan], totalMemoryMb: 6144);
    _initialized = true; return _capability;
  }

  void setCapability(DeviceCapability capability) { _capability = capability; _initialized = true; }
}