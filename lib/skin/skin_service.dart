import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_cube/flutter_cube.dart' show loadObj;
import 'package:image/image.dart' as img;

import '../core/config.dart';

class SkinResult {
  final bool ok;
  final String message;
  const SkinResult(this.ok, this.message);
}

class SkinService {
  static const _maxImageFileBytes = 25 * 1024 * 1024;
  static const _maxImagePixels = 40 * 1000 * 1000;
  static const _maxObjFaces = 60000;

  /// 选择图片并处理为透明底 PNG，返回处理结果；成功时更新 config（不落盘，由调用方 save）。
  static Future<SkinResult> pickAndProcessImage(
      AppConfig config, String animalId) async {
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(
          label: '图片', extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp']),
    ]);
    if (file == null) return const SkinResult(false, '');

    final src = File(file.path);
    if (await src.length() > _maxImageFileBytes) {
      return const SkinResult(false, '图片文件超过 25MB，请压缩后再试');
    }
    final bytes = await src.readAsBytes();
    final info = img.findDecoderForData(bytes)?.startDecode(bytes);
    if (info == null) return const SkinResult(false, '无法解码该图片文件');
    if (info.width * info.height > _maxImagePixels) {
      return const SkinResult(false, '图片分辨率过大（超过 4000 万像素）');
    }

    final Uint8List png;
    try {
      png = await Isolate.run(() {
        final decoded = img.decodeImage(bytes);
        if (decoded == null) throw const FormatException('decode failed');
        return img.encodePng(processImage(decoded));
      });
    } catch (e) {
      debugPrint('skin image process failed: $e');
      return const SkinResult(false, '图片处理失败，请换一张图片重试');
    }

