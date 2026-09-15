import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zoo_desktop_pet/core/animals.dart';
import 'package:zoo_desktop_pet/core/url_safety.dart';

void main() {
  group('kAnimals 数据完整性', () {
    test('动物 id 全局唯一（id 是资源文件名+存档文件名，重复会串档）', () {
      final ids = kAnimals.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('每个动物都有对应 PNG 资源', () {
      for (final a in kAnimals) {
        final f = File('assets/animals/${a.id}.png');
        expect(f.existsSync(), isTrue, reason: '缺少 ${a.id}.png');
      }
    });

    test('animalById 未知 id 回落首个动物', () {
      expect(animalById('cat').id, 'cat');
      expect(animalById('no_such_animal').id, kAnimals.first.id);
    });
  });

  group('isUnsafeHttpUrl 安全边界', () {
    test('公网 http 拦截', () {
      expect(isUnsafeHttpUrl('http://api.example.com/v1'), isTrue);
      expect(isUnsafeHttpUrl('http://192.168.1.10:8080/v1'), isTrue);
    });

    test('本地地址放行（localhost/127.0.0.1/[::1]/::1）', () {
      expect(isUnsafeHttpUrl('http://localhost:11434/v1'), isFalse);
      expect(isUnsafeHttpUrl('http://127.0.0.1:11434/v1'), isFalse);
      expect(isUnsafeHttpUrl('http://[::1]:11434/v1'), isFalse);
    });

    test('https 放行', () {
      expect(isUnsafeHttpUrl('https://api.example.com/v1'), isFalse);
    });

    test('无 scheme / 畸形输入不崩且返回 false', () {
      expect(isUnsafeHttpUrl(''), isFalse);
      expect(isUnsafeHttpUrl('not a url'), isFalse);
      expect(isUnsafeHttpUrl('  '), isFalse);
    });
  });
}
