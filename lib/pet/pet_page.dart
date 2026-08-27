import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';

import '../core/animals.dart';
import '../core/click_through.dart';
import '../core/config.dart';
import '../core/fa_icons.dart';
import '../growth/growth_service.dart';
import '../skin/model_pet_view.dart';
import '../skin/pseudo3d_image.dart';
import 'pet_controller.dart';

class PetPage extends StatefulWidget {
  final PetController controller;
  final VoidCallback onOpenSettings;
  final VoidCallback onExit;
  final ValueChanged<bool>? onHoverChanged;
  final VoidCallback? onDragStart;

  const PetPage({
    super.key,
    required this.controller,
    required this.onOpenSettings,
    required this.onExit,
    this.onHoverChanged,
    this.onDragStart,
  });

  @override
  State<PetPage> createState() => _PetPageState();
}

class _PetPageState extends State<PetPage> with TickerProviderStateMixin {
  late final AnimationController _breath;
  late final Animation<double> _breathCurve;
  late final AnimationController _bounce;
  late final AnimationController _blink;
  late final AnimationController _menu;
  late final AnimationController _spin;
  late final Animation<double> _spinCurve;
  late final AnimationController _yawn;
  late final AnimationController _feed;

  // Patrol animation controllers
  late final AnimationController _patrolFade;
  late final AnimationController _patrolWave;
  Timer? _patrolMoveTimer;
  Offset _patrolOrigin = Offset.zero;
  String _patrolPhase = 'idle'; // idle, entering, patrolling, exiting
  bool _patrolFlipX = false;

  bool _menuOpen = false;
  bool _hoverSpun = false;
  Offset _menuPos = const Offset(8, 8);

