import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

import 'atomic_json.dart';
import 'dpapi.dart';

class AppPaths {
  // 懒初始化目录缓存（只求值一次），避免每次 save/load 都走 existsSync。
  static final Directory root = _initDir(() {
    final appData = Platform.environment['APPDATA'] ??
        '${Platform.environment['USERPROFILE']}\\AppData\\Roaming';
    return Directory('$appData\\zoo_desktop_pet');
  });
  static final Directory growthDir =
      _initDir(() => Directory('${root.path}\\growth'));
  static final Directory configFileDir = root;
  static File get configFile => File('${root.path}\\config.json');
  static File get achievementsFile => File('${root.path}\\achievements.json');
  static File get dailyTasksFile => File('${root.path}\\daily_tasks.json');

  static Directory _skinDirCache = Directory('');
  static Directory skinDir(String animalId) {
    final path = '${root.path}\\skins\\$animalId';
    if (_skinDirCache.path != path) {
      final dir = Directory(path);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _skinDirCache = dir;
    }
    return _skinDirCache;
  }

  static Directory _initDir(Directory Function() create) {
    final dir = create();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }
}

class AnimalSkin {
  String? imagePath;
  String? modelPath;

  AnimalSkin({this.imagePath, this.modelPath});

  bool get isEmpty => imagePath == null && modelPath == null;

  factory AnimalSkin.fromJson(Map<String, dynamic> j) => AnimalSkin(
        imagePath: j['imagePath'],
        modelPath: j['modelPath'],
      );

  Map<String, dynamic> toJson() => {
        'imagePath': imagePath,
        'modelPath': modelPath,
      };
}

class AiConfig {
  String baseUrl;
  String apiKey;
  String model;
  bool enabled;
  int tipIntervalMinutes;

  /// 落盘密文前缀：无前缀视为旧版明文，读取兼容、下次保存自动迁移为密文。
  static const String _cipherPrefix = 'dpapi:';

  /// 密文缓存：apiKey 未变时复用上次加密结果，避免每次 save 都调用 CryptProtectData。
  String? _cachedCipher;
  String? _cachedPlainKey;

  AiConfig({
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.enabled = false,
    this.tipIntervalMinutes = 45,
  });

  factory AiConfig.fromJson(Map<String, dynamic> j) => AiConfig(
        baseUrl: j['baseUrl'] ?? '',
        apiKey: _decryptKey(j['apiKey'] ?? ''),
        model: j['model'] ?? '',
        enabled: j['enabled'] ?? false,
        tipIntervalMinutes: j['tipIntervalMinutes'] ?? 45,
      );

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'apiKey': _encryptKey(apiKey),
        'model': model,
        'enabled': enabled,
        'tipIntervalMinutes': tipIntervalMinutes,
      };

  String _encryptKey(String key) {
    if (key.isEmpty) {
      _cachedCipher = null;
      _cachedPlainKey = null;
      return '';
    }
    if (key == _cachedPlainKey && _cachedCipher != null) return _cachedCipher!;
    final cipher = Dpapi.protect(key);
    final result = cipher == null ? key : '$_cipherPrefix$cipher';
    _cachedCipher = result;
    _cachedPlainKey = key;
    return result;
  }

  static String _decryptKey(String stored) {
    if (stored.isEmpty) return '';
    if (!stored.startsWith(_cipherPrefix)) return stored;
    return Dpapi.unprotect(stored.substring(_cipherPrefix.length)) ?? '';
  }
}

class AppConfig {
  String animalId;
  AiConfig ai;
  double? windowX;
  double? windowY;
  double petScale;
  Map<String, AnimalSkin> skins;

  /// 键盘输入时宠物巡逻方向：'left'=从左侧消失右侧进入, 'right'=反向, 'random'=随机
  String patrolDirection;

  /// 无操作达到该时长（分钟）后宠物自动进入休眠，默认 60 分钟
  double sleepTimeoutMinutes;

  /// 拖动后自动吸附屏幕边缘（吸附后宠物半透明，悬停恢复）
  bool edgeSnap;

  /// 全局快捷键 Ctrl+Alt+P 显示/隐藏宠物
  bool hotkeyEnabled;

  /// 开机自启动（写入 HKCU Run 注册表）
  bool autoStart;

  /// 启动时随机换一只动物（盲盒效果）。默认关闭：以设置页选择的动物为准。
  bool randomAnimalOnStart;

  AppConfig({
    this.animalId = 'cat',
    AiConfig? ai,
    this.windowX,
    this.windowY,
    this.petScale = 1.0,
    Map<String, AnimalSkin>? skins,
    this.patrolDirection = 'left',
    this.sleepTimeoutMinutes = 60,
    this.edgeSnap = true,
    this.hotkeyEnabled = true,
    this.autoStart = false,
    this.randomAnimalOnStart = false,
  })  : ai = ai ?? AiConfig(),
        skins = skins ?? {};

  AnimalSkin skinOf(String animalId) =>
      skins.putIfAbsent(animalId, () => AnimalSkin());

  static AppConfig load() {
    final j = AtomicJson.read(AppPaths.configFile);
    if (j != null) {
      final skinsJson = j['skins'] as Map<String, dynamic>? ?? {};
      return AppConfig(
        animalId: j['animalId'] ?? 'cat',
        ai: AiConfig.fromJson(j['ai'] ?? {}),
        windowX: (j['windowX'] as num?)?.toDouble(),
        windowY: (j['windowY'] as num?)?.toDouble(),
        petScale: (j['petScale'] as num?)?.toDouble() ?? 1.0,
        patrolDirection: j['patrolDirection'] ?? 'left',
        sleepTimeoutMinutes:
            (j['sleepTimeoutMinutes'] as num?)?.toDouble() ?? 60,
        edgeSnap: j['edgeSnap'] ?? true,
        hotkeyEnabled: j['hotkeyEnabled'] ?? true,
        autoStart: j['autoStart'] ?? false,
        randomAnimalOnStart: j['randomAnimalOnStart'] ?? false,
        skins: skinsJson.map((k, v) =>
            MapEntry(k, AnimalSkin.fromJson(v as Map<String, dynamic>))),
      );
    }
    return AppConfig();
  }

  void save() {
    final ok = AtomicJson.write(AppPaths.configFile, {
      'animalId': animalId,
      'ai': ai.toJson(),
      'windowX': windowX,
      'windowY': windowY,
      'petScale': petScale,
      'patrolDirection': patrolDirection,
      'sleepTimeoutMinutes': sleepTimeoutMinutes,
      'edgeSnap': edgeSnap,
      'hotkeyEnabled': hotkeyEnabled,
      'autoStart': autoStart,
      'randomAnimalOnStart': randomAnimalOnStart,
      'skins': {
        for (final e in skins.entries)
          if (!e.value.isEmpty) e.key: e.value.toJson()
      },
    });
    if (!ok) debugPrint('AppConfig.save() failed');
  }
}
