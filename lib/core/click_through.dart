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

  late final _findWindow = _user32!.lookupFunction<
      IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
      int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');
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
  bool? _transparent;

  /// 宠物可交互矩形（窗口内逻辑坐标）。
  Rect Function()? hitRectProvider;

  /// 逻辑像素 → 物理像素比例。
  double devicePixelRatio = 1.0;

  /// 为 true 时整窗可交互（如右键菜单打开时）。
  bool forceInteractive = false;

  int get _windowHandle {
    if (_hwnd == 0) {
      final title = '爪爪'.toNativeUtf16();
      _hwnd = _findWindow(nullptr, title);
      calloc.free(title);
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
    if (!Platform.isWindows || _windowHandle == 0 || _transparent == value) {
      return;
    }
    final style = _getWindowLongPtr(_hwnd, _gwlExStyle);
    final next =
        value ? style | _wsExTransparent : style & ~_wsExTransparent;
    if (next != style) _setWindowLongPtr(_hwnd, _gwlExStyle, next);
    _transparent = value;
  }
}
