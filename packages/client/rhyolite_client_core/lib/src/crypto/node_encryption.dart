import 'dart:convert';
import 'dart:typed_data';

import 'package:rhyolite_graph/rhyolite_graph.dart';

/// Encrypts sensitive fields of a [NodeRecord] into [encryptedPayload]
/// before pushing to the server.
Future<NodeRecord> encryptNode(NodeRecord node, IVaultCipher cipher) async {
  return switch (node) {
    VaultRecord() => _encryptVault(node, cipher),
    FileRecord() => _encryptFile(node, cipher),
    ChangeRecord() => _encryptChange(node, cipher),
    MoveRecord() => _encryptMove(node, cipher),
    DeleteRecord() => node, // no sensitive fields
  };
}

/// Decrypts [encryptedPayload] and restores sensitive fields after pulling
/// from the server.
Future<NodeRecord> decryptNode(NodeRecord node, IVaultCipher cipher) async {
  return switch (node) {
    VaultRecord() => _decryptVault(node, cipher),
    FileRecord() => _decryptFile(node, cipher),
    ChangeRecord() => _decryptChange(node, cipher),
    MoveRecord() => _decryptMove(node, cipher),
    DeleteRecord() => node,
  };
}

// ---------------------------------------------------------------------------
// Encrypt
// ---------------------------------------------------------------------------

Future<VaultRecord> _encryptVault(VaultRecord node, IVaultCipher cipher) async {
  final payload = {'name': node.name};
  return VaultRecord(
    key: node.key,
    vaultId: node.vaultId,
    parentKey: node.parentKey,
    isSynced: node.isSynced,
    createdAt: node.createdAt,
    name: node.name,
    encryptedPayload: await _encrypt(payload, cipher),
  );
}

Future<FileRecord> _encryptFile(FileRecord node, IVaultCipher cipher) async {
  final payload = {'path': node.path};
  return FileRecord(
    key: node.key,
    vaultId: node.vaultId,
    parentKey: node.parentKey,
    isSynced: node.isSynced,
    createdAt: node.createdAt,
    fileId: node.fileId,
    path: node.path,
    encryptedPayload: await _encrypt(payload, cipher),
  );
}

Future<ChangeRecord> _encryptChange(ChangeRecord node, IVaultCipher cipher) async {
  final payload = {'sizeBytes': node.sizeBytes};
  return ChangeRecord(
    key: node.key,
    vaultId: node.vaultId,
    parentKey: node.parentKey,
    isSynced: node.isSynced,
    createdAt: node.createdAt,
    fileId: node.fileId,
    blobId: node.blobId,
    sizeBytes: node.sizeBytes,
    encryptedPayload: await _encrypt(payload, cipher),
  );
}

Future<MoveRecord> _encryptMove(MoveRecord node, IVaultCipher cipher) async {
  final payload = {'fromPath': node.fromPath, 'toPath': node.toPath};
  return MoveRecord(
    key: node.key,
    vaultId: node.vaultId,
    parentKey: node.parentKey,
    isSynced: node.isSynced,
    createdAt: node.createdAt,
    fileId: node.fileId,
    fromPath: node.fromPath,
    toPath: node.toPath,
    encryptedPayload: await _encrypt(payload, cipher),
  );
}

// ---------------------------------------------------------------------------
// Decrypt
// ---------------------------------------------------------------------------

Future<VaultRecord> _decryptVault(VaultRecord node, IVaultCipher cipher) async {
  final payload = await _decrypt(node.encryptedPayload, cipher);
  if (payload == null) return node;
  return VaultRecord(
    key: node.key,
    vaultId: node.vaultId,
    parentKey: node.parentKey,
    isSynced: node.isSynced,
    createdAt: node.createdAt,
    name: payload['name'] as String? ?? '',
    encryptedPayload: node.encryptedPayload,
  );
}

Future<FileRecord> _decryptFile(FileRecord node, IVaultCipher cipher) async {
  final payload = await _decrypt(node.encryptedPayload, cipher);
  if (payload == null) return node;
  return FileRecord(
    key: node.key,
    vaultId: node.vaultId,
    parentKey: node.parentKey,
    isSynced: node.isSynced,
    createdAt: node.createdAt,
    fileId: node.fileId,
    path: payload['path'] as String? ?? '',
    encryptedPayload: node.encryptedPayload,
  );
}

Future<ChangeRecord> _decryptChange(ChangeRecord node, IVaultCipher cipher) async {
  final payload = await _decrypt(node.encryptedPayload, cipher);
  if (payload == null) return node;
  return ChangeRecord(
    key: node.key,
    vaultId: node.vaultId,
    parentKey: node.parentKey,
    isSynced: node.isSynced,
    createdAt: node.createdAt,
    fileId: node.fileId,
    blobId: node.blobId,
    sizeBytes: payload['sizeBytes'] as int? ?? 0,
    encryptedPayload: node.encryptedPayload,
  );
}

Future<MoveRecord> _decryptMove(MoveRecord node, IVaultCipher cipher) async {
  final payload = await _decrypt(node.encryptedPayload, cipher);
  if (payload == null) return node;
  return MoveRecord(
    key: node.key,
    vaultId: node.vaultId,
    parentKey: node.parentKey,
    isSynced: node.isSynced,
    createdAt: node.createdAt,
    fileId: node.fileId,
    fromPath: payload['fromPath'] as String? ?? '',
    toPath: payload['toPath'] as String? ?? '',
    encryptedPayload: node.encryptedPayload,
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<String> _encrypt(Map<String, dynamic> payload, IVaultCipher cipher) async {
  final bytes = utf8.encode(jsonEncode(payload));
  final encrypted = await cipher.encrypt(Uint8List.fromList(bytes));
  return base64Encode(encrypted);
}

Future<Map<String, dynamic>?> _decrypt(String? encryptedPayload, IVaultCipher cipher) async {
  if (encryptedPayload == null) return null;
  try {
    final encrypted = base64Decode(encryptedPayload);
    final decrypted = await cipher.decrypt(encrypted);
    return jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>;
  } catch (_) {
    // Wrong key or corrupted payload — treat as undecryptable.
    return null;
  }
}
