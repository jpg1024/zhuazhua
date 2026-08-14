import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/keyboard_hook.dart';

/// 打字旋转配饰 Widget。
/// CustomPainter 手绘 3D 质感球体，打字时根据速度旋转，闲置时轻微上下浮动。
class SpinningAccessory extends StatefulWidget {
  final String type; // 'soccer', 'basketball', 'globe'
  final String position; // 'topLeft', 'topRight'

  const SpinningAccessory({
    super.key,
    required this.type,
    required this.position,
  });

  @override
  State<SpinningAccessory> createState() => _SpinningAccessoryState();
}

class _SpinningAccessoryState extends State<SpinningAccessory> {
  StreamSubscription<double>? _sub;
  double _speed = 0.0;
  double _angle = 0.0;
  double _bobPhase = 0.0;
  Timer? _ticker;

  static const double _size = 38.0;
  static const double _maxDegPerSec = 180.0;

  @override
  void initState() {
    super.initState();
    _sub = KeyboardHookService.instance.typingSpeedStream.listen((v) {
      if (mounted) setState(() => _speed = v);
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted) return;
      // 旋转：速度驱动
      _angle += (_speed * _maxDegPerSec) * (math.pi / 180) * 0.016;
      if (_angle > math.pi * 200) _angle -= math.pi * 200;
      // 浮动：始终轻微上下漂浮
      _bobPhase += 0.035;
      if (_bobPhase > math.pi * 2) _bobPhase -= math.pi * 2;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  Color get _mainColor {
    switch (widget.type) {
      case 'basketball':
        return const Color(0xFFE65100);
      case 'globe':
        return const Color(0xFF1565C0);
      default:
        return const Color(0xFF455A64);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bob = math.sin(_bobPhase) * 2.5;
    return IgnorePointer(
      child: Transform.translate(
        offset: Offset(0, bob),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: _angle,
              child: CustomPaint(
                size: const Size(_size, _size),
                painter: switch (widget.type) {
                  'basketball' => _BasketballPainter(_mainColor),
                  'globe' => _GlobePainter(),
                  _ => _SoccerPainter(),
                },
              ),
            ),
            const SizedBox(height: 3),
            // 地面阴影
            CustomPaint(
              size: const Size(22, 6),
              painter: _ShadowPainter(_mainColor),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 足球 ────────────────────────────────────────────────────────────────────
// 白色球体 + 黑色五边形拼块 + 3D 渐变 + 高光

class _SoccerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // 球体基底：偏移径向渐变模拟 3D 光照
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.35),
            radius: 1.3,
            colors: const [
              Color(0xFFFFFFFF),
              Color(0xFFF0F0F0),
              Color(0xFFBDBDBD),
              Color(0xFF757575),
            ],
            stops: const [0.0, 0.35, 0.7, 1.0],
          ).createShader(Rect.fromCircle(center: c, radius: r)));

    // 黑色五边形拼块
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    final patch = r * 0.22;
    _pentagon(canvas, c, patch, const Color(0xFF263238));
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 5;
      _pentagon(
        canvas,
        Offset(c.dx + math.cos(a) * r * 0.58, c.dy + math.sin(a) * r * 0.58),
        patch * 0.72,
        const Color(0xFF37474F),
      );
    }
    canvas.restore();

    // 边缘暗角
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.12)],
          ).createShader(Rect.fromCircle(center: c, radius: r)));

    // 高光
    canvas.drawCircle(
      c.translate(-r * 0.28, -r * 0.3),
      r * 0.17,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
  }

  void _pentagon(
      Canvas canvas, Offset center, double radius, Color color) {
    final path = Path();
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 5;
      final p = Offset(
        center.dx + math.cos(a) * radius,
        center.dy + math.sin(a) * radius,
      );
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(_) => true;
}

// ─── 篮球 ────────────────────────────────────────────────────────────────────
// 橙色球体 + 十字缝线 + 弧形纹 + 3D 渐变 + 高光

class _BasketballPainter extends CustomPainter {
  final Color color;
  _BasketballPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // 球体
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.25, -0.3),
            radius: 1.2,
            colors: [
              const Color(0xFFFFCC80),
              color,
              Color.lerp(color, Colors.black, 0.35)!,
            ],
            stops: const [0.0, 0.45, 1.0],
          ).createShader(Rect.fromCircle(center: c, radius: r)));

    // 缝线
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    final seam = Paint()
      ..color = const Color(0xFF3E2723).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // 十字
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), seam);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), seam);

    // 左右弧线
    final curveL = Path()
      ..moveTo(c.dx - r * 0.35, c.dy - r * 0.88)
      ..quadraticBezierTo(
          c.dx - r * 0.78, c.dy, c.dx - r * 0.35, c.dy + r * 0.88);
    canvas.drawPath(curveL, seam);
    final curveR = Path()
      ..moveTo(c.dx + r * 0.35, c.dy - r * 0.88)
      ..quadraticBezierTo(
          c.dx + r * 0.78, c.dy, c.dx + r * 0.35, c.dy + r * 0.88);
    canvas.drawPath(curveR, seam);
    canvas.restore();

    // 高光
    canvas.drawCircle(
      c.translate(-r * 0.22, -r * 0.28),
      r * 0.15,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  @override
  bool shouldRepaint(_) => true;
}

// ─── 地球仪 ──────────────────────────────────────────────────────────────────
// 蓝色海洋 + 绿色大陆斑块 + 经纬网格 + 3D 渐变 + 高光

class _GlobePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // 海洋
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.2, -0.25),
            radius: 1.2,
            colors: const [
              Color(0xFF64B5F6),
              Color(0xFF1E88E5),
              Color(0xFF0D47A1),
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(Rect.fromCircle(center: c, radius: r)));

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));

    // 大陆斑块
    final land = Paint()..color = const Color(0xFF43A047).withValues(alpha: 0.6);
    canvas.drawCircle(c.translate(-r * 0.2, -r * 0.15), r * 0.28, land);
    canvas.drawCircle(c.translate(r * 0.3, r * 0.1), r * 0.22, land);
    canvas.drawCircle(c.translate(-r * 0.05, r * 0.42), r * 0.16, land);
    canvas.drawCircle(c.translate(r * 0.35, -r * 0.35), r * 0.14, land);

    // 经纬网格
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    for (var i = -2; i <= 2; i++) {
      final y = c.dy + i * r * 0.32;
      final hw = math.sqrt(
          (r * r - (y - c.dy) * (y - c.dy)).clamp(0.0, r * r));
      if (hw > 0) {
        canvas.drawLine(Offset(c.dx - hw, y), Offset(c.dx + hw, y), grid);
      }
    }
    for (var i = -2; i <= 2; i++) {
      final x = c.dx + i * r * 0.32;
      final hh = math.sqrt(
          (r * r - (x - c.dx) * (x - c.dx)).clamp(0.0, r * r));
      if (hh > 0) {
        canvas.drawLine(Offset(x, c.dy - hh), Offset(x, c.dy + hh), grid);
      }
    }
    canvas.restore();

    // 边缘暗角
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.18)
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r)));

    // 高光
    canvas.drawCircle(
      c.translate(-r * 0.25, -r * 0.3),
      r * 0.14,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
  }

  @override
  bool shouldRepaint(_) => true;
}

// ─── 地面阴影 ────────────────────────────────────────────────────────────────

class _ShadowPainter extends CustomPainter {
  final Color tint;
  _ShadowPainter(this.tint);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawOval(
      Rect.fromCenter(center: c, width: size.width, height: size.height),
      Paint()
        ..color = tint.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  @override
  bool shouldRepaint(_) => false;
}
