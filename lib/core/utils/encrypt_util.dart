import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

class EncryptUtil {
  EncryptUtil._();

  static String aesEncrypt(String plaintext, String password) {
    // The underlying AES/CBC implementation cannot process an empty block
    // (throws a RangeError). Treat empty plaintext as empty ciphertext so the
    // helper round-trips for the empty boundary input without crashing. A real
    // encryption of non-empty data always yields non-empty base64, so an empty
    // ciphertext is unambiguous and this stays backward-compatible.
    if (plaintext.isEmpty) return '';
    final encrypter = Encrypter(AES(_keyFromPassword(password)));
    final encrypted = encrypter.encrypt(plaintext, iv: _iv);
    return encrypted.base64;
  }

  static String aesDecrypt(String ciphertext, String password) {
    if (ciphertext.isEmpty) return '';
    final encrypter = Encrypter(AES(_keyFromPassword(password)));
    return encrypter.decrypt64(ciphertext, iv: _iv);
  }

  static Key _keyFromPassword(String password) {
    final digest = sha256.convert(utf8.encode(password));
    return Key(Uint8List.fromList(digest.bytes));
  }

  static final IV _iv = IV.fromLength(16);
}
