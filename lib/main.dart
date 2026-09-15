import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'core/animals.dart';
import 'core/click_through.dart';
import 'core/config.dart';
import 'core/constants.dart';
import 'core/keyboard_hook.dart';
import 'core/window_utils.dart';
import 'growth/growth_service.dart';
import 'pet/pet_controller.dart';
import 'pet/pet_page.dart';
import 'settings/settings_page.dart';

late final AppConfig appConfig;

/// 把未捕获异常追加写入 crash.log，滚动保留最近 3 份（crash.1.log / crash.2.log）。
/// 24/7 常驻应用静默崩溃后，这是唯一的排障线索。
void _logCrash(Object error, StackTrace stack) {
  try {
    final dir = AppPaths.root;
    final log = File('${dir.path}\\crash.log');
    if (log.existsSync() && log.lengthSync() > 256 * 1024) {
      final older2 = File('${dir.path}\\crash.2.log');
      if (older2.existsSync()) older2.deleteSync();
      final older1 = File('${dir.path}\\crash.1.log');
      if (older1.existsSync()) older1.renameSync(older2.path);
      log.renameSync(older1.path);
    }
    log.writeAsStringSync(
        '[${DateTime.now().toIso8601String()}] $error\n$stack\n\n',
        mode: FileMode.append,
        flush: true);
  } catch (_) {
    // 崩溃日志自身失败时静默，避免二次异常
  }
}

Future<void> main() async {
  // 故意不 await：应用主体在 zone 内常驻运行，异常由 _logCrash 兜底
  unawaited(runZonedGuarded<Future<void>>(_run, (e, st) => _logCrash(e, st)));
}

Future<void> _run() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _logCrash(details.exception, details.stack ?? StackTrace.current);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _logCrash(error, stack);
    return true;
  };
  await windowManager.ensureInitialized();
  await acrylic.Window.initialize();

  appConfig = AppConfig.load();

  // 盲盒模式（默认关）：每次启动随机换一只；关闭时严格按设置页选择
  if (appConfig.randomAnimalOnStart) {
    final candidates =
        kAnimals.where((a) => a.id != appConfig.animalId).toList();
    appConfig.animalId = candidates[Random().nextInt(candidates.length)].id;
    appConfig.save();
  }

  const options = WindowOptions(
    size: kPetWindowSize,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    alwaysOnTop: true,
    titleBarStyle: TitleBarStyle.hidden,
    title: '爪爪',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setAsFrameless();
    await windowManager.setResizable(false);
    await acrylic.Window.setEffect(effect: acrylic.WindowEffect.transparent);
    if (appConfig.windowX != null && appConfig.windowY != null) {
      // 钳制到保存位置所在（或最近的）显示器工作区内，无交集时回退右下角
      // （防止拔副屏后宠物永久失踪）。多屏下按窗口中心找最近的显示器。
      var x = appConfig.windowX!;
      var y = appConfig.windowY!;
      final center = Offset(x + kPetWindowSize.width / 2,
          y + kPetWindowSize.height / 2);
      final area = WindowUtils.instance.workAreaForPoint(center);
      if (area != null) {
        // 窗口完全在工作区外时回退
        if (x + kPetWindowSize.width <= area.left ||
            x >= area.right ||
            y + kPetWindowSize.height <= area.top ||
            y >= area.bottom) {
          x = area.right - kPetWindowSize.width;
          y = area.bottom - kPetWindowSize.height;
        }
        x = x.clamp(area.left, area.right - kPetWindowSize.width);
        y = y.clamp(area.top, area.bottom - kPetWindowSize.height);
      }
      await windowManager.setPosition(Offset(x, y));
      // 更新配置中的位置，避免下次启动仍用旧坐标
      appConfig.windowX = x;
      appConfig.windowY = y;
      appConfig.save();
    } else {
      await windowManager.setAlignment(Alignment.bottomRight);
    }
  });

  runApp(const ZooPetApp());

  // 首帧渲染完成后再显示窗口，并做几次不可见的尺寸微调强制 DWM 重新合成；
  // 否则首次启动窗口不接收鼠标输入（托盘切换/打开设置同样通过窗口状态变化“治好”它）。
  // 开机自启动时系统登录早期 DWM 未就绪，单次微调可能不生效，故多阶段延时重试。
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await windowManager.show();
    Future<void> nudge() async {
      await windowManager.setSize(
          Size(kPetWindowSize.width + 1, kPetWindowSize.height + 1));
      await windowManager.setSize(kPetWindowSize);
    }

    await nudge();
    Future.delayed(const Duration(milliseconds: 300), nudge);
    Future.delayed(const Duration(seconds: 1), nudge);
    Future.delayed(const Duration(seconds: 3), nudge);
  });
}

class ZooPetApp extends StatelessWidget {
  const ZooPetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF5C6BC0),
        scaffoldBackgroundColor: Colors.transparent,
        fontFamily: 'Microsoft YaHei',
      ),
      home: const AppShell(),
    );
  }
}

enum AppMode { pet, settings }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with WindowListener, TrayListener {
  late final GrowthService growth;
  late final PetController pet;
  AppMode mode = AppMode.pet;
  Timer? _posSaveTimer;
  bool _visible = true;
  bool _snappedEdge = false;

