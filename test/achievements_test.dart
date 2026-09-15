import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zoo_desktop_pet/core/achievements.dart';
import 'package:zoo_desktop_pet/growth/growth_service.dart';

import 'test_paths.dart';

GrowthSnapshot snap(
  String id, {
  int level = 1,
  int mood = 80,
  int interactions = 0,
  int onlineMinutes = 0,
  int feedings = 0,
  DateTime? createdAt,
}) =>
    GrowthSnapshot(
      animalId: id,
      createdAt: createdAt ?? DateTime.now(),
      level: level,
      exp: 0,
      mood: mood,
      totalInteractions: interactions,
      totalOnlineMinutes: onlineMinutes,
      totalFeedings: feedings,
      lastActiveAt: DateTime.now(),
    );

void main() {
  late Directory tmp;

  setUp(() => tmp = setupPaths());
  tearDown(() => teardownPaths(tmp));

  group('aggregate 跨动物聚合（max/sum 混合语义）', () {
    test('互动/在线/喂食跨动物求和，等级/心情取最大值', () {
      final s = AchievementsService.aggregate([
        snap('cat', level: 3, mood: 90, interactions: 60, onlineMinutes: 100, feedings: 30),
        snap('dog', level: 7, mood: 50, interactions: 50, onlineMinutes: 200, feedings: 25),
      ], 0);
      expect(s.totalInteractions, 110);
      expect(s.totalOnlineMinutes, 300);
      expect(s.totalFeedings, 55);
      expect(s.maxLevel, 7);
      expect(s.maxMood, 90);
      expect(s.distinctAnimals, 2);
    });

    test('maxDays 取相识天数最大值', () {
      final s = AchievementsService.aggregate([
        snap('cat', createdAt: DateTime.now().subtract(const Duration(days: 40))),
        snap('dog', createdAt: DateTime.now().subtract(const Duration(days: 5))),
      ], 0);
      expect(s.maxDays, greaterThanOrEqualTo(40));
    });
  });

  group('checkAll', () {
    test('只返回新解锁，重复调用幂等', () {
      final svc = AchievementsService();
      final stats = AchievementsService.aggregate(
          [snap('cat', interactions: 150)], 0);
      final first = svc.checkAll(stats);
      expect(first.map((a) => a.id), contains('interact_100'));
      final second = svc.checkAll(stats);
      expect(second, isEmpty);
    });

    test('跨动物数据解锁「任意宠物」类成就（防聚合回归）', () {
      // 当前动物 level=2，但另一只动物 level=10 → level_10 必须解锁。
      // 若聚合只传当前动物（曾经的回归写法），此断言会失败。
      final svc = AchievementsService();
      final stats = AchievementsService.aggregate([
        snap('tiger', level: 10),
        snap('cat', level: 2),
      ], 0);
      final newly = svc.checkAll(stats);
      expect(newly.map((a) => a.id), contains('level_10'));
      expect(newly.map((a) => a.id), isNot(contains('level_30')));
    });

    test('番茄钟计数参与判定', () {
      final svc = AchievementsService();
      final stats = AchievementsService.aggregate([snap('cat')], 10);
      final newly = svc.checkAll(stats);
      expect(newly.map((a) => a.id), contains('pomo_10'));
    });
  });
}
