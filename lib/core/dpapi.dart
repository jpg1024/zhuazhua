import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef _BlobFn = int Function(
    Pointer<_DataBlob>,
    Pointer<Utf16>,
    Pointer<_DataBlob>,
    Pointer<Void>,
    Pointer<Void>,
    int,
    Pointer<_DataBlob>);

/// Windows DPAPI（CryptProtectData / CryptUnprotectData）封装。
/// 用当前登录用户的凭据加密，密文仅本机本用户可解，适合保护落盘的 API Key。
/// 非 Windows 平台 [supported] 为 false，调用方应回退到明文存储。
class Dpapi {
  Dpapi._();

  static final bool supported = Platform.isWindows;

  /// 禁止 DPAPI 弹任何 UI（后台进程必须设置）。
  static const int _uiForbidden = 0x1;

  static final DynamicLibrary? _crypt32 =
      Platform.isWindows ? DynamicLibrary.open('crypt32.dll') : null;
  static final DynamicLibrary? _kernel32 =
      Platform.isWindows ? DynamicLibrary.open('kernel32.dll') : null;

  static final _BlobFn _protect = _crypt32!.lookupFunction<
      Int32 Function(Pointer<_DataBlob>, Pointer<Utf16>, Pointer<_DataBlob>,
          Pointer<Void>, Pointer<Void>, Uint32, Pointer<_DataBlob>),
      _BlobFn>('CryptProtectData');

  static final _BlobFn _unprotect = _crypt32!.lookupFunction<
      Int32 Function(Pointer<_DataBlob>, Pointer<Utf16>, Pointer<_DataBlob>,
          Pointer<Void>, Pointer<Void>, Uint32, Pointer<_DataBlob>),
      _BlobFn>('CryptUnprotectData');

  static final _localFree = _kernel32!.lookupFunction<
      IntPtr Function(Pointer<Void>),
      int Function(Pointer<Void>)>('LocalFree');

  /// 加密为 base64 字符串；失败返回 null。
  static String? protect(String plain) {
    if (!supported || plain.isEmpty) return null;
    final out = _call(_protect, utf8.encode(plain));
    return out == null ? null : base64.encode(out);
  }

  /// 解密 base64 密文；失败（篡改/跨用户/跨机器）返回 null。
  static String? unprotect(String b64Cipher) {
    if (!supported || b64Cipher.isEmpty) return null;
    try {
      final out = _call(_unprotect, base64.decode(b64Cipher));
      return out == null ? null : utf8.decode(out);
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _call(_BlobFn fn, List<int> input) {
    if (input.isEmpty) return null;
    final inBlob = calloc<_DataBlob>();
    final outBlob = calloc<_DataBlob>();
    final data = calloc<Uint8>(input.length);
    try {
      for (var i = 0; i < input.length; i++) {
        data[i] = input[i];
      }
      inBlob.ref.cbData = input.length;
      inBlob.ref.pbData = data;
      outBlob.ref.cbData = 0;
      outBlob.ref.pbData = nullptr;
      final ok = fn(
          inBlob, nullptr, nullptr, nullptr, nullptr, _uiForbidden, outBlob);
      if (ok == 0 || outBlob.ref.cbData == 0 || outBlob.ref.pbData == nullptr) {
        return null;
      }
      // 拷贝出来再释放：asTypedList 视图在 LocalFree 后失效
      return Uint8List.fromList(
          outBlob.ref.pbData.asTypedList(outBlob.ref.cbData));
    } finally {
      if (outBlob.ref.pbData != nullptr) {
        _localFree(outBlob.ref.pbData.cast());
      }
      calloc.free(data);
      calloc.free(inBlob);
      calloc.free(outBlob);
    }
  }
}