  PetController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(reverse: true);
    _breathCurve =
        CurvedAnimation(parent: _breath, curve: Curves.easeInOutSine);
    _bounce = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 620));
    _blink = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _menu = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _spin = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000));
    _spinCurve =
        CurvedAnimation(parent: _spin, curve: Curves.easeInOutCubic);
    _yawn = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500));
    _feed = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _patrolFade = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _patrolWave = AnimationController(
        vsync: this,
        duration: Duration(
            milliseconds: c.animal.hasWings ? 5000 : 4000));
    c.addListener(_onState);
    final ct = ClickThroughService.instance;
    ct.hitRectProvider = _petHitRect;
    ct.start();
  }

  // 动物 bottom:8、水平居中、边长 96*scale；四周留余量（顶部含跳跃 -26px）
  Rect _petHitRect() {
    const w = 280.0, h = 380.0;
    final size = 96 * c.petScale;
    final left = (w - size) / 2 - 8;
    final top = h - 8 - size - 30;
    return Rect.fromLTWH(left, top, size + 16, size + 38);
  }

  PetState? _prev;
  bool _wasSleeping = false;

  void _onState() {
    if (c.state == PetState.happy && _prev != PetState.happy) {
      _bounce.forward(from: 0);
    }
    if (c.state == PetState.blink && _prev != PetState.blink) {
      _blink.forward(from: 0);
    }
    if (c.state == PetState.eat && _prev != PetState.eat) {
      _feed.forward(from: 0);
      _bounce.forward(from: 0);
    }
    if (c.state == PetState.yawn && _prev != PetState.yawn) {
      _yawn.forward(from: 0);
    }
    if (c.state == PetState.jump && _prev != PetState.jump) {
      _bounce.forward(from: 0);
    }
    if (c.state == PetState.spin && _prev != PetState.spin) {
      _spin.forward(from: 0);
    }
    final sleeping = c.state == PetState.sleep;
    if (sleeping != _wasSleeping) {
      if (sleeping) {
        _breath.animateTo(0,
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOut);
      } else {
        _breath.repeat(reverse: true);
      }
      _wasSleeping = sleeping;
    }
    // Patrol state transitions
    if (c.state == PetState.patrol && _prev != PetState.patrol) {
      _startPatrolAnimation();
    } else if (c.state != PetState.patrol && _prev == PetState.patrol) {
      _stopPatrolAnimation();
    }
    _prev = c.state;
  }

  @override
  void dispose() {
    c.removeListener(_onState);
    _patrolMoveTimer?.cancel();
    ClickThroughService.instance.stop();
    _breath.dispose();
    _bounce.dispose();
    _blink.dispose();
    _menu.dispose();
    _spin.dispose();
    _yawn.dispose();
    _feed.dispose();
    _patrolFade.dispose();
    _patrolWave.dispose();
    super.dispose();
  }

  static const double _menuWidth = 188;

  /// 菜单实际最大高度（压缩后的菜单 ≈299px，留余量用于位置钳制）
  static const double _menuHeight = 320;

  void _openMenu(Offset local) {
    const w = 280.0, h = 380.0;
    final dx = local.dx.clamp(8.0, w - _menuWidth - 8.0);
    // 窗口高 380，菜单高 320：dy 上限为 52，保证 clamp 范围有效且菜单不越窗
    final dy = local.dy.clamp(8.0, h - _menuHeight - 8.0);
    setState(() {
      _menuPos = Offset(dx, dy);
      _menuOpen = true;
    });
    ClickThroughService.instance.forceInteractive = true;
    _menu.forward(from: 0);
  }

  void _closeMenu() {
    if (!_menuOpen) return;
    _menu.reverse().whenComplete(() {
      ClickThroughService.instance.forceInteractive = false;
      if (mounted) setState(() => _menuOpen = false);
    });
  }

  void _select(String value) {
    _closeMenu();
    switch (value) {
      case 'interact':
        c.interact();
      case 'feed':
        c.feed();
      case 'growth':
        c.toggleGrowthCard();
      case 'pomodoro':
        c.togglePomodoro();
      case 'zoomIn':
        c.adjustScale(0.2);
      case 'zoomOut':
        c.adjustScale(-0.2);
      case 'settings':
        widget.onOpenSettings();
      case 'exit':
        widget.onExit();
    }
  }

  // ── Patrol animation ─────────────────────────────────────────────────────

  Future<void> _startPatrolAnimation() async {
    _patrolPhase = 'entering';
    _patrolOrigin = await windowManager.getPosition();

    // 1. 淡出
    await _patrolFadeOut();

    // 2. 根据方向瞬移窗口
    final dir = c.patrolActualDirection;
    _patrolFlipX = dir == 'left';
    final target = _patrolOrigin.translate(dir == 'left' ? 100 : -100, 0);
    await windowManager.setPosition(target);

    // 3. 淡入
    await _patrolFadeIn();

    // 4. 开始巡逻移动 + 飞/跑波浪动画
    _patrolPhase = 'patrolling';
    _patrolWave.repeat(reverse: false);
    _patrolMoveTimer = Timer.periodic(
        const Duration(milliseconds: 16), (_) => _updatePatrolPosition());
  }

  Future<void> _stopPatrolAnimation() async {
    _patrolPhase = 'exiting';
    _patrolMoveTimer?.cancel();
    _patrolWave.stop();

    // 1. 淡出
    await _patrolFadeOut();

    // 2. 回到原位
    await windowManager.setPosition(_patrolOrigin);

    // 3. 淡入
    await _patrolFadeIn();

    _patrolPhase = 'idle';
    _patrolFlipX = false;
    c.onPatrolReturned();
  }

  Future<void> _patrolFadeOut() {
    return _patrolFade.forward(from: 0).orCancel.then((_) {});
  }

  Future<void> _patrolFadeIn() {
    return _patrolFade.reverse(from: 1).orCancel.then((_) {});
  }

  void _updatePatrolPosition() {
    if (_patrolPhase != 'patrolling') return;
    final t = _patrolWave.value;
    final dir = c.patrolActualDirection;
    // sin 曲线在 200px 范围内来回移动
    final sinVal = math.sin(t * 2 * math.pi);
    // 'left': 从 +100 向 -100 移动（宠物从右侧进入）
    // 'right': 从 -100 向 +100 移动（宠物从左侧进入）
    final actualDx = dir == 'left'
        ? 100 - sinVal * 100   // 100 → 0 → -100 → 0 → 100
        : -100 + sinVal * 100; // -100 → 0 → 100 → 0 → -100
    windowManager.setPosition(_patrolOrigin.translate(actualDx, 0));
  }

  Widget _buildMenu(AnimalInfo animal) {
    final color = animal.themeColor;
    final tintTop = Color.alphaBlend(color.withValues(alpha: 0.08), Colors.white);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: _menuWidth,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [tintTop, Colors.white],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.22),
                blurRadius: 24,
                offset: const Offset(0, 10)),
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _menuTile('interact', Fa7.handPointer, '互动一下', color),
            _menuTile('feed', Fa7.bone, '喂食', color),
            _menuTile('growth', Fa7.chartLine, '成长记录', color),
            _menuDivider(color),
            _menuTile('pomodoro', Fa7.stopwatch,
                c.pomoRunning ? '停止番茄钟' : '番茄钟', color),
            _menuDivider(color),
            _menuTile('zoomIn', Fa7.magnifyingGlassPlus, '放大', color),
            _menuTile('zoomOut', Fa7.magnifyingGlassMinus, '缩小', color),
            _menuDivider(color),
            _menuTile('settings', Fa7.gear, '设置', color),
            _menuTile('exit', Fa7.rightFromBracket, '退出', color),
          ],
        ),
      ),
    );
  }

  Widget _menuDivider(Color color) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              color.withValues(alpha: 0),
              color.withValues(alpha: 0.18),
              color.withValues(alpha: 0),
            ]),
          ),
        ),
      );

  Widget _menuTile(String value, IconData icon, String label, Color color) {
    final danger = value == 'exit';
    final tint = danger ? const Color(0xFFE5534B) : color;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        onTap: () => _select(value),
        borderRadius: BorderRadius.circular(12),
        hoverColor: tint.withValues(alpha: 0.09),
        splashColor: tint.withValues(alpha: 0.16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      tint.withValues(alpha: 0.22),
                      tint.withValues(alpha: 0.10),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 12, color: tint),
              ),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: danger ? tint : const Color(0xFF444444),
                      decoration: TextDecoration.none)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final animal = c.animal;
    ClickThroughService.instance.devicePixelRatio =
        MediaQuery.of(context).devicePixelRatio;
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            final Widget topSlot = c.showGrowthCard
                ? Padding(
                    key: const ValueKey('card'),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: _GrowthCard(growth: c.growth, animal: animal))
                : (c.bubbleText != null
                    ? Padding(
                        key: ValueKey(c.bubbleText),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: _Bubble(
                            text: c.bubbleText!, color: animal.themeColor))
                    : const SizedBox.shrink(key: ValueKey('empty')));
            return Positioned(
              // 紧贴动物头顶显示（动物 bottom:8，高约 96*scale）；上限防止超出窗口
              bottom: math.min(
                  8 + 96 * c.petScale + 10, c.showGrowthCard ? 140 : 270),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.8, end: 1.0).animate(anim),
                    alignment: Alignment.bottomCenter,
                    child: child,
                  ),
                ),
                child: topSlot,
              ),
            );
          },
        ),
        Positioned(
          bottom: 8,
          child: RepaintBoundary(
            child: MouseRegion(
              onEnter: (_) {
                widget.onHoverChanged?.call(true);
                if (_hoverSpun ||
                    _spin.isAnimating ||
                    c.state == PetState.sleep) {
                  return;
                }
                _hoverSpun = true;
                _spin.forward(from: 0);
              },
              onExit: (_) {
                _hoverSpun = false;
                widget.onHoverChanged?.call(false);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: c.interact,
                onDoubleTap: c.toggleGrowthCard,
                onPanStart: (_) {
                  widget.onDragStart?.call();
                  windowManager.startDragging();
                },
                onSecondaryTapUp: (d) => _openMenu(d.localPosition),
                child: AnimatedBuilder(
                  animation: Listenable.merge(
                      [_breathCurve, _bounce, _blink, _spinCurve, _yawn, _feed, _patrolFade, _patrolWave]),
                  child: ListenableBuilder(
                    listenable: Listenable.merge([c, c.growth]),
                    builder: (context, _) => _PetVisual(
                        animal: animal,
                        skin: c.config.skinOf(animal.id),
                        sleeping: c.state == PetState.sleep,
                        scale: c.petScale),
                  ),
                  builder: (context, child) {
                    final breathScale = 1.0 + _breathCurve.value * 0.035;
                    final jump = math.sin(math.pi * _bounce.value);
                    final bounceY = -26 * jump;
                    final blinkAmount = math.sin(math.pi * _blink.value);
                    final squishY = 1.0 - 0.12 * blinkAmount;
                    final squishX = 1.0 + 0.06 * blinkAmount;
                    final stretch = 1.0 + 0.05 * jump;
                    final spinAngle = _spinCurve.value * 2 * math.pi * 2;
                    final st = _spinCurve.value;
                    final spinShrink = st < 0.35
                        ? 1.0 - 0.9 * (st / 0.35)
                        : 0.1 +
                            0.9 *
                                Curves.easeInOut
                                    .transform((st - 0.35) / 0.65);
                    // 打哈欠：先拉长（scaleY↑）再回落，附轻微侧倾
                    final yawnWave = math.sin(math.pi * _yawn.value);
                    final yawnScaleY = 1.0 + 0.07 * yawnWave;
                    final yawnTilt = 0.06 * yawnWave;
                    // 心情低落：idle 时无精打采地歪着
                    final moodTilt =
                        c.growth.mood < 40 && c.state == PetState.idle
                            ? 0.10
                            : 0.0;

                    // Patrol transforms
                    final isPatrol = _patrolPhase != 'idle';
                    final waveT = _patrolWave.value;
                    final hasWings = c.animal.hasWings;

                    // 透明度：
                    // - entering/exiting 阶段用 _patrolFade 做过渡淡出淡入
                    // - patrolling 阶段按位置：中心最亮，两端淡出（消失→重现效果）
                    double patrolOpacity;
                    if (_patrolPhase == 'patrolling') {
                      final sinVal = math.sin(waveT * 2 * math.pi);
                      // sinVal 在 [-1, 1]，|sinVal| 越接近 1 越靠近边缘
                      patrolOpacity = 1.0 - sinVal * sinVal;
                    } else if (isPatrol) {
                      patrolOpacity = 1.0 - _patrolFade.value;
                    } else {
                      patrolOpacity = 1.0;
                    }

                    // 飞翔：大幅度波浪起伏 + 翅膀扇动(scaleY)
                    // 奔跑：小幅度颠簸 + 轻微倾斜
                    final patrolBob = isPatrol
                        ? math.sin(waveT * 2 * math.pi) *
                            (hasWings ? 12.0 : 5.0)
                        : 0.0;
                    final patrolTilt = isPatrol && !hasWings
                        ? math.cos(waveT * 2 * math.pi) * 0.12
                        : 0.0;
                    final wingFlap = isPatrol && hasWings
                        ? 1.0 + math.sin(waveT * 4 * math.pi) * 0.15
                        : 1.0;

                    return Opacity(
                      opacity: patrolOpacity.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, bounceY + patrolBob),
                        child: Transform.rotate(
                          angle: spinAngle + patrolTilt + yawnTilt + moodTilt,
                          child: Transform.scale(
                            scaleY: breathScale *
                                squishY *
                                stretch *
                                spinShrink *
                                wingFlap *
                                yawnScaleY,
                            scaleX: squishX *
                                (2 - stretch).clamp(0.9, 1.1) *
                                spinShrink,
                            child: Transform.flip(
                              flipX: _patrolFlipX,
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: c,
          builder: (context, _) => c.state == PetState.sleep
              ? const Positioned(
                  bottom: 88,
                  right: 52,
                  child: Text('💤', style: TextStyle(fontSize: 22)))
              : const Positioned(bottom: 0, child: SizedBox.shrink()),
        ),
        // 喂食：动物专属食物从头顶落下
        ListenableBuilder(
          listenable: c,
          builder: (context, _) => c.state == PetState.eat
              ? Positioned(
                  bottom: 8 + 96 * c.petScale + 14,
                  child: AnimatedBuilder(
                    animation: _feed,
                    builder: (context, _) {
                      final v =
                          Curves.easeIn.transform(_feed.value.clamp(0.0, 1.0));
                      return Opacity(
                        opacity: (1 - v * 0.6).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, -46 * (1 - v)),
                          child: Text(c.feedingFood,
                              style: const TextStyle(fontSize: 26)),
                        ),
                      );
                    },
                  ),
                )
              : const Positioned(bottom: 0, child: SizedBox.shrink()),
        ),
        // 番茄钟倒计时 chip
        ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            if (!c.pomoRunning) {
              return const Positioned(bottom: 0, child: SizedBox.shrink());
            }
            final m = c.pomoRemaining ~/ 60;
            final s = c.pomoRemaining % 60;
            final focus = c.pomoPhase == PomoPhase.focus;
            final color = focus ? const Color(0xFFE5534B) : const Color(0xFF4CAF50);
            return Positioned(
              top: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: [
                    BoxShadow(
                        color: color.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4)),
                  ],
                ),
                child: Text(
                  '${focus ? '🍅' : '☕'} $m:${s.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4A4A4A),
                      decoration: TextDecoration.none),
                ),
              ),
            );
          },
        ),
        if (_menuOpen) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeMenu,
              onSecondaryTap: _closeMenu,
            ),
          ),
          Positioned(
            left: _menuPos.dx,
            top: _menuPos.dy,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _menu,
                builder: (context, child) {
                  final v = _menu.value.clamp(0.0, 1.0);
                  final s = 0.9 + 0.1 * Curves.easeOutBack.transform(v);
                  return Opacity(
                    opacity: v,
                    child: Transform.translate(
                      offset: Offset(0, -6 * (1 - v)),
                      child: Transform.scale(
                        scale: s,
                        alignment: Alignment.topLeft,
                        child: child,
                      ),
                    ),
                  );
                },
                child: _buildMenu(animal),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PetVisual extends StatelessWidget {
  final AnimalInfo animal;
  final AnimalSkin skin;
  final bool sleeping;
  final double scale;

  const _PetVisual(
      {required this.animal,
      required this.skin,
      required this.sleeping,
      this.scale = 1.0});

  // 皮肤文件存在性缓存：路径带时间戳，换肤即换 key，避免每帧同步 I/O
  static final Map<String, bool> _fileExistsCache = {};
  static bool _skinFileExists(String path) =>
      _fileExistsCache.putIfAbsent(path, () => File(path).existsSync());

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final size = 96 * scale;

    Widget visual;
    if (skin.modelPath != null && _skinFileExists(skin.modelPath!)) {
      visual = ModelPetView(objPath: skin.modelPath!, size: size);
    } else if (skin.imagePath != null && _skinFileExists(skin.imagePath!)) {
      visual = Pseudo3DImage(path: skin.imagePath!, size: size);
    } else {
      visual = SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          'assets/animals/${animal.id}.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          cacheWidth: (size * dpr).round(),
          gaplessPlayback: true,
          errorBuilder: (_, e, s) => _svgFallback(),
        ),
      );
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 600),
      opacity: sleeping ? 0.7 : 1.0,
      child: visual,
    );
  }

  Widget _svgFallback() => SvgPicture.asset(
        'assets/animals/${animal.id}.svg',
        fit: BoxFit.contain,
        placeholderBuilder: (_) => Center(
          child: Text(animal.emoji, style: const TextStyle(fontSize: 70)),
        ),
      );
}

