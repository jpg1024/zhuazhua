import 'package:flutter/material.dart' hide Material;
import 'package:flutter/material.dart' as m show Material, MaterialType;
import 'package:flutter_cube/flutter_cube.dart';

/// OBJ 模型宠物视图：纯 Dart 渲染 + 左右摆动 + 地面椭圆阴影。
class ModelPetView extends StatefulWidget {
  final String objPath;
  final double size;

  const ModelPetView({super.key, required this.objPath, required this.size});

  @override
  State<ModelPetView> createState() => _ModelPetViewState();
}

class _ModelPetViewState extends State<ModelPetView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sway;
  Scene? _scene;
  Object? _model;

  @override
  void initState() {
    super.initState();
    _sway = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 4500))
      ..repeat(reverse: true);
    _sway.addListener(_tick);
  }

  void _tick() {
    final model = _model;
    if (model == null) return;
    final t = Curves.easeInOutSine.transform(_sway.value) * 2 - 1;
    model.rotation.y = t * 18;
    model.updateTransform();
    _scene?.update();
  }

  @override
  void didUpdateWidget(ModelPetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.objPath != widget.objPath) {
      _scene = null;
      _model = null;
    }
  }

  @override
  void dispose() {
    _sway.dispose();
    super.dispose();
  }

  void _onSceneCreated(Scene scene) {
    _scene = scene;
    scene.camera.position.setValues(0, 1.2, 7);
    scene.camera.target.setValues(0, 0, 0);
    scene.light.position.setValues(3, 6, 8);
    scene.light.setColor(Colors.white, 0.55, 0.9, 0.35);
    final model = Object(
      fileName: widget.objPath,
      isAsset: false,
      lighting: true,
      scale: Vector3(4.2, 4.2, 4.2),
      position: Vector3(0, -0.4, 0),
    );
    _model = model;
    scene.world.add(model);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: 0,
            child: Container(
              width: widget.size * 0.62,
              height: widget.size * 0.10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.size * 0.05),
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
          m.Material(
            type: m.MaterialType.transparency,
            child: Cube(
              key: ValueKey(widget.objPath),
              interactive: false,
              onSceneCreated: _onSceneCreated,
            ),
          ),
        ],
      ),
    );
  }
}
