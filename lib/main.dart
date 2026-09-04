import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'core/animals.dart';
import 'core/config.dart';
import 'core/keyboard_hook.dart';
import 'core/window_utils.dart';
import 'growth/growth_service.dart';
import 'pet/pet_controller.dart';
import 'pet/pet_page.dart';
import 'settings/settings_page.dart';

const Size kPetWindowSize = Size(280, 380);
const Size kSettingsWindowSize = Size(720, 840);

late final AppConfig appConfig;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      await windowManager.setPosition(Offset(appConfig.windowX!, appConfig.windowY!));
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
    setState(() => _visible = !_visible);
  }

  @override
  void onWindowMoved() {
    _posSaveTimer?.cancel();
    _posSaveTimer = Timer(const Duration(seconds: 1), () async {
      if (mode != AppMode.pet) return;
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
    final area = WindowUtils.instance.workArea();
    if (area == null) return;
    final pos = await windowManager.getPosition();
    final size = await windowManager.getSize();
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

  void _exit() {
    growth.save();
    trayManager.destroy();
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