class _Bubble extends StatelessWidget {
  final String text;
  final Color color;

  const _Bubble({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final bottomTint =
        Color.alphaBlend(color.withValues(alpha: 0.08), Colors.white);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 210),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, bottomTint],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.15), width: 1),
            boxShadow: [
              BoxShadow(
                  color: color.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6)),
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Text(
            text,
            style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Color(0xFF4A4A4A),
                decoration: TextDecoration.none,
                fontWeight: FontWeight.w500),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -5),
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: bottomTint,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                    color: color.withValues(alpha: 0.15), width: 1),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GrowthCard extends StatelessWidget {
  final GrowthService growth;
  final AnimalInfo animal;

  const _GrowthCard({required this.growth, required this.animal});

  @override
  Widget build(BuildContext context) {
    final color = animal.themeColor;
    final days = DateTime.now().difference(growth.createdAt).inDays + 1;
    final hours = growth.totalOnlineMinutes ~/ 60;
    final mins = growth.totalOnlineMinutes % 60;
    final progress = (growth.exp / growth.expToNext).clamp(0.0, 1.0);
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.22),
              blurRadius: 24,
              offset: const Offset(0, 10)),
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.18),
                  color.withValues(alpha: 0.04),
                ],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      color,
                      Color.lerp(color, Colors.white, 0.25)!,
                    ]),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text('Lv.${growth.level}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          decoration: TextDecoration.none)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _row(Fa7.star, '经验', '${growth.exp}/${growth.expToNext}',
                    color),
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
                    '${_moodEmoji(growth.mood)} ${growth.mood}/100', color),
                _row(Fa7.handPointer, '互动次数', '${growth.totalInteractions}',
                    color),
                _row(Fa7.bone, '喂食次数', '${growth.totalFeedings}', color),
                _row(Fa7.clock, '陪伴时长', '$hours小时$mins分钟', color),
                _row(Fa7.calendarDays, '相识天数', '$days天', color),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _moodEmoji(int mood) {
    if (mood >= 80) return '😊';
    if (mood >= 50) return '🙂';
    return '😔';
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
