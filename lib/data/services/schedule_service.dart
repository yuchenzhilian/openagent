// ignore_for_file: dangling_library_doc_comments

/// 定时任务调度服务。
///
/// 持久化任务到 JSON 文件，定期检查并触发执行。
/// 支持 cron-like 表达式（分钟/小时/天维度）和固定间隔。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 单个定时任务配置。
class ScheduleTask {
  final String id;
  final String name;
  final String description;
  final String instruction; // 任务描述/指令，发送给 Agent 执行
  final String schedule; // 调度表达式: "daily:08:00" / "interval:3600" / "cron:0 8 * * *"
  final bool enabled;
  final DateTime createdAt;
  final DateTime? lastRunAt;
  final int runCount;
  final String? lastResult;

  const ScheduleTask({
    required this.id,
    required this.name,
    this.description = '',
    required this.instruction,
    required this.schedule,
    this.enabled = true,
    required this.createdAt,
    this.lastRunAt,
    this.runCount = 0,
    this.lastResult,
  });

  ScheduleTask copyWith({
    String? id,
    String? name,
    String? description,
    String? instruction,
    String? schedule,
    bool? enabled,
    DateTime? createdAt,
    DateTime? lastRunAt,
    int? runCount,
    String? lastResult,
    bool clearLastRun = false,
  }) =>
      ScheduleTask(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        instruction: instruction ?? this.instruction,
        schedule: schedule ?? this.schedule,
        enabled: enabled ?? this.enabled,
        createdAt: createdAt ?? this.createdAt,
        lastRunAt: clearLastRun ? null : (lastRunAt ?? this.lastRunAt),
        runCount: runCount ?? this.runCount,
        lastResult: clearLastRun ? null : (lastResult ?? this.lastResult),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'instruction': instruction,
        'schedule': schedule,
        'enabled': enabled,
        'created_at': createdAt.toIso8601String(),
        'last_run_at': lastRunAt?.toIso8601String(),
        'run_count': runCount,
        'last_result': lastResult,
      };

  factory ScheduleTask.fromJson(Map<String, dynamic> j) => ScheduleTask(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        description: j['description'] as String? ?? '',
        instruction: j['instruction'] as String? ?? '',
        schedule: j['schedule'] as String? ?? '',
        enabled: j['enabled'] as bool? ?? true,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
        lastRunAt: j['last_run_at'] != null ? DateTime.tryParse(j['last_run_at'] as String? ?? '') : null,
        runCount: j['run_count'] as int? ?? 0,
        lastResult: j['last_result'] as String?,
      );
}

/// 调度服务。
class ScheduleService {
  ScheduleService._();
  static final ScheduleService instance = ScheduleService._();

  final List<ScheduleTask> _tasks = [];
  Timer? _checkTimer;
  bool _initialized = false;
  String? _storagePath;

  /// 任务触发回调：当任务被触发时调用。
  /// 参数为被触发的任务。返回 true 表示执行成功。
  Future<bool> Function(ScheduleTask task)? onTaskTriggered;

  /// 通知回调：更新 UI 等。
  VoidCallback? onTasksChanged;

  List<ScheduleTask> get tasks => List.unmodifiable(_tasks);

  /// 初始化调度服务。
  Future<void> init({required String storagePath}) async {
    _storagePath = storagePath;
    await _load();
    _initialized = true;
    _startChecker();
  }

