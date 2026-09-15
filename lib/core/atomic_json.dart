import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

/// 原子 JSON 落盘工具。
///
/// 使用「写临时文件 → rename 覆盖」策略，避免进程被杀时 JSON 被截断。
/// 解析失败时将损坏文件保留为 `.corrupt-<ts>.json` 备份，
/// 所有异常通过 `debugPrint` 输出以便排障。
class AtomicJson {
  /// 将 [data] 以 pretty JSON 原子写入 [file]。
  /// 成功返回 true；失败返回 false 并输出日志。
  static bool write(File file, Map<String, dynamic> data) {
    final content = const JsonEncoder.withIndent('  ').convert(data);
    return _writeRaw(file, content);
  }

  /// 将原始 JSON 字符串原子写入 [file]。
  static bool _writeRaw(File file, String content) {
    try {
      final tmp = File('${file.path}.tmp');
      tmp.writeAsStringSync(content, flush: true);
      // 备份旧文件（如果存在），然后原子替换
      if (file.existsSync()) {
        final backup = File('${file.path}.bak');
        if (backup.existsSync()) backup.deleteSync();
        file.renameSync(backup.path);
      }
      tmp.renameSync(file.path);
      return true;
    } catch (e, st) {
      debugPrint('AtomicJson write failed for ${file.path}: $e\n$st');
      return false;
    }
  }

  /// 安全读取 JSON 文件。解析失败时保留损坏文件并输出日志。
  static Map<String, dynamic>? read(File file) {
    try {
      if (!file.existsSync()) return null;
      final raw = file.readAsStringSync();
      return jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException catch (e) {
      // JSON 损坏：保留现场并回退 null。
      // 注意备份名不能以 .json 结尾，否则会被 GrowthSnapshot.loadAll()
      // 等按 .json 后缀扫描的逻辑再次读到，导致每次扫描都重复"解析失败→改名"。
      final ts = DateTime.now().millisecondsSinceEpoch;
      final backup = File('${file.path}.corrupt-$ts');
      try {
        file.renameSync(backup.path);
        debugPrint('AtomicJson: ${file.path} 解析失败，已备份为 ${backup.uri.pathSegments.last}');
      } catch (_) {
        debugPrint('AtomicJson: 备份 ${file.path} 也失败了: $e');
      }
      return null;
    } catch (e) {
      debugPrint('AtomicJson read failed for ${file.path}: $e');
      return null;
    }
  }
}
