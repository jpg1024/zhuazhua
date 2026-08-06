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

  /// 当前是否正在打字（距最后一次按键 < 1.5 秒）。
  bool get isTyping =>
      DateTime.now().difference(_lastKeyTime).inMilliseconds < 1500;

  /// 开始轮询键盘状态（每 50ms 检测一次）。
  void install() {
    if (!Platform.isWindows || _installed) return;
    _installed = true;

    _pollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _pollKeys();
    });
  }

  void _pollKeys() {
    // 检测常用键码范围：字母、数字、功能键、空格、标点等
    // VK_SPACE=0x20, VK_0..VK_9=0x30..0x39, VK_A..VK_Z=0x41..0x5A,
    // VK_F1..VK_F24=0x70..0x87, 标点 VK_OEM_*=0xBA..0xC0, 0xDB..0xDE
    for (var vk = 0x20; vk <= 0xFE; vk++) {
      // 跳过鼠标按钮键码
      if (vk >= 0x01 && vk <= 0x06) continue;
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

  /// 停止轮询。
  void uninstall() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _installed = false;
  }

  void dispose() {
    uninstall();
    _activityController.close();
  }
}
