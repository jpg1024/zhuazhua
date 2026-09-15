import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zoo_desktop_pet/core/config.dart';

import 'test_paths.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = setupPaths());
  tearDown(() => teardownPaths(tmp));

  test('AppConfig → JSON → AppConfig 往返一致', () {
    final cfg = AppConfig.load(); // 空目录 → 全默认
    cfg.animalId = 'panda';
    cfg.petScale = 1.5;
    cfg.patrolDirection = 'random';
    cfg.sleepTimeoutMinutes = 90;
    cfg.windowX = 100;
    cfg.windowY = 200;
    cfg.ai
      ..enabled = true
      ..baseUrl = 'https://api.example.com/v1'
      ..model = 'qwen3.8-flash'
      ..tipIntervalMinutes = 30;
    cfg.save();

    final reloaded = AppConfig.load();
    expect(reloaded.animalId, 'panda');
    expect(reloaded.petScale, 1.5);
    expect(reloaded.patrolDirection, 'random');
    expect(reloaded.sleepTimeoutMinutes, 90);
    expect(reloaded.windowX, 100);
    expect(reloaded.windowY, 200);
    expect(reloaded.ai.enabled, isTrue);
    expect(reloaded.ai.baseUrl, 'https://api.example.com/v1');
    expect(reloaded.ai.model, 'qwen3.8-flash');
    expect(reloaded.ai.tipIntervalMinutes, 30);
  });

  test('旧配置缺少新字段时回落默认值', () {
    File(AppPaths.configFile.path).writeAsStringSync(jsonEncode({
      'animalId': 'dog',
      // 无 sleepTimeoutMinutes / edgeSnap 等新字段
    }));
    final cfg = AppConfig.load();
    expect(cfg.animalId, 'dog');
    expect(cfg.sleepTimeoutMinutes, 60);
  });

  test('明文 apiKey 旧档：读取正常，保存后迁移为 dpapi: 密文', () {
    if (!Platform.isWindows) return; // DPAPI 仅 Windows
    File(AppPaths.configFile.path).writeAsStringSync(jsonEncode({
      'ai': {'apiKey': 'sk-plain-secret', 'enabled': true},
    }));
    final cfg = AppConfig.load();
    expect(cfg.ai.apiKey, 'sk-plain-secret'); // 明文兼容读取

    cfg.save();
    final raw = File(AppPaths.configFile.path).readAsStringSync();
    expect(raw, contains('dpapi:')); // 已迁移为密文
    expect(raw, isNot(contains('sk-plain-secret')));

    final reloaded = AppConfig.load();
    expect(reloaded.ai.apiKey, 'sk-plain-secret'); // 密文可解密还原
  });

  test('损坏 JSON：回落默认值，坏文件备份名不以 .json 结尾', () {
    File(AppPaths.configFile.path).writeAsStringSync('{broken json!!!');
    final cfg = AppConfig.load();
    expect(cfg.animalId, 'cat'); // 默认

    // corrupt 备份不能以 .json 结尾，否则会被按后缀扫描的逻辑（如
    // GrowthSnapshot.loadAll）反复读取并重复改名（文件名无限增长的回归）
    final leftovers = tmp
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toList();
    final corrupt = leftovers.where((n) => n.contains('corrupt'));
    expect(corrupt, isNotEmpty);
    for (final name in corrupt) {
      expect(name.endsWith('.json'), isFalse, reason: '$name 不应以 .json 结尾');
    }
  });
}
