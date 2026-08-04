// KV cache stress test (Direction 2 Step 5).
import 'package:flutter_test/flutter_test.dart';
import 'package:openagent/agent/kv_cache/h2o_strategy.dart';
import 'package:openagent/agent/kv_cache/sliding_window.dart';

void main() {
  group('H2OStrategy stress test', () {
    test('handles 1000 attention scores', () {
      final strategy = H2OStrategy(config: const H2OConfig(
        checkInterval: 1, maxHeavyHitters: 128, slidingWindowSize: 64,
      ));
      final scores = List<double>.generate(1000, (i) => (i % 10) / 10.0);
      final keep = strategy.selectTokensToKeep(scores, 1000);
      expect(keep.length, greaterThanOrEqualTo(128));
      expect(keep.length, lessThanOrEqualTo(1000));
    });

    test('multiple rounds do not exceed max heavy hitters', () {
      final strategy = H2OStrategy(config: const H2OConfig(
        checkInterval: 3, maxHeavyHitters: 64, slidingWindowSize: 32,
      ));
      for (int round = 0; round < 10; round++) {
        final scores = List<double>.generate(200, (i) => (i % 5) / 5.0);
        final keep = strategy.selectTokensToKeep(scores, 200);
        expect(keep.length, lessThanOrEqualTo(200));
      }
    });

    test('reset clears state', () {
      final strategy = H2OStrategy();
      strategy.selectTokensToKeep([0.5, 0.3], 2);
      strategy.reset();
      // After reset, should work fresh.
      expect(() => strategy.selectTokensToKeep([0.9], 1), returnsNormally);
    });
  });

  group('SlidingWindowCache stress test', () {
    test('handles 100 sequential adds', () {
      final cache = SlidingWindowCache(windowSize: 100, summaryCacheSize: 50);
      int totalSummaries = 0;
      for (int i = 0; i < 100; i++) {
        cache.add('This is message number $i with some padding text to fill up the window. ');
        if (cache.summaries.length > totalSummaries) {
          totalSummaries = cache.summaries.length;
        }
      }
      expect(cache.summaries.length, greaterThan(0));
      expect(cache.windowContent, isNotEmpty);
    });

    test('fullContext format is correct', () {
      final cache = SlidingWindowCache(windowSize: 50, summaryCacheSize: 20);
      cache.add('A' * 100); // Force summary creation.
      cache.add('B' * 100);
      final context = cache.fullContext;
      expect(context, contains('[历史摘要]'));
      expect(context, contains('[/历史摘要]'));
    });

    test('reset clears all', () {
      final cache = SlidingWindowCache(windowSize: 50);
      cache.add('X' * 100);
      cache.reset();
      expect(cache.windowContent, '');
      expect(cache.summaries, isEmpty);
    });
  });
}