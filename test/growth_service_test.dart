import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zoo_desktop_pet/growth/growth_service.dart';

import 'test_paths.dart';

void main() {
  late Directory tmp;
  late GrowthService growth;

  setUp(() {
    tmp = setupPaths();
    growth = GrowthService('cat');
  });

  tearDown(() {
    growth.dispose(); // 取消分钟/节流定时器并 flush
    teardownPaths(tmp);
  });

  test('新动物出生：默认状态 + birth 事件', () {
    expect(growth.level, 1);
    expect(growth.exp, 0);
    expect(growth.mood, 80);
    expect(growth.events.single.type, 'birth');
  });

  test('expToNext = 100 * level', () {
    expect(growth.expToNext, 100);
    growth.level = 5;
    expect(growth.expToNext, 500);
  });

  test('grantExp 支持连续升级循环', () {
    // Lv1→2 需 100，Lv2→3 需 200，300 经验连升两级余 0
    final leveled = growth.grantExp(300);
    expect(leveled, isTrue);
    expect(growth.level, 3);
    expect(growth.exp, 0);
    // 升级事件应被记录
    expect(growth.events.where((e) => e.type == 'levelUp').length, 2);
  });

  test('mood 被 clamp 在 0~100', () {
    growth.boostMood(50);
    expect(growth.mood, 100);
    growth.mood = 5;
    growth.boostMood(-50);
    expect(growth.mood, 0);
  });

  test('interact 经验有 60 秒冷却，mood 无冷却', () {
    growth.interact(); // 首次：+2 经验
    expect(growth.exp, 2);
    growth.interact(); // 冷却内：经验不变，mood 仍加
    expect(growth.exp, 2);
    expect(growth.mood, 90); // 80 + 5 + 5
    expect(growth.totalInteractions, 2);
  });

  test('feed 经验冷却与计数', () {
    growth.feed();
    expect(growth.exp, 1);
    growth.feed();
    expect(growth.exp, 1);
    expect(growth.totalFeedings, 2);
    expect(growth.mood, 100); // 80+10+10 clamp 到 100
  });

  test('events 超过 200 条时截断保留最新', () {
    for (var i = 0; i < 250; i++) {
      growth.addEvent('test', 'event-$i');
    }
    expect(growth.events.length, 200);
    expect(growth.events.last.detail, 'event-249');
    expect(growth.events.first.detail, 'event-50');
  });

  test('flush 后可重新 load 恢复全部状态', () {
    growth.grantExp(150); // Lv2, exp 50
    growth.interact();
    growth.flush();

    final reloaded = GrowthService('cat');
    addTearDown(reloaded.dispose);
    expect(reloaded.level, 2);
    expect(reloaded.exp, 52); // 150→Lv2余50，interact 冷却外 +2
    expect(reloaded.totalInteractions, 1);
    expect(reloaded.events.any((e) => e.type == 'birth'), isTrue);
  });
}
