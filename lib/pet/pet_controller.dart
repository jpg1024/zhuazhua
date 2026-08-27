import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../ai/ai_client.dart';
import '../core/achievements.dart';
import '../core/animals.dart';
import '../core/config.dart';
import '../core/daily_tasks.dart';
import '../core/keyboard_hook.dart';
import '../growth/growth_service.dart';

enum PetState { idle, blink, happy, sleep, patrol, eat, yawn, jump, spin }

enum PomoPhase { none, focus, breakTime }

class PetController extends ChangeNotifier {
  final AnimalInfo animal;
  final GrowthService growth;
  final AiClient ai;
  final AppConfig config;
  final AchievementsService achievements = AchievementsService();
  final DailyTaskService daily = DailyTaskService();
  final _rand = Random();

  PetState state = PetState.idle;
  String? bubbleText;
  bool showGrowthCard = false;

  /// 本次喂食的食物 emoji（供 UI 掉落动画与气泡使用）
  String feedingFood = '🍖';

  Timer? _blinkTimer;
  Timer? _bubbleTimer;
  Timer? _sleepTimer;
  Timer? _tipTimer;
  Timer? _growthCardTimer;
  Timer? _patrolDebounce;
  Timer? _patrolStopTimer;
  Timer? _actionTimer;
  Timer? _actionStopTimer;
  Timer? _greetTimer;
  Timer? _pomoTimer;
  DateTime _lastInteraction = DateTime.now();
  int _lastSeenOnline = 0;

  PomoPhase pomoPhase = PomoPhase.none;
  int pomoRemaining = 0;
  static const int pomoFocusSeconds = 25 * 60;
  static const int pomoBreakSeconds = 5 * 60;

  bool get pomoRunning => pomoPhase != PomoPhase.none;

  /// 本次巡逻的实际方向（'left' 或 'right'），由 resolvePatrolDirection() 决定
  String patrolActualDirection = 'left';

  /// 是否正在巡逻（供 UI 层读取）
  bool get isPatrolling => state == PetState.patrol;

