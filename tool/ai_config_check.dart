import 'package:zoo_desktop_pet/core/config.dart';

void main() {
  final c = AiConfig(baseUrl: 'https://api.example.com/v1', apiKey: 'sk-test-123-你好', model: 'm');
  final j = c.toJson();
  final stored = j['apiKey'] as String;
  print('serialized prefix: ${stored.substring(0, stored.length > 12 ? 12 : stored.length)}');
  print('contains plain: ${stored.contains('sk-test')}');
  final back = AiConfig.fromJson(j);
  print('roundtrip ok: ${back.apiKey == 'sk-test-123-你好'}');

  // legacy plaintext migration
  final legacy = AiConfig.fromJson({'apiKey': 'sk-legacy-plain'});
  print('legacy load ok: ${legacy.apiKey == 'sk-legacy-plain'}');
  final migrated = legacy.toJson()['apiKey'] as String;
  print('legacy re-save encrypted: ${migrated.startsWith('dpapi:')}');
}
