import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../ai/ai_client.dart';
import '../core/animals.dart';
import '../core/config.dart';
import '../core/keyboard_hook.dart';
import '../growth/growth_service.dart';

enum PetState { idle, blink, happy, sleep, patrol }

class PetController extends ChangeNotifier {
  final AnimalInfo animal;
  final GrowthService growth;
  final AiClient ai;
  final AppConfig config;
  final _rand = Random();

  PetState state = PetState.idle;
  String? bubbleText;
  bool showGrowthCard = false;

  Timer? _blinkTimer;
  Timer? _bubbleTimer;
  Timer? _sleepTimer;
  Timer? _tipTimer;
  Timer? _growthCardTimer;
  Timer? _patrolDebounce;
  Timer? _patrolStopTimer;
  DateTime _lastInteraction = DateTime.now();

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
  }

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

  List<String> get _phrases => phrasesFor(animal);

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
    if (leveled) {
      showBubble('哇！升级啦，现在是 Lv.${growth.level}！', seconds: 6);
      return;
    }
    if (wasSleeping) {
      showBubble('呼啊…被你叫醒了，${animal.name}睡得正香呢～');
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
    _blinkTimer?.cancel();
    _bubbleTimer?.cancel();
    _sleepTimer?.cancel();
    _tipTimer?.cancel();
    _growthCardTimer?.cancel();
    _patrolDebounce?.cancel();
    _patrolStopTimer?.cancel();
    KeyboardHookService.instance.dispose();
    super.dispose();
  }
}
