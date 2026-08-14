import 'package:JsxposedX/core/utils/encrypt_util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EncryptUtil AES', () {
    test('round-trip decrypt(encrypt(x)) == x', () {
      const plain = 'hello 世界, 1234567890 !@#';
      const password = 'p@ssw0rd';
      final cipher = EncryptUtil.aesEncrypt(plain, password);
      expect(cipher, isNot(plain));
      expect(EncryptUtil.aesDecrypt(cipher, password), plain);
    });

    test('different passwords produce different ciphertext', () {
      const plain = 'secret';
      final c1 = EncryptUtil.aesEncrypt(plain, 'pass-a');
      final c2 = EncryptUtil.aesEncrypt(plain, 'pass-b');
      expect(c1, isNot(c2));
    });

    test('same password+plaintext is deterministic', () {
      const plain = 'stable';
      final c1 = EncryptUtil.aesEncrypt(plain, 'pw');
      final c2 = EncryptUtil.aesEncrypt(plain, 'pw');
      expect(c1, c2);
    });

    test('empty string round-trips', () {
      const password = 'pw';
      final cipher = EncryptUtil.aesEncrypt('', password);
      expect(EncryptUtil.aesDecrypt(cipher, password), '');
    });

    test('decrypt with wrong password throws (padding corruption detected)', () {
      final cipher = EncryptUtil.aesEncrypt('data', 'right');
      expect(
        () => EncryptUtil.aesDecrypt(cipher, 'wrong'),
        throwsA(anything),
      );
    });
  });
}
