import 'dart:convert';
import 'dart:io';

class AppPaths {
  static Directory get root {
    final appData = Platform.environment['APPDATA'] ??
        '${Platform.environment['USERPROFILE']}\\AppData\\Roaming';
    final dir = Directory('$appData\\zoo_desktop_pet');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Directory get growthDir {
    final dir = Directory('${root.path}\\growth');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static File get configFile => File('${root.path}\\config.json');

  static Directory skinDir(String animalId) {
    final dir = Directory('${root.path}\\skins\\$animalId');
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

  AiConfig({
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.enabled = false,
    this.tipIntervalMinutes = 45,
  });

  factory AiConfig.fromJson(Map<String, dynamic> j) => AiConfig(
        baseUrl: j['baseUrl'] ?? '',
        apiKey: j['apiKey'] ?? '',
        model: j['model'] ?? '',
        enabled: j['enabled'] ?? false,
        tipIntervalMinutes: j['tipIntervalMinutes'] ?? 45,
      );

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'enabled': enabled,
        'tipIntervalMinutes': tipIntervalMinutes,
      };
}

class AppConfig {
  String animalId;
  AiConfig ai;
  double? windowX;
  double? windowY;
  double petScale;
  Map<String, AnimalSkin> skins;

  AppConfig({
    this.animalId = 'cat',
    AiConfig? ai,
    this.windowX,
    this.windowY,
    this.petScale = 1.0,
    Map<String, AnimalSkin>? skins,
  })  : ai = ai ?? AiConfig(),
        skins = skins ?? {};

  AnimalSkin skinOf(String animalId) =>
      skins.putIfAbsent(animalId, () => AnimalSkin());

  static AppConfig load() {
    try {
      final f = AppPaths.configFile;
      if (f.existsSync()) {
        final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final skinsJson = j['skins'] as Map<String, dynamic>? ?? {};
        return AppConfig(
          animalId: j['animalId'] ?? 'cat',
          ai: AiConfig.fromJson(j['ai'] ?? {}),
          windowX: (j['windowX'] as num?)?.toDouble(),
          windowY: (j['windowY'] as num?)?.toDouble(),
          petScale: (j['petScale'] as num?)?.toDouble() ?? 1.0,
          skins: skinsJson.map((k, v) =>
              MapEntry(k, AnimalSkin.fromJson(v as Map<String, dynamic>))),
        );
      }
    } catch (_) {}
    return AppConfig();
  }

  void save() {
    try {
      AppPaths.configFile.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
        'animalId': animalId,
        'ai': ai.toJson(),
        'windowX': windowX,
        'windowY': windowY,
        'petScale': petScale,
        'skins': {
          for (final e in skins.entries)
            if (!e.value.isEmpty) e.key: e.value.toJson()
        },
      }));
    } catch (_) {}
  }
}