  /// 添加任务。
  Future<ScheduleTask> addTask({
    required String name,
    String description = '',
    required String instruction,
    required String schedule,
  }) async {
    final task = ScheduleTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      description: description,
      instruction: instruction,
      schedule: schedule,
      createdAt: DateTime.now(),
    );
    _tasks.add(task);
    await _save();
    onTasksChanged?.call();
    return task;
  }

  /// 删除任务。
  Future<bool> removeTask(String id) async {
    final before = _tasks.length;
    _tasks.removeWhere((t) => t.id == id);
    final removed = before - _tasks.length;
    if (removed > 0) {
      await _save();
      onTasksChanged?.call();
      return true;
    }
    return false;
  }

  /// 更新任务。
  Future<ScheduleTask?> updateTask(String id, {required ScheduleTask Function(ScheduleTask) update}) async {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return null;
    _tasks[idx] = update(_tasks[idx]);
    await _save();
    onTasksChanged?.call();
    return _tasks[idx];
  }

  /// 启用/禁用任务。
  Future<bool> toggleTask(String id, bool enabled) async {
    final task = await updateTask(id, update: (t) => t.copyWith(enabled: enabled));
    return task != null;
  }

  /// 停止调度服务。
  void dispose() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  /// 检查是否有任务需要触发。
  void _startChecker() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkTasks());
  }

  Future<void> _checkTasks() async {
    if (!_initialized) return;
    final now = DateTime.now();
    for (final task in _tasks.toList()) {
      if (!task.enabled) continue;
      if (!_shouldRun(task, now)) continue;
      debugPrint('[ScheduleService] 触发任务: ${task.name} (${task.id})');
      // 标记已运行
      final idx = _tasks.indexWhere((t) => t.id == task.id);
      if (idx < 0) continue;
      _tasks[idx] = task.copyWith(
        lastRunAt: now,
        runCount: task.runCount + 1,
        lastResult: 'pending',
      );
      await _save();
      // 执行回调
      if (onTaskTriggered != null) {
        try {
          final ok = await onTaskTriggered!(task);
          _tasks[idx] = _tasks[idx].copyWith(
            lastResult: ok ? 'success' : 'failed',
          );
        } catch (e) {
          _tasks[idx] = _tasks[idx].copyWith(
            lastResult: 'error: $e',
          );
        }
        await _save();
      }
    }
  }

  bool _shouldRun(ScheduleTask task, DateTime now) {
    // 检查上次运行时间
    if (task.lastRunAt != null) {
      // 防止重复触发（同一分钟不重复）
      if (task.lastRunAt!.isAfter(now.subtract(const Duration(minutes: 1)))) {
        return false;
      }
    }
    final parts = task.schedule.split(':');
    if (parts.length < 2) return false;
    switch (parts[0]) {
      case 'daily':
        // daily:HH:MM — 每天指定时间
        final hour = int.tryParse(parts[1]) ?? -1;
        final minute = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;
        return now.hour == hour && now.minute == minute;
      case 'interval':
        // interval:seconds — 固定间隔（秒）
        final interval = int.tryParse(parts[1]) ?? 0;
        if (interval <= 0 || task.lastRunAt == null) return false;
        return now.difference(task.lastRunAt!).inSeconds >= interval;
      case 'cron':
        // 简单 cron: minute hour * * * (简化版，只支持分钟和小时)
        if (parts.length < 3) return false;
        final cronMinute = int.tryParse(parts[1]) ?? -1;
        final cronHour = int.tryParse(parts[2]) ?? -1;
        return (cronMinute < 0 || now.minute == cronMinute) &&
            (cronHour < 0 || now.hour == cronHour);
      default:
        return false;
    }
  }

  Future<void> _load() async {
    if (_storagePath == null) return;
    try {
      final file = File('$_storagePath/schedule_tasks.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = jsonDecode(content) as List<dynamic>;
        _tasks.clear();
        for (final item in list) {
          _tasks.add(ScheduleTask.fromJson(item as Map<String, dynamic>));
        }
      }
    } catch (e) {
      debugPrint('[ScheduleService] 加载失败: $e');
    }
  }

  Future<void> _save() async {
    if (_storagePath == null) return;
    try {
      final file = File('$_storagePath/schedule_tasks.json');
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await file.writeAsString(jsonEncode(_tasks.map((t) => t.toJson()).toList()));
    } catch (e) {
      debugPrint('[ScheduleService] 保存失败: $e');
    }
  }
}