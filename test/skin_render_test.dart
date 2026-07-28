import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoo_desktop_pet/skin/model_pet_view.dart';
import 'package:zoo_desktop_pet/skin/pseudo3d_image.dart';

void main() {
  testWidgets('ModelPetView 加载 OBJ+MTL 不崩溃', (tester) async {
    final objPath =
        File('_test_assets/pyramid.obj').absolute.path;
    await tester.pumpWidget(MaterialApp(
      home: Center(child: ModelPetView(objPath: objPath, size: 96)),
    ));
    // 等模型异步加载 + 摆动动画数帧
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.byType(ModelPetView), findsOneWidget);
  });

  testWidgets('Pseudo3DImage 渲染文件图片不崩溃', (tester) async {
    final imgPath =
        File('_test_assets/test_white_bg.png').absolute.path;
    await tester.pumpWidget(MaterialApp(
      home: Center(child: Pseudo3DImage(path: imgPath, size: 96)),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
