import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zoo_desktop_pet/core/config.dart';
import 'package:zoo_desktop_pet/core/daily_tasks.dart';

import 'test_paths.dart';

void main() {
  late Directory tmp;
  late DailyTaskService daily;

  setUp(() {
    tmp = setupPaths();
    daily = DailyTaskService();
  });

  tearDown(() {
    daily.dispose();
    teardownPaths(tmp);
  });

  test('首次达标返回任务定义，重复调用返回 null（防重复发奖）', () {
    final def = kDailyTasks.firstWhere((t) => t.id == 'interact');
    DailyTaskDef? got;
    for (var i = 0; i < def.target; i++) {
      got = daily.add('interact') ?? got;
    }
    expect(got, isNotNull);
    expect(got!.id, 'interact');
    // 已完成后再加：不再返回 def
    expect(daily.add('interact'), isNull);
  });

  test('未达标前 add 返回 null 但计数递增', () {
    expect(daily.add('interact'), isNull);
    expect(daily.countOf('interact'), 1);
  });

  test('未知任务 id 安全返回 null', () {
    expect(daily.add('no_such_task'), isNull);
  });

  test('flush 后重新 load 恢复进度与完成态', () {
    final def = kDailyTasks.firstWhere((t) => t.id == 'feed');
    for (var i = 0; i < def.target; i++) {
      daily.add('feed');
    }
    daily.flush();

    final reloaded = DailyTaskService();
    addTearDown(reloaded.dispose);
    expect(reloaded.isDone('feed'), isTrue);
    expect(reloaded.countOf('feed'), def.target);
  });

  test('跨天 rollover：昨天的存档清零重来', () {
    // 手写一份"昨天"的存档
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    File(AppPaths.dailyTasksFile.path).writeAsStringSync(jsonEncode({
      'date': yesterday.toIso8601String().substring(0, 10),
      'counts': {'interact': 99},
      'done': ['interact'],
    }));

    final rolled = DailyTaskService();
    addTearDown(rolled.dispose);
    expect(rolled.countOf('interact'), 0);
    expect(rolled.isDone('interact'), isFalse);
  });
}
