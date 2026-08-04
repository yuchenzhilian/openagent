// Tests for Phase 4: Heterogeneous compute, Quantization, MCP security.
import 'package:flutter_test/flutter_test.dart';
import 'package:openagent/data/services/device_capability_service.dart';
import 'package:openagent/data/services/quantization_benchmark.dart';
import 'package:openagent/data/services/auto_quantization.dart';
import 'package:openagent/agent/mcp/mcp_security.dart';
import 'package:openagent/agent/mcp/mcp_sandbox.dart';
import 'package:openagent/agent/mcp/mcp_discovery.dart';

void main() {
  group('DeviceCapabilityService', () {
    test('detect', () async {
      final s = DeviceCapabilityService();
      final c = await s.detect();
      expect(c.availableBackends, isNotEmpty);
    });
    test('setCapability', () {
      final s = DeviceCapabilityService();
      s.setCapability(const DeviceCapability(
          gpuVendor: GpuVendor.adreno,
          hasNpu: true,
          availableBackends: [ComputeBackend.cpu, ComputeBackend.npu]));
      expect(s.capability.recommendedBackend, ComputeBackend.npu);
    });
    test('recommendedBackend CPU', () {
      expect(
          const DeviceCapability(availableBackends: [ComputeBackend.cpu])
              .recommendedBackend,
          ComputeBackend.cpu);
    });
  });

  group('QuantizationBenchmark', () {
    test('addPresets', () {
      final b = QuantizationBenchmark();
      b.addPresets();
      expect(b.configs.length, 4);
    });
    test('bestConfig null', () {
      expect(QuantizationBenchmark().bestConfig(), isNull);
    });
  });

  group('AutoQuantization', () {
    test('6GB+', () {
      expect(
          AutoQuantization.selectForDevice(6144).languageBits, QuantBits.fp16);
    });
    test('4GB', () {
      expect(
          AutoQuantization.selectForDevice(4096).languageBits, QuantBits.int8);
    });
    test('<4GB', () {
      expect(
          AutoQuantization.selectForDevice(3072).languageBits, QuantBits.int4);
    });
    test('estimateModelSizeMb', () {
      expect(
          AutoQuantization.estimateModelSizeMb(
              4000,
              const QuantConfig(
                  visionBits: QuantBits.int4, languageBits: QuantBits.int4)),
          lessThan(4000));
    });
  });

  group('McpCapability', () {
    test('allowsTool empty', () {
      expect(const McpCapability().allowsTool('any'), isTrue);
    });
    test('allowsTool restricted', () {
      expect(const McpCapability(allowedTools: {'a'}).allowsTool('b'), isFalse);
    });
    test('merge', () {
      final m =
          const McpCapability(allowedTools: {'a'}, allowNetworkAccess: true)
              .merge(const McpCapability(
                  allowedTools: {'b'}, allowFileSystemAccess: true));
      expect(m.allowedTools, containsAll(['a', 'b']));
    });
  });

  group('McpSecurityManager', () {
    test('checkAndAcquire', () {
      final m = McpSecurityManager();
      m.registerServer('s1', const McpCapability(allowedTools: {'calc'}));
      expect(m.checkAndAcquire('s1', 'calc'), isTrue);
      m.releaseCall('s1');
    });
    test('denies unknown', () {
      expect(McpSecurityManager().checkAndAcquire('unknown', 'any'), isFalse);
    });
    test('concurrency limit', () {
      final m = McpSecurityManager();
      m.registerServer('s1',
          const McpCapability(allowedTools: {'t1'}, maxConcurrentCalls: 1));
      expect(m.checkAndAcquire('s1', 't1'), isTrue);
      expect(m.checkAndAcquire('s1', 't1'), isFalse);
      m.releaseCall('s1');
      expect(m.checkAndAcquire('s1', 't1'), isTrue);
    });
  });

  group('McpSandbox', () {
    test('canRead', () {
      final s =
          McpSandbox(config: const SandboxConfig(allowedReadPaths: ['/tmp']));
      expect(s.canRead('/tmp/f'), isTrue);
      expect(s.canRead('/etc/p'), isFalse);
    });
    test('canWrite', () {
      final s =
          McpSandbox(config: const SandboxConfig(allowedWritePaths: ['/tmp']));
      expect(s.canWrite('/tmp/f'), isTrue);
    });
  });

  group('McpDiscovery', () {
    test('start/stop', () {
      final d = McpDiscovery();
      expect(() => d.startScan(), returnsNormally);
      expect(() => d.stopScan(), returnsNormally);
      d.dispose();
    });
    test('servers empty', () {
      final d = McpDiscovery();
      expect(d.servers, isEmpty);
      d.dispose();
    });
  });
}
