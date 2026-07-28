import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../ai/ai_client.dart';
import '../core/animals.dart';
import '../core/config.dart';
import '../growth/growth_service.dart';

enum PetState { idle, blink, happy, sleep }

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
  DateTime _lastInteraction = DateTime.now();

  PetController({
    required this.animal,
    required this.growth,
    required this.config,
  }) : ai = AiClient(config.ai) {
    _scheduleBlink();
    _sleepTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (state == PetState.idle &&
          DateTime.now().difference(_lastInteraction).inMinutes >= 5) {
        state = PetState.sleep;
        notifyListeners();
      }
    });
    _scheduleTip();
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
    super.dispose();
  }
}
