import 'package:flutter/material.dart';

class AnimalInfo {
  final String id;
  final String name;
  final String emoji;
  final String personality;
  final Color themeColor;
  final List<String> phrases;

  /// 有翅膀且会飞 → true（巡逻时飞翔动画）；否则 → false（巡逻时奔跑动画）
  final bool hasWings;

  /// 专属食物 emoji 列表（喂食时随机取一个，掉落动画与气泡同款）
  final List<String> foods;

  const AnimalInfo({
    required this.id,
    required this.name,
    required this.emoji,
    required this.personality,
    required this.themeColor,
    this.phrases = const [],
    this.hasWings = false,
    this.foods = const ['🍖', '🍎'],
  });
}

const List<String> _sharedPhrases = [
  '记得多喝水哦～',
  '坐久了起来活动一下吧！',
  '今天也要加油呀！',
  '看看窗外，让眼睛休息一下～',
  '你摸我头啦，好开心！',
  '嘿嘿，被你发现我在偷懒了～',
];

List<String> phrasesFor(AnimalInfo a) => [
      '${a.name}最喜欢你啦！',
      '我是${a.personality}的${a.name}～',
      '陪着你工作，${a.name}一点也不困！',
      '戳我干嘛呀，${a.name}会害羞的！',
      ..._sharedPhrases,
    ];

const List<AnimalInfo> kAnimals = [
  AnimalInfo(id: 'tiger', name: '老虎', emoji: '🐯', personality: '威风凛凛', themeColor: Color(0xFFE8871E), foods: ['🍖', '🥩']),
  AnimalInfo(id: 'lion', name: '狮子', emoji: '🦁', personality: '霸气侧漏', themeColor: Color(0xFFC98A2B), foods: ['🍖', '🥩']),
  AnimalInfo(id: 'dog', name: '狗狗', emoji: '🐶', personality: '忠诚活泼', themeColor: Color(0xFFA9745B), foods: ['🦴', '🥩']),
  AnimalInfo(id: 'cat', name: '猫', emoji: '🐱', personality: '高冷傲娇', themeColor: Color(0xFF8E7CC3), foods: ['🐟', '🥛']),
  AnimalInfo(id: 'elephant', name: '大象', emoji: '🐘', personality: '稳重温柔', themeColor: Color(0xFF8DA3B9), foods: ['🍌', '🍎']),
  AnimalInfo(id: 'monkey', name: '猴子', emoji: '🐵', personality: '机灵调皮', themeColor: Color(0xFFB58A5F), foods: ['🍌', '🍑']),
  AnimalInfo(id: 'panda', name: '熊猫', emoji: '🐼', personality: '憨态可掬', themeColor: Color(0xFF6B8E5A), foods: ['🎋', '🍎']),
  AnimalInfo(id: 'kangaroo', name: '袋鼠', emoji: '🦘', personality: '活力四射', themeColor: Color(0xFFC77B4F), foods: ['🥕', '🌿']),
  AnimalInfo(id: 'giraffe', name: '长颈鹿', emoji: '🦒', personality: '优雅从容', themeColor: Color(0xFFE0B653), foods: ['🌿', '🍃']),
  AnimalInfo(id: 'seal', name: '海豹', emoji: '🦭', personality: '圆滚滚软乎乎', themeColor: Color(0xFF7FA8C9), foods: ['🐟', '🦑']),
  AnimalInfo(id: 'hippo', name: '河马', emoji: '🦛', personality: '慢悠悠', themeColor: Color(0xFF9B8AA6), foods: ['🍉', '🌿']),
  AnimalInfo(id: 'orangutan', name: '猩猩', emoji: '🦧', personality: '聪明沉稳', themeColor: Color(0xFFB06A3B), foods: ['🍌', '🥭']),
  AnimalInfo(id: 'otter', name: '水獭', emoji: '🦦', personality: '爱玩水', themeColor: Color(0xFF8B9E6B), foods: ['🐟', '🦀']),
  AnimalInfo(id: 'red_panda', name: '小熊猫', emoji: '🐾', personality: '软萌可爱', themeColor: Color(0xFFCB6843), foods: ['🍎', '🎋']),
  AnimalInfo(id: 'eagle', name: '鹰', emoji: '🦅', personality: '锐利威武', themeColor: Color(0xFF7B6A55), hasWings: true, foods: ['🐟', '🍗']),
  AnimalInfo(id: 'parrot', name: '鹦鹉', emoji: '🦜', personality: '话痨社牛', themeColor: Color(0xFF4FA85C), hasWings: true, foods: ['🌰', '🍓']),
  AnimalInfo(id: 'mandarin_duck', name: '鸳鸯', emoji: '🦆', personality: '成双成对', themeColor: Color(0xFFCF7BA0), hasWings: true, foods: ['🐛', '🌾']),
  AnimalInfo(id: 'penguin', name: '企鹅', emoji: '🐧', personality: '摇摇摆摆', themeColor: Color(0xFF4A6B8A), foods: ['🐟', '🦐']),
  AnimalInfo(id: 'albatross', name: '信天翁', emoji: '🕊️', personality: '远航冒险', themeColor: Color(0xFF9AB3C4), hasWings: true, foods: ['🐟', '🦑']),
  AnimalInfo(id: 'swan', name: '天鹅', emoji: '🦢', personality: '高贵优雅', themeColor: Color(0xFFB9C4D6), hasWings: true, foods: ['🌾', '🐟']),
  AnimalInfo(id: 'ostrich', name: '鸵鸟', emoji: '🐦', personality: '大长腿飞毛腿', themeColor: Color(0xFFA88E6F), foods: ['🌿', '🍉']),
  AnimalInfo(id: 'heron', name: '鹭', emoji: '🐦', personality: '静如处子', themeColor: Color(0xFF8FA6A0), hasWings: true, foods: ['🐟', '🐸']),
  AnimalInfo(id: 'grouse', name: '松鸡', emoji: '🐦', personality: '林间隐士', themeColor: Color(0xFF97764F), hasWings: true, foods: ['🌰', '🐛']),
  AnimalInfo(id: 'woodpecker', name: '啄木鸟', emoji: '🐦', personality: '勤劳敬业', themeColor: Color(0xFFB55B4C), hasWings: true, foods: ['🐛', '🌰']),
  AnimalInfo(id: 'seagull', name: '海鸥', emoji: '🐦', personality: '自由自在', themeColor: Color(0xFF89A9C9), hasWings: true, foods: ['🐟', '🍟']),
  AnimalInfo(id: 'hummingbird', name: '蜂鸟', emoji: '🐦', personality: '小巧玲珑', themeColor: Color(0xFF5FA88F), hasWings: true, foods: ['🌺', '🍯']),
];

AnimalInfo animalById(String id) =>
    kAnimals.firstWhere((a) => a.id == id, orElse: () => kAnimals.first);