  @override
  void initState() {
    super.initState();
    final animal = animalById(appConfig.animalId);
    growth = GrowthService(animal.id);
    pet = PetController(animal: animal, growth: growth, config: appConfig);
    windowManager.addListener(this);
    trayManager.addListener(this);
    _initTray(animal);

    // 全局快捷键 Ctrl+Alt+P 显示/隐藏（宠物模式下生效）
    KeyboardHookService.instance.hotkeyEnabled = appConfig.hotkeyEnabled;
    KeyboardHookService.instance.hotkeyStream.listen((_) {
      if (mode == AppMode.pet) _toggleVisible();
    });
  }

  Future<void> _initTray(AnimalInfo animal) async {
    try {
      await trayManager.setIcon('assets/tray_icon.ico');
      await trayManager.setToolTip('爪爪 - ${animal.name}');
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'toggle', label: '显示 / 隐藏'),
        MenuItem(key: 'settings', label: '设置'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: '退出'),
      ]));
    } catch (_) {}
  }

  @override
  void onTrayIconMouseDown() => _toggleVisible();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem item) {
    switch (item.key) {
      case 'toggle':
        _toggleVisible();
      case 'settings':
        _openSettings();
      case 'exit':
        _exit();
    }
  }

  Future<void> _toggleVisible() async {
    if (_visible) {
      await windowManager.hide();
    } else {
      await windowManager.show();
    }
    // 同步 TickerMode：隐藏时暂停全部动画，省 CPU
    // 同步 ClickThroughService：隐藏时跳过 100ms 光标轮询
    ClickThroughService.instance.isVisible = !_visible;
    setState(() => _visible = !_visible);
  }

  @override
  void onWindowMoved() {
    _posSaveTimer?.cancel();
    _posSaveTimer = Timer(const Duration(seconds: 1), () async {
      if (mode != AppMode.pet) return;
      // 巡逻期间窗口位置由动画控制，不存档（防止 ±100px 偏移污染 config）。
      if (pet.isPatrolling) return;
      final pos = await windowManager.getPosition();
      appConfig.windowX = pos.dx;
      appConfig.windowY = pos.dy;
      appConfig.save();
      await _applyEdgeSnap();
    });
  }

  /// 贴边吸附：距屏幕工作区边缘 40px 内自动吸附，吸附后半透明（悬停恢复）。
  Future<void> _applyEdgeSnap() async {
    if (!appConfig.edgeSnap) return;
    final pos = await windowManager.getPosition();
    final size = await windowManager.getSize();
    // 多屏：按窗口中心找所在显示器的工作区（旧实现只取主屏，副屏上永不吸附）
    final area = WindowUtils.instance.workAreaForPoint(
        Offset(pos.dx + size.width / 2, pos.dy + size.height / 2));
    if (area == null) return;
    const threshold = 40.0;
    var x = pos.dx;
    var y = pos.dy;
    var snapped = false;
    if ((pos.dx - area.left).abs() < threshold) {
      x = area.left.toDouble();
      snapped = true;
    } else if ((area.right - (pos.dx + size.width)).abs() < threshold) {
      x = (area.right - size.width).toDouble();
      snapped = true;
    }
    if ((pos.dy - area.top).abs() < threshold) {
      y = area.top.toDouble();
      snapped = true;
    } else if ((area.bottom - (pos.dy + size.height)).abs() < threshold) {
      y = (area.bottom - size.height).toDouble();
      snapped = true;
    }
    if (snapped && (x != pos.dx || y != pos.dy)) {
      await windowManager.setPosition(Offset(x, y));
    }
    if (snapped != _snappedEdge) {
      _snappedEdge = snapped;
      await windowManager.setOpacity(snapped ? 0.6 : 1.0);
    }
  }

  /// 宠物悬停：吸附状态下恢复不透明，移开后回到半透明。
  void _onPetHover(bool hovering) {
    if (!_snappedEdge) return;
    windowManager.setOpacity(hovering ? 1.0 : 0.6);
  }

  /// 开始拖动：解除吸附并恢复不透明。
  void _onPetDragStart() {
    if (!_snappedEdge) return;
    _snappedEdge = false;
    windowManager.setOpacity(1.0);
  }

  Future<void> _openSettings() async {
    if (!_visible) await _toggleVisible();
    setState(() => mode = AppMode.settings);
    await windowManager.setSize(kSettingsWindowSize);
    await windowManager.center();
  }

  Future<void> _closeSettings() async {
    setState(() => mode = AppMode.pet);
    await windowManager.setSize(kPetWindowSize);
    if (appConfig.windowX != null && appConfig.windowY != null) {
      await windowManager.setPosition(Offset(appConfig.windowX!, appConfig.windowY!));
    } else {
      await windowManager.setAlignment(Alignment.bottomRight);
    }
  }

  Future<void> _exit() async {
    growth.flush();
    pet.daily.flush();
    pet.dispose();
    await trayManager.destroy();
    exit(0);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    _posSaveTimer?.cancel();
    pet.dispose();
    growth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TickerMode(
        enabled: _visible,
        child: mode == AppMode.pet
            ? PetPage(
                controller: pet,
                onOpenSettings: _openSettings,
                onExit: _exit,
                onHoverChanged: _onPetHover,
                onDragStart: _onPetDragStart,
              )
            : Padding(
                padding: const EdgeInsets.all(8),
                child: SettingsPage(
                    config: appConfig, onClose: _closeSettings, pet: pet),
              ),
      ),
    );
  }
}
