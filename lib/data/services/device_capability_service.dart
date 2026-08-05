/// Device capability detection service.
///
/// Uses [DeviceProbeService] to read real hardware metrics (memory, CPU,
/// GPU vendor, thermal state) from the native layer and maps them to a
/// [DeviceCapability] that drives backend selection and model recommendation.
import 'device_probe_service.dart';

enum GpuVendor { adreno, mali, apple, powerVr, unknown }

enum ComputeBackend { cpu, opencl, vulkan, metal, npu }

class DeviceCapability {
  final GpuVendor gpuVendor;
  final String gpuModel;
  final double memoryBandwidthGbps;
  final bool hasNpu;
  final String npuModel;
  final List<ComputeBackend> availableBackends;
  final double thermalLevel;
  final int totalMemoryMb;

  /// Number of CPU "big" cores (high-frequency cores). Used to set the
  /// optimal MNN thread_num - matching big cores avoids scheduling overhead
  /// on efficiency cores.
  final int bigCoreCount;

  /// Total CPU core count (big + small).
  final int cpuCoreCount;

  /// Max CPU frequency in MHz (0 if unavailable).
  final int cpuMaxFreqMhz;

  const DeviceCapability({
    this.gpuVendor = GpuVendor.unknown,
    this.gpuModel = '',
    this.memoryBandwidthGbps = 0,
    this.hasNpu = false,
    this.npuModel = '',
    this.availableBackends = const [ComputeBackend.cpu],
    this.thermalLevel = 0,
    this.totalMemoryMb = 4096,
    this.bigCoreCount = 4,
    this.cpuCoreCount = 8,
    this.cpuMaxFreqMhz = 2000,
  });

  bool get supportsOpenCL => availableBackends.contains(ComputeBackend.opencl);
  bool get supportsVulkan => availableBackends.contains(ComputeBackend.vulkan);
  bool get supportsMetal => availableBackends.contains(ComputeBackend.metal);

  /// Recommend the best compute backend for MNN inference.
  /// On Android: Adreno GPUs have good OpenCL support; Mali can use OpenCL
  /// as well but performance varies. CPU is always the safe fallback.
  ComputeBackend get recommendedBackend {
    if (hasNpu) return ComputeBackend.npu;
    if (supportsMetal) return ComputeBackend.metal;
    // Adreno GPUs (Qualcomm) have well-optimised OpenCL kernels in MNN.
    if (gpuVendor == GpuVendor.adreno && supportsOpenCL) {
      return ComputeBackend.opencl;
    }
    // Mali GPUs (ARM/Exynos/MediaTek) also support OpenCL in MNN.
    if (gpuVendor == GpuVendor.mali && supportsOpenCL) {
      return ComputeBackend.opencl;
    }
    if (gpuVendor == GpuVendor.mali && supportsVulkan) {
      return ComputeBackend.vulkan;
    }
    return ComputeBackend.cpu;
  }

  /// Recommend a model based on available memory.
  /// Low-end devices get the smallest model; flagship devices can run 4B.
  static String recommendModel(int totalMemoryMb) {
    if (totalMemoryMb >= 8192) return 'Qwen3-4B-MNN';
    if (totalMemoryMb >= 4096) return 'Qwen3-1.7B-MNN';
    return 'Qwen3-0.6B-MNN';
  }
}

class DeviceCapabilityService {
  DeviceCapability _capability = const DeviceCapability();
  bool _initialized = false;
  DeviceCapability get capability => _capability;

  Future<DeviceCapability> detect() async {
    if (_initialized) return _capability;

    // Use the DeviceProbeService to get real hardware data.
    final probe = await DeviceProbeService().probe();

    // Map GPU vendor string to enum.
    final gpuVendor = _mapGpuVendor(probe.gpuVendor);

    // Determine available backends based on GPU and platform.
    final backends = <ComputeBackend>[ComputeBackend.cpu];
    if (gpuVendor == GpuVendor.adreno || gpuVendor == GpuVendor.mali) {
      backends.add(ComputeBackend.opencl);
    }
    if (gpuVendor == GpuVendor.mali) {
      backends.add(ComputeBackend.vulkan);
    }

    // Estimate memory bandwidth from GPU vendor and CPU frequency.
    double bandwidth = 15.0; // conservative default
    if (gpuVendor == GpuVendor.adreno) {
      bandwidth = 25.0; // Adreno GPUs typically have good bandwidth
    } else if (gpuVendor == GpuVendor.mali) {
      bandwidth = 20.0;
    }

    _capability = DeviceCapability(
      gpuVendor: gpuVendor,
      gpuModel: probe.gpuModel,
      memoryBandwidthGbps: bandwidth,
      hasNpu: false,
      availableBackends: backends,
      thermalLevel: probe.thermalStatus.toDouble(),
      totalMemoryMb: probe.totalMemoryMb,
      bigCoreCount: probe.cpuBigCoreCount,
      cpuCoreCount: probe.cpuCoreCount,
      cpuMaxFreqMhz: probe.cpuMaxFreqMhz,
    );
    _initialized = true;
    return _capability;
  }

  GpuVendor _mapGpuVendor(String vendor) {
    switch (vendor.toLowerCase()) {
      case 'adreno':
        return GpuVendor.adreno;
      case 'mali':
        return GpuVendor.mali;
      case 'powervr':
        return GpuVendor.powerVr;
      case 'apple':
        return GpuVendor.apple;
      default:
        return GpuVendor.unknown;
    }
  }

  void setCapability(DeviceCapability capability) {
    _capability = capability;
    _initialized = true;
  }
}
