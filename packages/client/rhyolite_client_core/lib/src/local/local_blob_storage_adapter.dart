import 'dart:typed_data';

import 'package:rhyolite_graph/rhyolite_graph.dart';

import 'local_blob_store.dart';

/// Bridges [LocalBlobStore] (which requires vaultId per call)
/// to the [IBlobStorage] interface (which is vaultId-agnostic).
class LocalBlobStorageAdapter implements IBlobStorage {
  LocalBlobStorageAdapter(this._store, this._vaultId);

  final LocalBlobStore _store;
  final String _vaultId;

  @override
  Future<Map<String, Uint8List>> download(List<String> blobIds) async {
    final result = <String, Uint8List>{};
    for (final blobId in blobIds) {
      final bytes = await _store.read(blobId, vaultId: _vaultId);
      if (bytes == null) throw StateError('Blob not found: $blobId');
      result[blobId] = bytes;
    }
    return result;
  }

  @override
  Future<void> upload(List<(Uint8List bytes, String blobId)> blobs) async {
    for (final (bytes, blobId) in blobs) {
      await _store.write(bytes, blobId, vaultId: _vaultId);
    }
  }
}
