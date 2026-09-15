import 'dart:io';

import 'package:zoo_desktop_pet/core/config.dart';

/// 为每个测试创建独立临时根目录并注入 AppPaths，返回临时目录。
/// 必须与 [teardownPaths] 配对使用。
Directory setupPaths() {
  final tmp = Directory.systemTemp.createTempSync('zoo_test_');
  AppPaths.resetForTesting(tmp.path);
  return tmp;
}

/// 清除 AppPaths 覆盖并删除临时目录。
void teardownPaths(Directory tmp) {
  AppPaths.resetForTesting();
  if (tmp.existsSync()) tmp.deleteSync(recursive: true);
}
