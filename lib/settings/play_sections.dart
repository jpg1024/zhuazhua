import 'package:flutter/material.dart';

import '../core/achievements.dart';
import '../core/daily_tasks.dart';
import '../core/fa_icons.dart';
import '../pet/pet_controller.dart';

const Color _accent = Color(0xFF5C6BC0);

/// 设置页「陪伴玩法」区块：番茄钟控制、每日任务进度、成就墙。
class PlaySections extends StatelessWidget {
  final PetController pet;

  const PlaySections({super.key, required this.pet});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(Fa7.stopwatch, '番茄钟'),
        const SizedBox(height: 8),
        _PomodoroCard(pet: pet),
        const Divider(height: 32),
        _header(Fa7.listCheck, '每日任务'),
        const SizedBox(height: 8),
        _DailyTasksCard(daily: pet.daily),
        const Divider(height: 32),
        _header(Fa7.trophy, '成就'),
        const SizedBox(height: 8),
        _AchievementsCard(achievements: pet.achievements),
      ],
    );
  }

  Widget _header(IconData icon, String title) => Row(
        children: [
          Icon(icon, size: 14, color: _accent),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      );
}

class _PomodoroCard extends StatelessWidget {
  final PetController pet;

  const _PomodoroCard({required this.pet});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListenableBuilder(
        listenable: pet,
        builder: (context, _) {
          final running = pet.pomoRunning;
          final String status;
          if (!running) {
            status = '未开始';
          } else if (pet.pomoPhase == PomoPhase.focus) {
            final m = pet.pomoRemaining ~/ 60;
            final s = pet.pomoRemaining % 60;
            status = '🍅 专注中 $m:${s.toString().padLeft(2, '0')}';
          } else {
            final m = pet.pomoRemaining ~/ 60;
            final s = pet.pomoRemaining % 60;
            status = '☕ 休息中 $m:${s.toString().padLeft(2, '0')}';
          }
          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('专注 25 分钟 → 休息 5 分钟',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(
                        running
                            ? status
                            : '完成后宠物奖励经验，还会累计成就与每日任务进度。',
                        style: const TextStyle(
                            fontSize: 11.5, color: Colors.black54)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: pet.togglePomodoro,
                style: FilledButton.styleFrom(
                  backgroundColor: running ? const Color(0xFFE5534B) : _accent,
                ),
                icon: Icon(
                    running ? Fa7.stop : Fa7.stopwatch,
                    size: 13),
                label: Text(running ? '停止' : '开始',
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DailyTasksCard extends StatelessWidget {
  final DailyTaskService daily;

  const _DailyTasksCard({required this.daily});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListenableBuilder(
        listenable: daily,
        builder: (context, _) {
          final doneCount = daily.doneCount;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('今日进度 $doneCount/${kDailyTasks.length}',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  const Text('每日 0 点重置',
                      style: TextStyle(fontSize: 11, color: Colors.black38)),
                ],
              ),
              const SizedBox(height: 8),
              for (final t in kDailyTasks) _taskRow(t),
            ],
          );
        },
      ),
    );
  }

  Widget _taskRow(DailyTaskDef t) {
    final count = daily.countOf(t.id);
    final done = daily.isDone(t.id);
    final progress = (count / t.target).clamp(0.0, 1.0);
    final rewardText = [
      if (t.rewardExp > 0) '经验+${t.rewardExp}',
      if (t.rewardMood > 0) '心情+${t.rewardMood}',
    ].join(' ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: done
                  ? const Color(0xFF4CAF50).withValues(alpha: 0.15)
                  : _accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(done ? Fa7.circleCheck : t.icon,
                size: 12,
                color: done ? const Color(0xFF4CAF50) : _accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(t.name,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Text('${count.clamp(0, t.target)}/${t.target} ${t.unit}',
                        style: const TextStyle(
                            fontSize: 11.5, color: Colors.black45)),
                    const Spacer(),
                    Text(done ? '已完成' : '奖励 $rewardText',
                        style: TextStyle(
                            fontSize: 11,
                            color: done
                                ? const Color(0xFF4CAF50)
                                : Colors.black38)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor: Colors.black.withValues(alpha: 0.06),
                    color: done ? const Color(0xFF4CAF50) : _accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementsCard extends StatelessWidget {
  final AchievementsService achievements;

  const _AchievementsCard({required this.achievements});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListenableBuilder(
        listenable: achievements,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('已解锁 ${achievements.unlockedCount}/${kAchievements.length}',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in kAchievements) _achievementChip(a),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _achievementChip(AchievementDef a) {
    final unlocked = achievements.isUnlocked(a.id);
    final at = achievements.unlockedAt(a.id);
    final color = unlocked ? const Color(0xFFE8A13C) : Colors.black26;
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: unlocked
            ? const Color(0xFFE8A13C).withValues(alpha: 0.12)
            : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        children: [
          Icon(unlocked ? a.icon : Fa7.lock, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.name,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: unlocked
                            ? const Color(0xFF6B4A1E)
                            : Colors.black45)),
                Text(
                  unlocked && at != null
                      ? '${at.month}/${at.day} 解锁'
                      : a.desc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: Colors.black45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
