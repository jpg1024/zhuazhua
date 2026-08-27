import 'dart:ffi';
import 'dart:io';
import 'dart:ui';

import 'package:ffi/ffi.dart';

final class _WinRect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

/// Windows 原生小工具：主屏工作区（不含任务栏）与开机自启动注册表。
class WindowUtils {
  WindowUtils._();

  static final WindowUtils instance = WindowUtils._();

  static const _spiGetWorkArea = 0x0030;
  static const _hkeyCurrentUser = 0x80000001;
  static const _keyQueryValue = 0x0001;
  static const _keySetValue = 0x0002;
  static const _regSz = 1;
  static const _errorSuccess = 0;
  static const _autoStartKey =
      'Software\\Microsoft\\Windows\\CurrentVersion\\Run';
  static const _autoStartValueName = 'zhuazhua';

  final _user32 = Platform.isWindows ? DynamicLibrary.open('user32.dll') : null;
  final _advapi32 =
      Platform.isWindows ? DynamicLibrary.open('advapi32.dll') : null;

  late final _systemParametersInfo = _user32!.lookupFunction<
      Int32 Function(Uint32, Uint32, Pointer<_WinRect>, Uint32),
      int Function(int, int, Pointer<_WinRect>, int)>('SystemParametersInfoW');

  late final _regOpenKeyEx = _advapi32!.lookupFunction<
      Int32 Function(IntPtr, Pointer<Utf16>, Uint32, Uint32, Pointer<IntPtr>),
      int Function(int, Pointer<Utf16>, int, int, Pointer<IntPtr>)>(
          'RegOpenKeyExW');
  late final _regSetValueEx = _advapi32!.lookupFunction<
      Int32 Function(
          IntPtr, Pointer<Utf16>, Uint32, Uint32, Pointer<Utf16>, Uint32),
      int Function(
          int, Pointer<Utf16>, int, int, Pointer<Utf16>, int)>(
      'RegSetValueExW');
  late final _regQueryValueEx = _advapi32!.lookupFunction<
      Int32 Function(
          IntPtr, Pointer<Utf16>, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint16>, Pointer<Uint32>),
      int Function(int, Pointer<Utf16>, Pointer<Uint32>, Pointer<Uint32>,
          Pointer<Uint16>, Pointer<Uint32>)>('RegQueryValueExW');
  late final _regDeleteValue = _advapi32!.lookupFunction<
      Int32 Function(IntPtr, Pointer<Utf16>),
      int Function(int, Pointer<Utf16>)>('RegDeleteValueW');
  late final _regCloseKey = _advapi32!.lookupFunction<
      Int32 Function(IntPtr), int Function(int)>('RegCloseKey');

  /// 主屏工作区（不含任务栏），失败返回 null。
  Rect? workArea() {
    if (!Platform.isWindows) return null;
    final rc = calloc<_WinRect>();
    try {
      final ok =
          _systemParametersInfo(_spiGetWorkArea, 0, rc, 0);
      if (ok == 0) return null;
      return Rect.fromLTRB(rc.ref.left.toDouble(), rc.ref.top.toDouble(),
          rc.ref.right.toDouble(), rc.ref.bottom.toDouble());
    } finally {
      calloc.free(rc);
    }
  }

  bool autoStartEnabled() {
    if (!Platform.isWindows) return false;
    final key = _openKey(_keyQueryValue);
    if (key == 0) return false;
    try {
      final name = _autoStartValueName.toNativeUtf16();
      final err = _regQueryValueEx(
          key, name, nullptr, nullptr, nullptr, nullptr);
      calloc.free(name);
      return err == _errorSuccess;
    } finally {
      _regCloseKey(key);
    }
  }

  /// 写入/删除 HKCU\...\Run 下的自启动项。成功返回 true。
  bool setAutoStart(bool enabled) {
    if (!Platform.isWindows) return false;
    final key = _openKey(_keySetValue | _keyQueryValue);
    if (key == 0) return false;
    try {
      final name = _autoStartValueName.toNativeUtf16();
      if (enabled) {
        final exe = '"${Platform.resolvedExecutable}"';
        final data = exe.toNativeUtf16();
        // cbData 含结尾 null：UTF-16 码元数 * 2
        final err = _regSetValueEx(
            key, name, 0, _regSz, data, (exe.length + 1) * 2);
        calloc.free(data);
        calloc.free(name);
        return err == _errorSuccess;
      }
      final err = _regDeleteValue(key, name);
      calloc.free(name);
      return err == _errorSuccess || err == 2; // 2 = 值不存在
    } finally {
      _regCloseKey(key);
    }
  }

  int _openKey(int access) {
    final sub = _autoStartKey.toNativeUtf16();
    final hkey = calloc<IntPtr>();
    try {
      final err =
          _regOpenKeyEx(_hkeyCurrentUser, sub, 0, access, hkey);
      return err == _errorSuccess ? hkey.value : 0;
    } finally {
      calloc.free(sub);
      calloc.free(hkey);
    }
  }
}
