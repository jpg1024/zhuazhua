import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui';

import 'package:ffi/ffi.dart';

final class _Point extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
}

final class _Rect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

/// 轮询光标位置，按需给窗口加/去 WS_EX_TRANSPARENT：
/// 光标在宠物矩形内窗口接收鼠标，否则整窗点击穿透到桌面。
class ClickThroughService {
  ClickThroughService._();

  static final ClickThroughService instance = ClickThroughService._();

  static const _gwlExStyle = -20;
  static const _wsExTransparent = 0x20;
  static const _wsExLayered = 0x80000;
  static const _lwaAlpha = 0x2;

  final _user32 = Platform.isWindows ? DynamicLibrary.open('user32.dll') : null;
  final _kernel32 =
      Platform.isWindows ? DynamicLibrary.open('kernel32.dll') : null;

  late final _findWindowEx = _user32!.lookupFunction<
      IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
      int Function(
          int, int, Pointer<Utf16>, Pointer<Utf16>)>('FindWindowExW');
  late final _getWindowThreadProcessId = _user32!.lookupFunction<
      Uint32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');
  late final _getCurrentProcessId =
      _kernel32!.lookupFunction<Uint32 Function(), int Function()>(
          'GetCurrentProcessId');
  late final _getCursorPos = _user32!.lookupFunction<
      Int32 Function(Pointer<_Point>),
      int Function(Pointer<_Point>)>('GetCursorPos');
  late final _getWindowRect = _user32!.lookupFunction<
      Int32 Function(IntPtr, Pointer<_Rect>),
      int Function(int, Pointer<_Rect>)>('GetWindowRect');
  late final _getWindowLongPtr = _user32!.lookupFunction<
      IntPtr Function(IntPtr, Int32),
      int Function(int, int)>('GetWindowLongPtrW');
  late final _setWindowLongPtr = _user32!.lookupFunction<
      IntPtr Function(IntPtr, Int32, IntPtr),
      int Function(int, int, int)>('SetWindowLongPtrW');
  late final _setLayeredWindowAttributes = _user32!.lookupFunction<
      Int32 Function(IntPtr, Uint32, Uint8, Uint32),
      int Function(int, int, int, int)>('SetLayeredWindowAttributes');

  int _hwnd = 0;
  Timer? _timer;

  /// 宠物可交互矩形（窗口内逻辑坐标）。
  Rect Function()? hitRectProvider;

  /// 逻辑像素 → 物理像素比例。
  double devicePixelRatio = 1.0;

  /// 为 true 时整窗可交互（如右键菜单打开时）。
  bool forceInteractive = false;

  int get _windowHandle {
    if (_hwnd == 0) {
      _hwnd = _findOwnWindowByTitle('爪爪');
      if (_hwnd != 0) {
        // 保证 WS_EX_LAYERED 存在，否则 WS_EX_TRANSPARENT 不生效
        final style = _getWindowLongPtr(_hwnd, _gwlExStyle);
        if (style & _wsExLayered == 0) {
          _setWindowLongPtr(_hwnd, _gwlExStyle, style | _wsExLayered);
          _setLayeredWindowAttributes(_hwnd, 0, 255, _lwaAlpha);
        }
      }
    }
    return _hwnd;
  }

  /// 遍历同标题顶层窗口，只认本进程的那个。
  /// 标题可能被其他进程占用：绝不对外进程窗口设置扩展样式。
  int _findOwnWindowByTitle(String title) {
    final nativeTitle = title.toNativeUtf16();
    try {
      final selfPid = _getCurrentProcessId();
      final pidBuf = calloc<Uint32>();
      try {
        var prev = 0;
        // 防御性上限，避免异常情况下无限遍历
        for (var i = 0; i < 32; i++) {
          final hwnd = _findWindowEx(0, prev, nullptr, nativeTitle);
          if (hwnd == 0) break;
          _getWindowThreadProcessId(hwnd, pidBuf);
          if (pidBuf.value == selfPid) return hwnd;
          prev = hwnd;
        }
        return 0;
      } finally {
        calloc.free(pidBuf);
      }
    } finally {
      calloc.free(nativeTitle);
    }
  }

  void start() {
    if (!Platform.isWindows || _timer != null) return;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _setTransparent(false);
  }

  void _tick() {
    if (_windowHandle == 0) return;
    if (forceInteractive || hitRectProvider == null) {
      _setTransparent(false);
      return;
    }
    final pt = calloc<_Point>();
    final rc = calloc<_Rect>();
    try {
      if (_getCursorPos(pt) == 0 || _getWindowRect(_windowHandle, rc) == 0) {
        _setTransparent(false);
        return;
      }
      final localX = (pt.ref.x - rc.ref.left) / devicePixelRatio;
      final localY = (pt.ref.y - rc.ref.top) / devicePixelRatio;
      final inside = hitRectProvider!().contains(Offset(localX, localY));
      _setTransparent(!inside);
    } finally {
      calloc.free(pt);
      calloc.free(rc);
    }
  }

  void _setTransparent(bool value) {
    if (!Platform.isWindows || _windowHandle == 0) return;
    // 自愈：每次强制对比窗口实际扩展样式，不依赖缓存短路。
    // 窗口被 DWM 重建/外部操作清除样式后，缓存与真实状态脱节会导致
    // 整窗永久点击穿透（无法拖动/右键无反应），此处 100ms 轮询内自动纠正。
    final style = _getWindowLongPtr(_hwnd, _gwlExStyle);
    final has = (style & _wsExTransparent) != 0;
    if (has != value) {
      _setWindowLongPtr(_hwnd, _gwlExStyle,
          value ? style | _wsExTransparent : style & ~_wsExTransparent);
    }
  }
}
