import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:paseto_dart/paseto_dart.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

/// [IVaultCipher] implementation using PASETO v4 local (XChaCha20-Poly1305 + BLAKE2b).
///
/// Key derivation: Argon2id(passphrase, salt=vaultId, m=65536, t=3, p=4).
/// Deterministic — same passphrase + vaultId always produce the same key,
/// so any client can derive it without exchanging a wrappedKey.
class VaultCipher implements IVaultCipher {
  static const _verifyPlaintext = 'rhyolite-verify';

  // Argon2id parameters: 64 MiB memory, 3 iterations, 4 threads.
  // Provides ~1–2 s KDF time on typical hardware — adequate protection
  // while remaining usable in a browser environment.
  static final _argon2 = crypto.Argon2id(
    parallelism: 4,
    memory: 65536, // 64 MiB
    iterations: 3,
    hashLength: 32,
  );

  final K4LocalKey _key;

  VaultCipher._(this._key);

  /// Derives vault cipher from [passphrase] and [vaultId].
  /// Uses vaultId as Argon2id salt — unique per vault, shared between clients.
  static Future<VaultCipher> derive(String passphrase, String vaultId) async {
    final secretKey = await _argon2.deriveKey(
      secretKey: crypto.SecretKey(utf8.encode(passphrase)),
      nonce: utf8.encode(vaultId),
    );
    final keyBytes = await secretKey.extractBytes();
    return VaultCipher._(K4LocalKey(Uint8List.fromList(keyBytes)));
  }

  /// Creates a verification token — encrypt a known constant so the passphrase
  /// can be validated later without storing the raw key.
  Future<String> createVerificationToken() async {
    final bytes = await encrypt(Uint8List.fromList(utf8.encode(_verifyPlaintext)));
    return base64Encode(bytes);
  }

  /// Returns true if [token] decrypts to the known constant — i.e. passphrase is correct.
  Future<bool> verifyToken(String token) async {
    try {
      final bytes = await decrypt(base64Decode(token));
      return utf8.decode(bytes) == _verifyPlaintext;
    } catch (_) {
      return false;
    }
  }

  /// Restores cipher from previously saved raw key bytes (remembered key).
  factory VaultCipher.fromRawKey(Uint8List bytes) => VaultCipher._(K4LocalKey(bytes));

  /// Raw key bytes — use only for secure persistent storage (e.g. OS keychain).
  Uint8List get rawKeyBytes => _key.rawBytes;

  @override
  Future<Uint8List> encrypt(Uint8List plaintext) async {
    final secretKey = SecretKeyData(_key.rawBytes);
    final payload = await LocalV4.encrypt(
      Package(content: plaintext),
      secretKey: secretKey,
    );
    // Serialize token to bytes via its string representation
    final token = Token(
      header: LocalV4.header,
      payload: payload,
      footer: null,
    );
    return Uint8List.fromList(utf8.encode(token.toTokenString));
  }

  @override
  Future<Uint8List> decrypt(Uint8List ciphertext) async {
    final secretKey = SecretKeyData(_key.rawBytes);
    final token = await Token.fromString(utf8.decode(ciphertext));
    final package = await LocalV4.decrypt(token, secretKey: secretKey);
    return Uint8List.fromList(package.content);
  }
}
