import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/atomic_json.dart';
import '../core/config.dart';

class GrowthEvent {
  final DateTime time;
  final String type;
  final String detail;

  GrowthEvent(this.time, this.type, this.detail);

  factory GrowthEvent.fromJson(Map<String, dynamic> j) => GrowthEvent(
        DateTime.tryParse(j['time'] ?? '') ?? DateTime.now(),
        j['type'] ?? '',
        j['detail'] ?? '',
      );

  Map<String, dynamic> toJson() =>
      {'time': time.toIso8601String(), 'type': type, 'detail': detail};
}

/// Read-only view of a single animal's growth data, loaded directly from disk
/// without starting timers or writing. Used by the settings page browser.
class GrowthSnapshot {
  final String animalId;
  final DateTime createdAt;
  final int level;
  final int exp;
  final int mood;
  final int totalInteractions;
  final int totalOnlineMinutes;
  final int totalFeedings;
  final DateTime lastActiveAt;

  GrowthSnapshot({
    required this.animalId,
    required this.createdAt,
    required this.level,
    required this.exp,
    required this.mood,
    required this.totalInteractions,
    required this.totalOnlineMinutes,
    required this.totalFeedings,
    required this.lastActiveAt,
  });

  int get expToNext => 100 * level;

  factory GrowthSnapshot.fromJson(String animalId, Map<String, dynamic> j) {
    return GrowthSnapshot(
      animalId: j['animalId'] ?? animalId,
      createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
      level: j['level'] ?? 1,
      exp: j['exp'] ?? 0,
      mood: j['mood'] ?? 80,
      totalInteractions: j['totalInteractions'] ?? 0,
      totalOnlineMinutes: j['totalOnlineMinutes'] ?? 0,
      totalFeedings: j['totalFeedings'] ?? 0,
      lastActiveAt: DateTime.tryParse(j['lastActiveAt'] ?? '') ?? DateTime.now(),
    );
  }

  static List<GrowthSnapshot> loadAll() {
    final result = <GrowthSnapshot>[];
    try {
      final dir = AppPaths.growthDir;
      for (final entity in dir.listSync()) {
        if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
          continue;
        }
        final name = entity.uri.pathSegments.last;
        final id = name.substring(0, name.length - 5);
        final j = AtomicJson.read(entity);
        if (j != null) result.add(GrowthSnapshot.fromJson(id, j));
      }
    } catch (_) {}
    return result;
  }
}

class GrowthService extends ChangeNotifier {
  final String animalId;

  DateTime createdAt = DateTime.now();
  int level = 1;
  int exp = 0;
  int mood = 80;
  int totalInteractions = 0;
  int totalOnlineMinutes = 0;
  int totalFeedings = 0;
  DateTime lastActiveAt = DateTime.now();
  List<GrowthEvent> events = [];

  Timer? _minuteTimer;
  DateTime _lastInteractExp = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastFeedExp = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastInteraction = DateTime.now();

  int get expToNext => 100 * level;

  /// 从内存状态创建只读快照（供成就检测用，避免每分钟读盘）。
  GrowthSnapshot toSnapshot() => GrowthSnapshot(
        animalId: animalId,
        createdAt: createdAt,
        level: level,
        exp: exp,
        mood: mood,
        totalInteractions: totalInteractions,
        totalOnlineMinutes: totalOnlineMinutes,
        totalFeedings: totalFeedings,
        lastActiveAt: lastActiveAt,
      );