  PetController({
    required this.animal,
    required this.growth,
    required this.config,
  }) : ai = AiClient(config.ai) {
    _scheduleBlink();
    _sleepTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (state == PetState.idle &&
          DateTime.now().difference(_lastInteraction).inMinutes >=
              config.sleepTimeoutMinutes) {
        state = PetState.sleep;
        notifyListeners();
      }
    });
    _scheduleTip();
    _initKeyboardHook();
    _lastSeenOnline = growth.totalOnlineMinutes;
    growth.addListener(_onGrowthTick);
    _checkAchievements();
    _scheduleGreet();
    _scheduleRandomAction();
  }

  // ── 每日任务 / 成就编排 ──────────────────────────────────────────────────

  void _onGrowthTick() {
    if (growth.totalOnlineMinutes == _lastSeenOnline) return;
    _lastSeenOnline = growth.totalOnlineMinutes;
    final done = daily.add('accompany');
    if (done != null) _applyTaskReward(done);
    _checkAchievements();
  }

  void _applyTaskReward(DailyTaskDef def) {
    if (state == PetState.sleep) {
      state = PetState.idle;
      notifyListeners();
    }
    if (def.rewardExp > 0) {
      final leveled = growth.grantExp(def.rewardExp);
      showBubble(
          leveled
              ? '每日任务「${def.name}」完成！经验+${def.rewardExp}，还升级啦！'
              : '每日任务「${def.name}」完成！经验+${def.rewardExp} 🎉',
          seconds: 6);
    } else if (def.rewardMood > 0) {
      growth.boostMood(def.rewardMood);
      showBubble('每日任务「${def.name}」完成！心情+${def.rewardMood} 🎉',
          seconds: 6);
    }
  }

  void _checkAchievements() {
    final stats = AchievementsService.aggregate(
        GrowthSnapshot.loadAll(), achievements.pomodoros);
    final newly = achievements.checkAll(stats);
    for (final a in newly) {
      showBubble('🏆 解锁成就「${a.name}」！', seconds: 6);
      growth.addEvent('achievement', '解锁成就「${a.name}」');
      growth.save();
    }
  }

  // ── 键盘巡逻 ─────────────────────────────────────────────────────────────

  void _initKeyboardHook() {
    final hook = KeyboardHookService.instance;
    hook.install();
    hook.activityStream.listen((isTyping) {
      if (isTyping) {
        _onTypingDetected();
      } else {
        _onTypingStopped();
      }
    });
  }

  void _onTypingDetected() {
    // 已经在巡逻或睡眠中则不处理
    if (state == PetState.patrol || state == PetState.sleep) return;

    // 防抖：300ms 后确认仍在打字才启动巡逻
    _patrolDebounce?.cancel();
    _patrolStopTimer?.cancel();
    _patrolDebounce = Timer(const Duration(milliseconds: 300), () {
      if (KeyboardHookService.instance.isTyping && state != PetState.patrol) {
        _startPatrol();
      }
    });
  }

  void _onTypingStopped() {
    // 如果正在巡逻，延迟 2 秒后停止
    if (state == PetState.patrol) {
      _patrolStopTimer?.cancel();
      _patrolStopTimer = Timer(const Duration(seconds: 2), () {
        if (!KeyboardHookService.instance.isTyping) {
          _stopPatrol();
        }
      });
    }
  }

  void _startPatrol() {
    patrolActualDirection = _resolvePatrolDirection();
    state = PetState.patrol;
    notifyListeners();
  }

  void _stopPatrol() {
    if (state != PetState.patrol) return;
    state = PetState.idle;
    notifyListeners();
  }

  /// 根据配置解析实际巡逻方向
  String _resolvePatrolDirection() {
    switch (config.patrolDirection) {
      case 'left':
        return 'left';
      case 'right':
        return 'right';
      case 'random':
        return _rand.nextBool() ? 'left' : 'right';
      default:
        return 'left';
    }
  }

  /// 巡逻结束归位后调用（由 UI 层动画完成时触发）
  void onPatrolReturned() {
    // 归位完成，2 秒内不再触发
    _patrolStopTimer?.cancel();
    _patrolStopTimer = Timer(const Duration(seconds: 2), () {});
  }

  // ── 随机小动作 ───────────────────────────────────────────────────────────

  void _scheduleRandomAction() {
    _actionTimer = Timer(Duration(seconds: 20 + _rand.nextInt(26)), () {
      if (state == PetState.idle && !pomoRunning) {
        _startRandomAction();
      }
      _scheduleRandomAction();
    });
  }

  void _startRandomAction() {
    final r = _rand.nextDouble();
    final PetState next;
    final int durationMs;
    if (r < 0.4) {
      next = PetState.yawn;
      durationMs = 1500;
    } else if (r < 0.7) {
      next = PetState.jump;
      durationMs = 700;
    } else {
      next = PetState.spin;
      durationMs = 2400;
    }
    state = next;
    notifyListeners();
    _actionStopTimer?.cancel();
    _actionStopTimer = Timer(Duration(milliseconds: durationMs), () {
      if (state == next) {
        state = PetState.idle;
        notifyListeners();
      }
    });
  }

  // ── 时间感知问候（无需 AI） ──────────────────────────────────────────────

  void _scheduleGreet() {
    _greetTimer = Timer(Duration(minutes: 35 + _rand.nextInt(31)), () {
      if (state == PetState.idle && !pomoRunning) {
        showBubble(_timePhrase(), seconds: 6);
        growth.addEvent('greet', '主动问候');
        growth.save();
      }
      _scheduleGreet();
    });
  }

  String _timePhrase() {
    final now = DateTime.now();
    final hour = now.hour;
    final weekend = now.weekday >= DateTime.saturday;
    const weekendPool = [
      '周末啦，出去晒晒太阳吧～',
      '休息日也要好好放松哦！',
      '周末愉快，主人陪我玩会儿嘛～',
    ];
    const morningPool = [
      '早安！新的一天也要元气满满～',
      '早上好，先喝杯水提提神吧！',
    ];
    const workingPool = [
      '工作加油，我就在旁边陪着你～',
      '专心工作啦，忙完记得摸摸我！',
      '你认真的样子最好看啦～',
    ];
    const lunchPool = [
      '到饭点啦，快去吃饭，别饿着！',
      '午饭时间到！吃饱才有力气继续呀～',
    ];
    const afternoonPool = [
      '下午容易犯困，起来伸个懒腰吧～',
      '要不要来杯咖啡？我帮你盯着屏幕！',
    ];
    const eveningPool = [
      '天快黑啦，早点收工回家吧～',
      '辛苦一天了，晚饭想吃点什么呀？',
    ];
    const nightPool = [
      '夜深了，早点休息，别熬夜啦～',
      '月亮都出来了，主人该睡觉啦！',
    ];
    if (weekend) return weekendPool[_rand.nextInt(weekendPool.length)];
    if (hour >= 5 && hour < 9) return morningPool[_rand.nextInt(morningPool.length)];
    if (hour >= 9 && hour < 12) return workingPool[_rand.nextInt(workingPool.length)];
    if (hour >= 12 && hour < 14) return lunchPool[_rand.nextInt(lunchPool.length)];
    if (hour >= 14 && hour < 18) return afternoonPool[_rand.nextInt(afternoonPool.length)];
    if (hour >= 18 && hour < 23) return eveningPool[_rand.nextInt(eveningPool.length)];
    return nightPool[_rand.nextInt(nightPool.length)];
  }

  // ── 番茄钟 ───────────────────────────────────────────────────────────────

  void togglePomodoro() {
    if (pomoRunning) {
      _stopPomodoro();
    } else {
      _startPomodoro();
    }
  }

  void _startPomodoro() {
    pomoPhase = PomoPhase.focus;
    pomoRemaining = pomoFocusSeconds;
    showBubble('开始专注！🍅 25 分钟后叫你休息', seconds: 5);
    _pomoTimer?.cancel();
    _pomoTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pomoTick());
    notifyListeners();
  }

  void _stopPomodoro() {
    pomoPhase = PomoPhase.none;
    pomoRemaining = 0;
    _pomoTimer?.cancel();
    _pomoTimer = null;
    showBubble('番茄钟已停止，休息一下吧～', seconds: 5);
    notifyListeners();
  }

  void _pomoTick() {
    pomoRemaining--;
    if (pomoRemaining > 0) {
      notifyListeners();
      return;
    }
    if (pomoPhase == PomoPhase.focus) {
      pomoPhase = PomoPhase.breakTime;
      pomoRemaining = pomoBreakSeconds;
      showBubble('专注结束！休息 5 分钟吧 ☕', seconds: 6);
      growth.addEvent('pomodoro', '完成一个专注时段');
      growth.save();
    } else {
      pomoPhase = PomoPhase.none;
      _pomoTimer?.cancel();
      _pomoTimer = null;
      achievements.pomodoros++;
      achievements.save();
      final leveled = growth.grantExp(3);
      final done = daily.add('pomodoro');
      if (done != null) _applyTaskReward(done);
      showBubble(leveled ? '番茄钟完成！经验+3，升级啦！🎉' : '番茄钟完成！经验+3 🎉',
          seconds: 6);
      _checkAchievements();
    }
    notifyListeners();
  }

  // ── 台词与互动 ───────────────────────────────────────────────────────────

  List<String> get _phrases => phrasesFor(animal);

  static const List<String> _sadPhrases = [
    '最近有点孤单呢…多陪陪我嘛',
    '心情不太好，摸摸我好不好…',
    '你怎么不理我呀…',
    '陪陪我嘛，一小会儿就好…',
  ];

  void _scheduleBlink() {
    _blinkTimer = Timer(Duration(seconds: 4 + _rand.nextInt(5)), () {
      if (state == PetState.idle) {
        state = PetState.blink;
        notifyListeners();
        Timer(const Duration(milliseconds: 260), () {
          if (state == PetState.blink) {
            state = PetState.idle;
            notifyListeners();
          }
        });
      }
      _scheduleBlink();
    });
  }

  void _scheduleTip() {
    if (!config.ai.enabled) return;
    final base = config.ai.tipIntervalMinutes.clamp(5, 720);
    final delay = Duration(minutes: base + _rand.nextInt(base ~/ 2 + 1));
    _tipTimer = Timer(delay, () async {
      final hour = DateTime.now().hour;
      final text = await ai.chat(
        _systemPrompt(),
        '现在是$hour点，请作为桌面宠物主动给主人一句不超过40字的暖心提示'
        '（如喝水、休息、久坐提醒、按时吃饭等），只输出这句话。',
      );
      if (text != null) {
        showBubble(text, seconds: 8);
        growth.addEvent('aiTip', text);
        growth.save();
      }
      _scheduleTip();
    });
  }

  String _systemPrompt() =>
      '你是一只名叫"${animal.name}"的桌面宠物，性格${animal.personality}。'
      '当前等级Lv.${growth.level}，心情${growth.mood}/100，'
      '已陪伴主人${growth.totalOnlineMinutes}分钟。'
      '用中文回复，口语化、拟人化、可爱，不超过40个字，不要使用引号。';

  void showBubble(String text, {int seconds = 5}) {
    bubbleText = text;
    notifyListeners();
    _bubbleTimer?.cancel();
    _bubbleTimer = Timer(Duration(seconds: seconds), () {
      bubbleText = null;
      notifyListeners();
    });
  }

  Future<void> interact() async {
    _lastInteraction = DateTime.now();
    final wasSleeping = state == PetState.sleep;
    state = PetState.happy;
    notifyListeners();
    Timer(const Duration(milliseconds: 1200), () {
      if (state == PetState.happy) {
        state = PetState.idle;
        notifyListeners();
      }
    });

    final leveled = growth.interact();
    final done = daily.add('interact');
    if (done != null) _applyTaskReward(done);
    if (leveled) {
      showBubble('哇！升级啦，现在是 Lv.${growth.level}！', seconds: 6);
      return;
    }
    if (wasSleeping) {
      showBubble('呼啊…被你叫醒了，${animal.name}睡得正香呢～');
      return;
    }
    if (growth.mood < 40) {
      showBubble(_sadPhrases[_rand.nextInt(_sadPhrases.length)]);
      return;
    }

    if (ai.ready && _rand.nextDouble() < 0.3) {
      showBubble(_phrases[_rand.nextInt(_phrases.length)]);
      final text = await ai.chat(_systemPrompt(), '主人刚刚摸了摸你，回应一句话。');
      if (text != null) {
        showBubble(text, seconds: 6);
        growth.addEvent('aiChat', text);
      }
    } else {
      showBubble(_phrases[_rand.nextInt(_phrases.length)]);
    }
  }

  Future<void> feed() async {
    _lastInteraction = DateTime.now();
    final wasSleeping = state == PetState.sleep;
    feedingFood = animal.foods[_rand.nextInt(animal.foods.length)];
    state = PetState.eat;
    notifyListeners();
    Timer(const Duration(milliseconds: 1600), () {
      if (state == PetState.eat) {
        state = PetState.idle;
        notifyListeners();
      }
    });

    final leveled = growth.feed();
    final done = daily.add('feed');
    if (done != null) _applyTaskReward(done);
    if (leveled) {
      showBubble('好吃！还升级啦，现在是 Lv.${growth.level}！', seconds: 6);
      return;
    }
    if (wasSleeping) {
      showBubble('闻到香味就醒啦～${animal.name}开动！');
      return;
    }
    showBubble('啊呜～$feedingFood真好吃！');
    _checkAchievements();
  }

  void toggleGrowthCard() {
    showGrowthCard = !showGrowthCard;
    _growthCardTimer?.cancel();
    if (showGrowthCard) {
      _growthCardTimer = Timer(const Duration(seconds: 15), () {
        showGrowthCard = false;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  static const double minScale = 0.6;
  static const double maxScale = 2.0;

  double get petScale => config.petScale;

  void setScale(double value) {
    final v = value.clamp(minScale, maxScale);
    if (v == config.petScale) return;
    config.petScale = v;
    config.save();
    notifyListeners();
  }

  void adjustScale(double delta) => setScale(config.petScale + delta);

  @override
  void dispose() {
    growth.removeListener(_onGrowthTick);
    _blinkTimer?.cancel();
    _bubbleTimer?.cancel();
    _sleepTimer?.cancel();
    _tipTimer?.cancel();
    _growthCardTimer?.cancel();
    _patrolDebounce?.cancel();
    _patrolStopTimer?.cancel();
    _actionTimer?.cancel();
    _actionStopTimer?.cancel();
    _greetTimer?.cancel();
    _pomoTimer?.cancel();
    KeyboardHookService.instance.dispose();
    super.dispose();
  }
}
