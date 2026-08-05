// Dynamic MNN backend configuration builder.
//
// Generates runtime config overrides for MNN-LLM based on the detected
// device capabilities. These overrides are passed via mnn_llm_set_config
// and include:
//   - backend_type: cpu vs opencl (GPU acceleration)
//   - thread_num: matched to big core count for optimal CPU utilisation
//   - precision: "low" (fp16) for all devices
//   - memory: "low" (mmap) for devices with <4GB RAM
//   - sampler_type: "mixed" with optimised parameters

import 'device_capability_service.dart';

class MnnConfigBuilder {
  MnnConfigBuilder._();

  /// Build MNN runtime config overrides based on device capability.
  ///
  /// The returned map should be merged into the sampling config before
  /// calling [MnnLlmSession.setConfig].
  static Map<String, dynamic> buildBackendConfig(DeviceCapability cap) {
    final config = <String, dynamic>{};

    // 1. Backend selection: prefer GPU (OpenCL) on supported devices.
    final backend = cap.recommendedBackend;
    if (backend == ComputeBackend.opencl) {
      config['backend_type'] = 'opencl';
      config['backend_config'] = {
        'backend_type': 'opencl',
        'power': 'normal',
        'memory': 'normal',
        'precision': 'normal',
      };
    } else if (backend == ComputeBackend.vulkan) {
      config['backend_type'] = 'vulkan';
    } else {
      config['backend_type'] = 'cpu';
    }

    // 2. Thread count: match big core count (not total cores).
    //    Using more threads than big cores causes scheduling overhead on
    //    efficiency cores with no throughput benefit.
    config['thread_num'] = cap.bigCoreCount.clamp(1, 8);

    // 3. Precision: "low" means fp16 - always use on mobile for speed.
    config['precision'] = 'low';

    // 4. Memory mode: "low" enables mmap to reduce dirty memory.
    //    Critical for low-end devices with <4GB RAM. On high-end devices
    //    "normal" is slightly faster (no page fault overhead).
    config['memory'] = cap.totalMemoryMb < 4096 ? 'low' : 'normal';

    // 5. Sampler: "mixed" sampler with optimised chain.
    //    Reducing topK from 40 to 20 cuts sampling computation ~50%.
    config['sampler_type'] = 'mixed';
    config['mixed_samplers'] = ['penalty', 'topK', 'topP', 'temperature'];

    return config;
  }

  /// Build a warm-up config with minimal max_new_tokens for kernel
  /// compilation. Used after model load to trigger OpenCL cache generation.
  static Map<String, dynamic> buildWarmupConfig(DeviceCapability cap) {
    final config = buildBackendConfig(cap);
    config['max_new_tokens'] = 1;
    config['temperature'] = 0.0; // deterministic, fastest sampling
    return config;
  }
}