  GrowthService(this.animalId) {
    _load();
    _minuteTimer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  File get _file => File('${AppPaths.growthDir.path}\\$animalId.json');

  void _load() {
    final j = AtomicJson.read(_file);
    if (j != null) {
      createdAt = DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now();
      level = j['level'] ?? 1;
      exp = j['exp'] ?? 0;
      mood = j['mood'] ?? 80;
      totalInteractions = j['totalInteractions'] ?? 0;
      totalOnlineMinutes = j['totalOnlineMinutes'] ?? 0;
      totalFeedings = j['totalFeedings'] ?? 0;
      lastActiveAt = DateTime.tryParse(j['lastActiveAt'] ?? '') ?? DateTime.now();
      events = ((j['events'] as List?) ?? [])
          .map((e) => GrowthEvent.fromJson(e as Map<String, dynamic>))
          .toList();
    } else if (!_file.existsSync()) {
      addEvent('birth', '第一次见面，请多关照！');
      save();
    }
  }

  Timer? _flushTimer;
  bool _dirty = false;

  /// 标记数据已变更，3 秒内合并落盘（节流）。
  /// 避免一次互动（成长+任务+奖励经验）触发 2~3 次同步写盘。
  /// 需要立即持久化的路径（退出/重启/dispose）请调用 [flush]。
  void save() {
    _dirty = true;
    _flushTimer ??= Timer(const Duration(seconds: 3), flush);
  }

  /// 立即将未落盘的变更写入磁盘（幂等）。
  void flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (!_dirty) return;
    _dirty = false;
    lastActiveAt = DateTime.now();
    final ok = AtomicJson.write(_file, {
      'animalId': animalId,
      'createdAt': createdAt.toIso8601String(),
      'level': level,
      'exp': exp,
      'mood': mood,
      'totalInteractions': totalInteractions,
      'totalOnlineMinutes': totalOnlineMinutes,
      'totalFeedings': totalFeedings,
      'lastActiveAt': lastActiveAt.toIso8601String(),
      'events': events.map((e) => e.toJson()).toList(),
    });
    if (!ok) debugPrint('GrowthService.flush($animalId) failed');
  }

  void addEvent(String type, String detail) {
    events.add(GrowthEvent(DateTime.now(), type, detail));
    if (events.length > 200) {
      events = events.sublist(events.length - 200);
    }
  }

  void _tick() {
    totalOnlineMinutes++;
    if (totalOnlineMinutes % 10 == 0) {
      _gainExp(1);
      if (DateTime.now().difference(_lastInteraction).inMinutes >= 10 &&
          mood > 0) {
        mood--;
      }
    }
    save();
    notifyListeners();
  }

  /// Returns true if this interaction caused a level-up.
  bool interact() {
    totalInteractions++;
    _lastInteraction = DateTime.now();
    mood = (mood + 5).clamp(0, 100);
    var leveled = false;
    if (DateTime.now().difference(_lastInteractExp).inSeconds >= 60) {
      _lastInteractExp = DateTime.now();
      leveled = _gainExp(2);
    }
    save();
    notifyListeners();
    return leveled;
  }

  /// 喂食：心情 +10；经验 60 秒冷却 +1。返回是否因此升级。
  bool feed() {
    totalFeedings++;
    _lastInteraction = DateTime.now();
    mood = (mood + 10).clamp(0, 100);
    var leveled = false;
    if (DateTime.now().difference(_lastFeedExp).inSeconds >= 60) {
      _lastFeedExp = DateTime.now();
      leveled = _gainExp(1);
    }
    save();
    notifyListeners();
    return leveled;
  }

  /// 直接奖励经验（每日任务/番茄钟用），返回是否因此升级。
  bool grantExp(int amount) {
    final leveled = _gainExp(amount);
    save();
    notifyListeners();
    return leveled;
  }

  void boostMood(int amount) {
    mood = (mood + amount).clamp(0, 100);
    save();
    notifyListeners();
  }

  bool _gainExp(int amount) {
    exp += amount;
    var leveled = false;
    while (exp >= expToNext) {
      exp -= expToNext;
      level++;
      leveled = true;
      addEvent('levelUp', '升到 Lv.$level');
    }
    return leveled;
  }

  @override
  void dispose() {
    _minuteTimer?.cancel();
    _flushTimer?.cancel();
    flush();
    super.dispose();
  }
}
