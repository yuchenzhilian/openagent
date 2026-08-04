// Tests for ScheduleService task model and JSON serialization.
import 'package:flutter_test/flutter_test.dart';
import 'package:openagent/data/services/schedule_service.dart';

void main() {
  group('ScheduleTask', () {
    test('default constructor', () {
      final task = ScheduleTask(
        id: 'test-1',
        name: 'Test Task',
        instruction: 'Do something',
        schedule: 'daily:08:00',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(task.id, 'test-1');
      expect(task.name, 'Test Task');
      expect(task.description, '');
      expect(task.enabled, isTrue);
      expect(task.runCount, 0);
      expect(task.lastRunAt, isNull);
      expect(task.lastResult, isNull);
    });

    test('toJson/fromJson round-trip', () {
      final task = ScheduleTask(
        id: 'test-1',
        name: 'Test Task',
        description: 'A test task',
        instruction: 'Do something',
        schedule: 'daily:08:00',
        enabled: true,
        createdAt: DateTime(2026, 1, 1),
        lastRunAt: DateTime(2026, 1, 2, 8, 0),
        runCount: 5,
        lastResult: 'success',
      );
      final json = task.toJson();
      final restored = ScheduleTask.fromJson(json);
      expect(restored.id, 'test-1');
      expect(restored.name, 'Test Task');
      expect(restored.description, 'A test task');
      expect(restored.instruction, 'Do something');
      expect(restored.schedule, 'daily:08:00');
      expect(restored.enabled, isTrue);
      expect(restored.runCount, 5);
      expect(restored.lastResult, 'success');
      expect(restored.lastRunAt, isNotNull);
    });

    test('fromJson handles missing fields', () {
      final task = ScheduleTask.fromJson({'id': 'test-1'});
      expect(task.id, 'test-1');
      expect(task.name, '');
      expect(task.description, '');
      expect(task.enabled, isTrue);
      expect(task.runCount, 0);
    });

    test('copyWith preserves fields', () {
      final task = ScheduleTask(
        id: 'test-1',
        name: 'Original',
        instruction: 'Do something',
        schedule: 'daily:08:00',
        createdAt: DateTime(2026, 1, 1),
      );
      final copy = task.copyWith(name: 'Updated');
      expect(copy.id, 'test-1');
      expect(copy.name, 'Updated');
      expect(copy.instruction, 'Do something');
    });

    test('copyWith clearLastRun works', () {
      final task = ScheduleTask(
        id: 'test-1',
        name: 'Test',
        instruction: 'Do something',
        schedule: 'daily:08:00',
        createdAt: DateTime(2026, 1, 1),
        lastRunAt: DateTime(2026, 1, 2),
        lastResult: 'ok',
      );
      final copy = task.copyWith(clearLastRun: true);
      expect(copy.lastRunAt, isNull);
      expect(copy.lastResult, isNull);
    });

    test('toJson omits null lastRunAt', () {
      final task = ScheduleTask(
        id: 'test-1',
        name: 'Test',
        instruction: 'Do something',
        schedule: 'daily:08:00',
        createdAt: DateTime(2026, 1, 1),
      );
      final json = task.toJson();
      expect(json['last_run_at'], isNull);
      expect(json['last_result'], isNull);
    });

    test('supports various schedule formats', () {
      final daily = ScheduleTask(
        id: '1', name: 'Daily', instruction: '', schedule: 'daily:08:00',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(daily.schedule, 'daily:08:00');

      final interval = ScheduleTask(
        id: '2', name: 'Interval', instruction: '', schedule: 'interval:3600',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(interval.schedule, 'interval:3600');

      final cron = ScheduleTask(
        id: '3', name: 'Cron', instruction: '', schedule: 'cron:0 8 * * *',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(cron.schedule, 'cron:0 8 * * *');
    });
  });

  group('ScheduleService', () {
    test('is a singleton', () {
      final instance1 = ScheduleService.instance;
      final instance2 = ScheduleService.instance;
      expect(identical(instance1, instance2), isTrue);
    });
  });
}