import 'package:zoo_desktop_pet/core/dpapi.dart';

void main() {
  const secret = 'sk-test-1234-你好世界';
  final cipher = Dpapi.protect(secret);
  if (cipher == null) {
    print('PROTECT FAILED');
    return;
  }
  print('cipher(base64, ${cipher.length} chars): ${cipher.substring(0, 32)}...');
  print('contains plain secret: ${cipher.contains('sk-test') ? 'YES(BAD)' : 'no(good)'}');
  final plain = Dpapi.unprotect(cipher);
  print('roundtrip: ${plain == secret ? 'OK' : 'FAIL -> $plain'}');
  print('tampered input rejected: ${Dpapi.unprotect('QUJDRA==') == null ? 'OK' : 'FAIL'}');
  print('empty protect: ${Dpapi.protect('') == null ? 'OK(null)' : 'FAIL'}');
}
