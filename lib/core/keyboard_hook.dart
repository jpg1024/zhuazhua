import 'dart:async';
import 'dart:ffi';
import 'dart:io';

/// 全局键盘活动检测服务。
/// 通过 GetAsyncKeyState 轮询检测键盘输入，提供 [activityStream] 供业务层消费。
class KeyboardHookService {
  KeyboardHookService._();
  static final KeyboardHookService instance = KeyboardHookService._();

  final _user32 = Platform.isWindows ? DynamicLibrary.open('user32.dll') : null;

  late final _getAsyncKeyState = _user32!.lookupFunction<
      Int16 Function(Int32),
      int Function(int)>('GetAsyncKeyState');

  bool _installed = false;
  DateTime _lastKeyTime = DateTime.now();
  Timer? _pollTimer;
  bool _wasTyping = false;

  /// 键盘活动流：状态变化时推送（true=正在打字, false=停止打字）。
  final _activityController = StreamController<bool>.broadcast();
  Stream<bool> get activityStream => _activityController.stream;

  /// 全局快捷键 Ctrl+Alt+P 触发流（边沿触发，按住只发一次）。
  final _hotkeyController = StreamController<void>.broadcast();
  Stream<void> get hotkeyStream => _hotkeyController.stream;

  /// 是否启用全局快捷键（设置页可关）。
  bool hotkeyEnabled = true;
  bool _hotkeyDown = false;

  /// 当前是否正在打字（距最后一次按键 < 1.5 秒）。
  bool get isTyping =>
      DateTime.now().difference(_lastKeyTime).inMilliseconds < 1500;

  /// 开始轮询键盘状态（每 100ms 检测一次）。
  void install() {
    if (!Platform.isWindows || _installed) return;
    _installed = true;

    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _pollKeys();
    });
  }

  void _pollKeys() {
    // 全局快捷键：Ctrl(0x11) + Alt(0x12) + P(0x50) 同时按下，边沿触发
    if (hotkeyEnabled) {
      final ctrl = _getAsyncKeyState(0x11) & 0x8000 != 0;
      final alt = _getAsyncKeyState(0x12) & 0x8000 != 0;
      final p = _getAsyncKeyState(0x50) & 0x8000 != 0;
      final combo = ctrl && alt && p;
      if (combo && !_hotkeyDown) _hotkeyController.add(null);
      _hotkeyDown = combo;
    }

    // 检测常用键码：字母、数字、空格、功能键、常见标点（约 53 个码）。
    // 排除修饰键、NumLock、ScrollLock、音量键等，避免误触发巡逻。
    // VK_SPACE=0x20, VK_0..VK_9=0x30..0x39, VK_A..VK_Z=0x41..0x5A,
    // VK_F1..VK_F12=0x70..0x7B, 标点 VK_OEM_*=0xBA,0xBB..0xC0,0xDB..0xDE
    for (final vk in _typableVks) {
      final state = _getAsyncKeyState(vk);
      // 高位为 1 表示按键当前处于按下状态
      if (state & 0x8000 != 0) {
        _lastKeyTime = DateTime.now();
        break;
      }
    }

    // 状态变化时通知监听者
    final typing = isTyping;
    if (typing != _wasTyping) {
      _wasTyping = typing;
      _activityController.add(typing);
    }
  }

  /// 与打字相关的虚拟键码（字母、数字、空格、F1-F12、常见标点）。
  static const List<int> _typableVks = [
    0x20, // VK_SPACE
    // VK_0..VK_9
    0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
    // VK_A..VK_Z
    0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A,
    0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x50, 0x51, 0x52, 0x53, 0x54,
    0x55, 0x56, 0x57, 0x58, 0x59, 0x5A,
    // VK_F1..VK_F12
    0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79,
    0x7A, 0x7B,
    // VK_OEM (常见标点：分号、=、逗号、减号、句号、斜杠、反引号、方括号)
    0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC0, 0xDB, 0xDC, 0xDD, 0xDE,
  ];

  /// 停止轮询。
  void uninstall() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _installed = false;
  }

  void dispose() {
    uninstall();
    _activityController.close();
    _hotkeyController.close();
  }
}
