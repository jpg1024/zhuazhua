import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../growth/growth_service.dart';
import 'config.dart';
import 'fa_icons.dart';

/// 成就判定的聚合统计（跨所有动物档案）。
class AchievementStats {
  final int totalInteractions;
  final int totalOnlineMinutes;
  final int totalFeedings;
  final int maxLevel;
  final int maxMood;
  final int maxDays;
  final int distinctAnimals;
  final int pomodoros;

  const AchievementStats({
    this.totalInteractions = 0,
    this.totalOnlineMinutes = 0,
    this.totalFeedings = 0,
    this.maxLevel = 1,
    this.maxMood = 0,
    this.maxDays = 0,
    this.distinctAnimals = 0,
    this.pomodoros = 0,
  });
}

class AchievementDef {
  final String id;
  final String name;
  final String desc;
  final IconData icon;
  final bool Function(AchievementStats s) test;

  const AchievementDef({
    required this.id,
    required this.name,
    required this.desc,
    required this.icon,
    required this.test,
  });
}

final List<AchievementDef> kAchievements = [
  AchievementDef(
      id: 'first_friend',
      name: '结缘初遇',
      desc: '结识 1 种动物',
      icon: Fa7.paw,
      test: (s) => s.distinctAnimals >= 1),
  AchievementDef(
      id: 'collector_10',
      name: '动物园长',
      desc: '结识 10 种动物',
      icon: Fa7.crown,
      test: (s) => s.distinctAnimals >= 10),
  AchievementDef(
      id: 'hour_1',
      name: '初来乍到',
      desc: '累计陪伴 1 小时',
      icon: Fa7.clock,
      test: (s) => s.totalOnlineMinutes >= 60),
  AchievementDef(
      id: 'hour_24',
      name: '常驻居民',
      desc: '累计陪伴 24 小时',
      icon: Fa7.house,
      test: (s) => s.totalOnlineMinutes >= 1440),
  AchievementDef(
      id: 'hour_100',
      name: '资深陪伴',
      desc: '累计陪伴 100 小时',
      icon: Fa7.hourglassHalf,
      test: (s) => s.totalOnlineMinutes >= 6000),
  AchievementDef(
      id: 'interact_100',
      name: '人气爆棚',
      desc: '累计互动 100 次',
      icon: Fa7.handPointer,
      test: (s) => s.totalInteractions >= 100),
  AchievementDef(
      id: 'level_10',
      name: '成长之星',
      desc: '任意宠物达到 Lv.10',
      icon: Fa7.star,
      test: (s) => s.maxLevel >= 10),
  AchievementDef(
      id: 'level_30',
      name: '宠物大师',
      desc: '任意宠物达到 Lv.30',
      icon: Fa7.crown,
      test: (s) => s.maxLevel >= 30),
  AchievementDef(
      id: 'feed_50',
      name: '投喂达人',
      desc: '累计喂食 50 次',
      icon: Fa7.bone,
      test: (s) => s.totalFeedings >= 50),
  AchievementDef(
      id: 'pomo_10',
      name: '专注达人',
      desc: '完成 10 个番茄钟',
      icon: Fa7.stopwatch,
      test: (s) => s.pomodoros >= 10),
  AchievementDef(
      id: 'mood_100',
      name: '心情满格',
      desc: '任意宠物心情达到 100',
      icon: Fa7.faceLaughBeam,
      test: (s) => s.maxMood >= 100),
  AchievementDef(
      id: 'days_30',
      name: '老友记',
      desc: '与任意宠物相识 30 天',
      icon: Fa7.calendarDays,
      test: (s) => s.maxDays >= 30),
];

class AchievementsService extends ChangeNotifier {
  final Map<String, DateTime> _unlocked = {};

  /// 累计完成的番茄钟数（跨动物、跨天累计）。
  int pomodoros = 0;

  AchievementsService() {
    _load();
  }

  bool isUnlocked(String id) => _unlocked.containsKey(id);

  DateTime? unlockedAt(String id) => _unlocked[id];

  int get unlockedCount => _unlocked.length;

  static AchievementStats aggregate(
      List<GrowthSnapshot> snaps, int pomodoros) {
    var interactions = 0, online = 0, feedings = 0;
    var maxLevel = 1, maxMood = 0, maxDays = 0;
    final now = DateTime.now();
    for (final s in snaps) {
      interactions += s.totalInteractions;
      online += s.totalOnlineMinutes;
      feedings += s.totalFeedings;
      if (s.level > maxLevel) maxLevel = s.level;
      if (s.mood > maxMood) maxMood = s.mood;
      final days = now.difference(s.createdAt).inDays + 1;
      if (days > maxDays) maxDays = days;
    }
    return AchievementStats(
      totalInteractions: interactions,
      totalOnlineMinutes: online,
      totalFeedings: feedings,
      maxLevel: maxLevel,
      maxMood: maxMood,
      maxDays: maxDays,
      distinctAnimals: snaps.length,
      pomodoros: pomodoros,
    );
  }

  /// 检测全部成就，返回本次新解锁的成就（同时落盘）。
  List<AchievementDef> checkAll(AchievementStats stats) {
    final newly = <AchievementDef>[];
    for (final a in kAchievements) {
      if (!_unlocked.containsKey(a.id) && a.test(stats)) {
        _unlocked[a.id] = DateTime.now();
        newly.add(a);
      }
    }
    if (newly.isNotEmpty) {
      _save();
      notifyListeners();
    }
    return newly;
  }

  void _load() {
    try {
      final f = AppPaths.achievementsFile;
      if (!f.existsSync()) return;
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      pomodoros = j['pomodoros'] ?? 0;
      final unlocked = j['unlocked'] as Map<String, dynamic>? ?? {};
      for (final e in unlocked.entries) {
        _unlocked[e.key] =
            DateTime.tryParse(e.value as String? ?? '') ?? DateTime.now();
      }
    } catch (_) {}
  }

  void save() {
    try {
      AppPaths.achievementsFile.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
        'pomodoros': pomodoros,
        'unlocked': {
          for (final e in _unlocked.entries)
            e.key: e.value.toIso8601String()
        },
      }));
    } catch (_) {}
  }

  void _save() => save();
}
