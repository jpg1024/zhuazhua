import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zoo_desktop_pet/skin/skin_service.dart';

void main() {
  test('白底图片去背景：四角透明、主体保留', () {
    final bytes =
        File('_test_assets/test_white_bg.png').readAsBytesSync();
    final decoded = img.decodeImage(bytes)!;
    final out = SkinService.processImage(decoded);

    expect(out.numChannels, 4);
    expect(out.getPixel(0, 0).a, 0, reason: '左上角应透明');
    expect(out.getPixel(out.width - 1, out.height - 1).a, 0,
        reason: '右下角应透明');
    final center = out.getPixel(out.width ~/ 2, out.height ~/ 2 + 10);
    expect(center.a, greaterThan(200), reason: '主体应保留不透明');
    expect(center.r, greaterThan(center.b), reason: '主体应为橙色');
  });

  test('透明 PNG 不做去背景，超大图缩放到 512', () {
    final big = img.Image(width: 1024, height: 700, numChannels: 4);
    img.fill(big, color: img.ColorRgba8(10, 200, 30, 255));
    // 打一个透明角标，模拟已含透明通道的图
    big.setPixelRgba(0, 0, 0, 0, 0, 0);
    final out = SkinService.processImage(big);
    expect(out.width, 512);
    expect(out.getPixel(256, 256).a, 255, reason: '不应误删主体');
  });

  test('OBJ 面数与 mtllib 解析正则', () {
    final content = File('_test_assets/pyramid.obj').readAsStringSync();
    final faces =
        RegExp(r'^f\s', multiLine: true).allMatches(content).length;
    expect(faces, 6);
    final mtl = RegExp(r'^mtllib\s+(.+)$', multiLine: true)
        .firstMatch(content)!
        .group(1)!
        .trim();
    expect(mtl, 'pyramid.mtl');
    expect(File('_test_assets/$mtl').existsSync(), true);
  });

  test('safeRelativePath 拦截路径穿越', () {
    expect(SkinService.safeRelativePath('tex.png'), 'tex.png');
    expect(SkinService.safeRelativePath('textures/tex.png'), 'textures\\tex.png');
    expect(SkinService.safeRelativePath(r'..\..\evil.exe'), isNull);
    expect(SkinService.safeRelativePath('../evil.exe'), isNull);
    expect(SkinService.safeRelativePath(r'C:\Windows\evil.dll'), isNull);
    expect(SkinService.safeRelativePath(r'\\server\share\x'), isNull);
    expect(SkinService.safeRelativePath(r'a\.\b.png'), isNull);
    expect(SkinService.safeRelativePath(''), isNull);
  });
}