    final skin = config.skinOf(animalId);
    try {
      final dir = AppPaths.skinDir(animalId);
      _clearDir(dir);
      final out = File(
          '${dir.path}\\skin_${DateTime.now().millisecondsSinceEpoch}.png');
      await out.writeAsBytes(png);
      skin.imagePath = out.path;
      skin.modelPath = null;
      return const SkinResult(true, '图片皮肤已应用');
    } catch (e) {
      debugPrint('skin image save failed: $e');
      skin.imagePath = null;
      skin.modelPath = null;
      return const SkinResult(false, '皮肤保存失败，已恢复默认形象');
    }
  }

  /// 去背景 + 缩放到 ≤512px。
  static img.Image processImage(img.Image decoded) {
    decoded = decoded.convert(numChannels: 4);
    if (decoded.width > 512 || decoded.height > 512) {
      final ratio = 512 /
          (decoded.width > decoded.height ? decoded.width : decoded.height);
      decoded = img.copyResize(decoded,
          width: (decoded.width * ratio).round(),
          height: (decoded.height * ratio).round(),
          interpolation: img.Interpolation.cubic);
    }
    if (!_hasTransparency(decoded)) {
      _removeSolidBackground(decoded);
    }
    return decoded;
  }

  /// 选择 OBJ 模型，连同 MTL/贴图复制到皮肤目录并预解析校验。
  static Future<SkinResult> pickModel(
      AppConfig config, String animalId) async {
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(label: '3D 模型', extensions: ['obj']),
    ]);
    if (file == null) return const SkinResult(false, '');

    final objFile = File(file.path);
    final String content;
    try {
      content = await objFile.readAsString();
    } catch (_) {
      return const SkinResult(false, '无法读取该 OBJ 文件（需为文本格式）');
    }
    final faceCount =
        RegExp(r'^f\s', multiLine: true).allMatches(content).length;
    if (faceCount == 0) return const SkinResult(false, '该 OBJ 文件不含任何面数据');
    if (faceCount > _maxObjFaces) {
      return SkinResult(false, '模型过大（$faceCount 面 > $_maxObjFaces），会导致卡顿');
    }

    final srcDir = objFile.parent.path;
    final dir = AppPaths.skinDir(animalId);
    final skin = config.skinOf(animalId);
    _clearDir(dir);
    try {
      final objName = objFile.uri.pathSegments.last;
      final destObj = File('${dir.path}\\$objName');
      await objFile.copy(destObj.path);

      // 复制 mtllib 引用的材质及其贴图
      for (final m in RegExp(r'^mtllib\s+(.+)$', multiLine: true)
          .allMatches(content)) {
        final mtlName = safeRelativePath(m.group(1)!.trim());
        if (mtlName == null) continue;
        final mtlFile = File('$srcDir\\$mtlName');
        if (!mtlFile.existsSync()) continue;
        final destMtl = File('${dir.path}\\$mtlName');
        destMtl.parent.createSync(recursive: true);
        await mtlFile.copy(destMtl.path);
        final mtlContent = await mtlFile.readAsString();
        for (final t in RegExp(r'^\s*map_\w+\s+(.+)$', multiLine: true)
            .allMatches(mtlContent)) {
          final texName = safeRelativePath(
              t.group(1)!.trim().split(RegExp(r'\s+')).last);
          if (texName == null) continue;
          final texFile = File('$srcDir\\$texName');
          if (texFile.existsSync()) {
            final destTex = File('${dir.path}\\$texName');
            destTex.parent.createSync(recursive: true);
            await texFile.copy(destTex.path);
          }
        }
      }

      // 导入时预解析，避免渲染阶段静默失败
      await loadObj(destObj.path, true, isAsset: false);

      skin.modelPath = destObj.path;
      skin.imagePath = null;
      return SkinResult(true, '3D 模型已应用（$faceCount 面）');
    } catch (e) {
      debugPrint('skin model import failed: $e');
      skin.imagePath = null;
      skin.modelPath = null;
      return const SkinResult(false, '模型导入失败：文件解析或复制出错，已恢复默认形象');
    }
  }

  static void clearSkin(AppConfig config, String animalId) {
    final skin = config.skinOf(animalId);
    skin.imagePath = null;
    skin.modelPath = null;
    try {
      final dir = Directory('${AppPaths.root.path}\\skins\\$animalId');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  }

  /// 只允许皮肤目录内的相对路径：拒绝绝对路径、盘符和 `..` 穿越。
  @visibleForTesting
  static String? safeRelativePath(String name) {
    final n = name.replaceAll('/', '\\');
    if (n.isEmpty || n.contains(':') || n.startsWith('\\')) return null;
    final segs = n.split('\\');
    if (segs.any((s) => s.isEmpty || s == '.' || s == '..')) return null;
    return n;
  }

  static bool _hasTransparency(img.Image image) {
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (image.getPixel(x, y).a < 250) return true;
      }
    }
    return false;
  }

  /// 从四角 flood-fill 去除近似纯色背景。
  static void _removeSolidBackground(img.Image image) {
    const tolerance = 32.0;
    final w = image.width, h = image.height;
    final visited = List<bool>.filled(w * h, false);
    final stack = <int>[];

    void seed(int x, int y) => stack.add(y * w + x);
    seed(0, 0);
    seed(w - 1, 0);
    seed(0, h - 1);
    seed(w - 1, h - 1);

    final corners = [
      image.getPixel(0, 0),
      image.getPixel(w - 1, 0),
      image.getPixel(0, h - 1),
      image.getPixel(w - 1, h - 1),
    ];

    bool isBg(img.Pixel p) {
      for (final c in corners) {
        final dr = p.r - c.r, dg = p.g - c.g, db = p.b - c.b;
        if (dr * dr + dg * dg + db * db < tolerance * tolerance) return true;
      }
      return false;
    }

    while (stack.isNotEmpty) {
      final idx = stack.removeLast();
      if (visited[idx]) continue;
      visited[idx] = true;
      final x = idx % w, y = idx ~/ w;
      final p = image.getPixel(x, y);
      if (!isBg(p)) continue;
      image.setPixelRgba(x, y, 0, 0, 0, 0);
      if (x > 0) stack.add(idx - 1);
      if (x < w - 1) stack.add(idx + 1);
      if (y > 0) stack.add(idx - w);
      if (y < h - 1) stack.add(idx + w);
    }

    // 边缘 1px 羽化：与透明像素相邻的不透明像素 alpha 减半
    final toFeather = <int>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (image.getPixel(x, y).a == 0) continue;
        final neighbors = [
          if (x > 0) image.getPixel(x - 1, y),
          if (x < w - 1) image.getPixel(x + 1, y),
          if (y > 0) image.getPixel(x, y - 1),
          if (y < h - 1) image.getPixel(x, y + 1),
        ];
        if (neighbors.any((n) => n.a == 0)) toFeather.add(y * w + x);
      }
    }
    for (final idx in toFeather) {
      final x = idx % w, y = idx ~/ w;
      final p = image.getPixel(x, y);
      image.setPixelRgba(x, y, p.r, p.g, p.b, (p.a ~/ 2));
    }
  }

  static void _clearDir(Directory dir) {
    try {
      for (final f in dir.listSync()) {
        f.deleteSync(recursive: true);
      }
    } catch (_) {}
  }
}
