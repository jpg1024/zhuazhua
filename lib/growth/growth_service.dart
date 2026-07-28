import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

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

class GrowthService extends ChangeNotifier {
  final String animalId;

  DateTime createdAt = DateTime.now();
  int level = 1;
  int exp = 0;
  int mood = 80;
  int totalInteractions = 0;
  int totalOnlineMinutes = 0;
  DateTime lastActiveAt = DateTime.now();
  List<GrowthEvent> events = [];

  Timer? _minuteTimer;
  DateTime _lastInteractExp = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastInteraction = DateTime.now();

  int get expToNext => 100 * level;

  GrowthService(this.animalId) {
    _load();
    _minuteTimer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  File get _file => File('${AppPaths.growthDir.path}\\$animalId.json');

  void _load() {
    try {
      if (_file.existsSync()) {
        final j = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
        createdAt = DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now();
        level = j['level'] ?? 1;
        exp = j['exp'] ?? 0;
        mood = j['mood'] ?? 80;
        totalInteractions = j['totalInteractions'] ?? 0;
        totalOnlineMinutes = j['totalOnlineMinutes'] ?? 0;
        lastActiveAt = DateTime.tryParse(j['lastActiveAt'] ?? '') ?? DateTime.now();
        events = ((j['events'] as List?) ?? [])
            .map((e) => GrowthEvent.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        addEvent('birth', '第一次见面，请多关照！');
        save();
      }
    } catch (_) {}
  }

  void save() {
    try {
      lastActiveAt = DateTime.now();
      _file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
        'animalId': animalId,
        'createdAt': createdAt.toIso8601String(),
        'level': level,
        'exp': exp,
        'mood': mood,
        'totalInteractions': totalInteractions,
        'totalOnlineMinutes': totalOnlineMinutes,
        'lastActiveAt': lastActiveAt.toIso8601String(),
        'events': events.map((e) => e.toJson()).toList(),
      }));
    } catch (_) {}
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
    save();
    super.dispose();
  }
}
