import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'core/animals.dart';
import 'core/config.dart';
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

  // 首帧渲染完成后再显示窗口，并做一次不可见的尺寸微调强制 DWM 重新合成；
  // 否则首次启动窗口不接收鼠标输入（托盘切换/打开设置同样通过窗口状态变化“治好”它）
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await windowManager.show();
    await windowManager.setSize(
        Size(kPetWindowSize.width + 1, kPetWindowSize.height + 1));
    await windowManager.setSize(kPetWindowSize);
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

  @override
  void initState() {
    super.initState();
    final animal = animalById(appConfig.animalId);
    growth = GrowthService(animal.id);
    pet = PetController(animal: animal, growth: growth, config: appConfig);
    windowManager.addListener(this);
    trayManager.addListener(this);
    _initTray(animal);
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
    });
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
              )
            : Padding(
                padding: const EdgeInsets.all(8),
                child: SettingsPage(config: appConfig, onClose: _closeSettings),
              ),
      ),
    );
  }
}
