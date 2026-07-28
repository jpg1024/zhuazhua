import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 单张透明底图片的"伪3D"展示：透视左右摆动 + 地面椭圆阴影。
class Pseudo3DImage extends StatefulWidget {
  final String path;
  final double size;

  const Pseudo3DImage({super.key, required this.path, required this.size});

  @override
  State<Pseudo3DImage> createState() => _Pseudo3DImageState();
}

class _Pseudo3DImageState extends State<Pseudo3DImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sway;
  late final CurvedAnimation _curve;

  @override
  void initState() {
    super.initState();
    _sway = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 4500))
      ..repeat(reverse: true);
    _curve = CurvedAnimation(parent: _sway, curve: Curves.easeInOutSine);
  }

  @override
  void dispose() {
    _curve.dispose();
    _sway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _curve,
        child: Image.file(
          File(widget.path),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          cacheWidth: (widget.size * dpr).round(),
          gaplessPlayback: true,
          errorBuilder: (_, e, s) =>
              const Center(child: Text('🖼️', style: TextStyle(fontSize: 48))),
        ),
        builder: (context, child) {
          final t = _curve.value * 2 - 1; // -1..1
          final angle = t * 0.10;
          return Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                bottom: 0,
                child: Transform.translate(
                  offset: Offset(-t * widget.size * 0.06, 0),
                  child: Container(
                    width: widget.size * 0.62,
                    height: widget.size * 0.10,
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(widget.size * 0.05),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0015)
                  ..rotateY(angle)
                  ..rotateX(math.sin(_curve.value * math.pi) * 0.02),
                child: Padding(
                  padding: EdgeInsets.only(bottom: widget.size * 0.04),
                  child: child,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
