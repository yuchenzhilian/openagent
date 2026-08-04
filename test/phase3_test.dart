// Tests for Phase 3: KV Cache, Skill synthesis, VLM UI control.
import 'package:flutter_test/flutter_test.dart';
import 'package:openagent/agent/kv_cache/h2o_strategy.dart';
import 'package:openagent/agent/kv_cache/sliding_window.dart';
import 'package:openagent/agent/skills/skill_trace_recorder.dart';
import 'package:openagent/agent/skills/skill_synthesizer.dart';
import 'package:openagent/agent/skills/skill_evolution.dart';
import 'package:openagent/agent/rpa/vision_grounding.dart';
import 'package:openagent/agent/rpa/resolution_adapter.dart';
import 'package:openagent/agent/rpa/hybrid_localizer.dart';

void main() {
  group('H2OStrategy', () {
    test('keeps tokens', () {
      final s = H2OStrategy(
          config: const H2OConfig(
              checkInterval: 1, maxHeavyHitters: 3, slidingWindowSize: 2));
      expect(s.selectTokensToKeep([0.9, 0.1, 0.8], 3), isNotEmpty);
    });
    test('reset', () {
      final s = H2OStrategy();
      s.reset();
      expect(() => s.selectTokensToKeep([0.5], 1), returnsNormally);
    });
  });

  group('SlidingWindowCache', () {
    test('under limit', () {
      final c = SlidingWindowCache(windowSize: 1000);
      expect(c.add('hello').toSummarize, '');
    });
    test('summary when over limit', () {
      final c = SlidingWindowCache(windowSize: 10);
      c.add('hello world this is a long text');
      expect(c.summaries, isNotEmpty);
    });
    test('reset', () {
      final c = SlidingWindowCache();
      c.add('test');
      c.reset();
      expect(c.windowContent, '');
    });
  });

  group('SkillTraceRecorder', () {
    test('record and stop', () {
      final r = SkillTraceRecorder();
      r.startTrace(
          name: 't',
          context: const TraceContext(appPackage: 'com.t', screenName: 'm'));
      r.recordStep(const TraceStep(
          toolName: 'click',
          args: {},
          timestamp: 1,
          result: 'ok',
          durationMs: 100));
      expect(r.stopTrace()!.steps.length, 1);
    });
    test('findTraces', () {
      final r = SkillTraceRecorder();
      r.startTrace(
          name: 'open_wifi',
          context: const TraceContext(appPackage: 'com.t', screenName: 'm'));
      r.stopTrace();
      r.startTrace(
          name: 'close_wifi',
          context: const TraceContext(appPackage: 'com.t', screenName: 'm'));
      r.stopTrace();
      expect(r.findTraces('wifi').length, 2);
    });
  });

  group('SkillSynthesizer', () {
    test('needs 2+ traces', () {
      expect(
          SkillSynthesizer().synthesize('t', [
            ExecutionTrace(
                id: '1',
                name: 't',
                context: const TraceContext(appPackage: 'c', screenName: 's'),
                steps: [])
          ]),
          isNull);
    });
  });

  group('SkillEvolution', () {
    test('addVersion', () {
      final e = SkillEvolution();
      e.addVersion('s1',
          SkillVersion(version: '1.0', createdAt: DateTime.now(), steps: []));
      expect(e.getCurrentVersion('s1')!.version, '1.0');
    });
    test('rollback', () {
      final e = SkillEvolution();
      e.addVersion('s1',
          SkillVersion(version: '1.0', createdAt: DateTime.now(), steps: []));
      e.addVersion('s1',
          SkillVersion(version: '1.1', createdAt: DateTime.now(), steps: []));
      expect(e.rollback('s1', '1.0')!.version, '1.0');
    });
  });

  group('VisionGrounding', () {
    test('centerOf', () {
      final v = VisionGrounding();
      final c = v.centerOf(
          const ScreenRegion(x: 0.2, y: 0.3, width: 0.4, height: 0.2));
      expect(c.x, 0.4);
      expect(c.y, 0.4);
    });
    test('ground without VLM', () async {
      expect((await VisionGrounding().ground('s.png', 'btn')).found, isFalse);
    });
  });

  group('ResolutionAdapter', () {
    test('relativeToAbsolute', () {
      final a = ResolutionAdapter(
          currentDevice:
              const DeviceInfo(screenWidth: 1080, screenHeight: 2400));
      final r = a.relativeToAbsolute(0.5, 0.5);
      expect(r.x, 540);
      expect(r.y, 1200);
    });
  });

  group('HybridLocalizer', () {
    test('fails without strategies', () async {
      expect(
          (await HybridLocalizer(
                      visionGrounding: VisionGrounding(),
                      resolutionAdapter: ResolutionAdapter(
                          currentDevice: const DeviceInfo(
                              screenWidth: 1080, screenHeight: 2400)))
                  .locate('test'))
              .success,
          isFalse);
    });
  });
}
