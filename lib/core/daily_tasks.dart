import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'config.dart';
import 'fa_icons.dart';

class DailyTaskDef {
  final String id;
  final String name;
  final IconData icon;
  final int target;

  /// 达成奖励：心情与经验。
  final int rewardMood;
  final int rewardExp;
  final String unit;

  const DailyTaskDef({
    required this.id,
    required this.name,
    required this.icon,
    required this.target,
    required this.rewardMood,
    required this.rewardExp,
    required this.unit,
  });
}

const List<DailyTaskDef> kDailyTasks = [
  DailyTaskDef(
      id: 'interact',
      name: '互动一下',
      icon: Fa7.handPointer,
      target: 3,
      rewardMood: 0,
      rewardExp: 3,
      unit: '次'),
  DailyTaskDef(
      id: 'accompany',
      name: '陪伴主人',
      icon: Fa7.clock,
      target: 30,
      rewardMood: 10,
      rewardExp: 0,
      unit: '分钟'),
  DailyTaskDef(
      id: 'feed',
      name: '吃点好吃的',
      icon: Fa7.bone,
      target: 1,
      rewardMood: 5,
      rewardExp: 0,
      unit: '次'),
  DailyTaskDef(
      id: 'pomodoro',
      name: '完成番茄钟',
      icon: Fa7.stopwatch,
      target: 1,
      rewardMood: 0,
      rewardExp: 5,
      unit: '个'),
];

/// 每日任务进度，跨天自动重置，JSON 落盘。
class DailyTaskService extends ChangeNotifier {
  String _date = _today();
  final Map<String, int> _counts = {};
  final Set<String> _done = {};

  DailyTaskService() {
    _load();
  }

  static String _today() =>
      DateTime.now().toIso8601String().substring(0, 10);

  int countOf(String id) => _counts[id] ?? 0;

  bool isDone(String id) => _done.contains(id);

  int get doneCount => _done.length;

  /// 累计进度；首次达成返回该任务定义（由调用方发放奖励），否则返回 null。
  DailyTaskDef? add(String id, [int n = 1]) {
    _rollover();
    final idx = kDailyTasks.indexWhere((t) => t.id == id);
    if (idx < 0 || _done.contains(id)) return null;
    final def = kDailyTasks[idx];
    final before = _counts[id] ?? 0;
    final v = before + n;
    _counts[id] = v;
    if (v >= def.target && before < def.target) _done.add(id);
    _save();
    notifyListeners();
    return v >= def.target && before < def.target ? def : null;
  }

  void _rollover() {
    final today = _today();
    if (today != _date) {
      _date = today;
      _counts.clear();
      _done.clear();
      _save();
    }
  }

  void _load() {
    try {
      final f = AppPaths.dailyTasksFile;
      if (!f.existsSync()) return;
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      _date = j['date'] ?? _today();
      final counts = j['counts'] as Map<String, dynamic>? ?? {};
      counts.forEach((k, v) => _counts[k] = v as int? ?? 0);
      final done = (j['done'] as List?) ?? [];
      for (final id in done) {
        if (id is String) _done.add(id);
      }
      _rollover();
    } catch (_) {}
  }

  void _save() {
    try {
      AppPaths.dailyTasksFile.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
        'date': _date,
        'counts': _counts,
        'done': _done.toList(),
      }));
    } catch (_) {}
  }
}
