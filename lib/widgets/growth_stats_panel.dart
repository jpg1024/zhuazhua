import 'package:flutter/material.dart';

import '../core/animals.dart';
import '../core/fa_icons.dart';
import '../growth/growth_service.dart';

/// 成长统计 UI 组件集：宠物浮层卡片与设置页成长档案浏览器共用，
/// 消除同一 UI 的两份实现。数据源统一为只读的 [GrowthSnapshot]
/// （活跃动物用 `GrowthService.toSnapshot()` 生成）。
///
/// 所有 Text 显式 decoration:none（宠物浮层无 DefaultTextStyle 兜底，
/// 必须显式；在 Material 上下文里与默认效果一致）。

/// 头部行：emoji + 名字 + 等级徽章。
class GrowthHeaderRow extends StatelessWidget {
  const GrowthHeaderRow({super.key, required this.animal, required this.level});

  final AnimalInfo animal;
  final int level;

  @override
  Widget build(BuildContext context) {
    final color = animal.themeColor;
    return Row(
      children: [
        Text(animal.emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 6),
        Text(animal.name,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color.alphaBlend(
                    Colors.black.withValues(alpha: 0.25), color),
                decoration: TextDecoration.none)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              color,
              Color.lerp(color, Colors.white, 0.25)!,
            ]),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text('Lv.$level',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  decoration: TextDecoration.none)),
        ),
      ],
    );
  }
}

/// 统计主体：经验行 + 经验条 + 各统计行。
class GrowthStatsBody extends StatelessWidget {
  const GrowthStatsBody({
    super.key,
    required this.animal,
    required this.stats,
    this.showFeedings = false,
  });

  final AnimalInfo animal;
  final GrowthSnapshot stats;

  /// 是否展示「喂食次数」行（宠物卡片展示，设置页保持原布局不展示）
  final bool showFeedings;

  static String moodEmoji(int mood) {
    if (mood >= 80) return '😊';
    if (mood >= 50) return '🙂';
    return '😔';
  }

  @override
  Widget build(BuildContext context) {
    final color = animal.themeColor;
    final days = DateTime.now().difference(stats.createdAt).inDays + 1;
    final hours = stats.totalOnlineMinutes ~/ 60;
    final mins = stats.totalOnlineMinutes % 60;
    final progress = (stats.exp / stats.expToNext).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(Fa7.star, '经验', '${stats.exp}/${stats.expToNext}', color),
        const SizedBox(height: 2),
        Stack(
          children: [
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F0F3),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            FractionallySizedBox(
              widthFactor: progress <= 0 ? 0.001 : progress,
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    color,
                    Color.lerp(color, Colors.white, 0.35)!,
                  ]),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _row(Fa7.faceSmile, '心情',
            '${moodEmoji(stats.mood)} ${stats.mood}/100', color),
        _row(Fa7.handPointer, '互动次数', '${stats.totalInteractions}', color),
        if (showFeedings)
          _row(Fa7.bone, '喂食次数', '${stats.totalFeedings}', color),
        _row(Fa7.clock, '陪伴时长', '$hours小时$mins分钟', color),
        _row(Fa7.calendarDays, '相识天数', '$days天', color),
      ],
    );
  }

  Widget _row(IconData icon, String k, String v, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          children: [
            Icon(icon, size: 12, color: color.withValues(alpha: 0.55)),
            const SizedBox(width: 6),
            Text(k,
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8A8A8A),
                    decoration: TextDecoration.none,
                    fontWeight: FontWeight.normal)),
            const Spacer(),
            Text(v,
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF3A3A3A),
                    decoration: TextDecoration.none,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

/// 完整面板 = 头部行 + 统计主体（设置页成长档案直接使用）。
class GrowthStatsPanel extends StatelessWidget {
  const GrowthStatsPanel({
    super.key,
    required this.animal,
    required this.stats,
    this.showFeedings = false,
  });

  final AnimalInfo animal;
  final GrowthSnapshot stats;
  final bool showFeedings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GrowthHeaderRow(animal: animal, level: stats.level),
        const SizedBox(height: 8),
        GrowthStatsBody(
            animal: animal, stats: stats, showFeedings: showFeedings),
      ],
    );
  }
}
