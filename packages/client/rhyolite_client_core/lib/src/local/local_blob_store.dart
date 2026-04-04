import 'dart:typed_data';

import 'package:rpc_blob/rpc_blob.dart';

class LocalBlobStore {
  LocalBlobStore(this._repo);

  final IBlobRepository _repo;

  String _collection(String vaultId) => 'blobs_$vaultId';

  Future<void> write(
    Uint8List bytes,
    String blobId, {
    required String vaultId,
  }) async {
    await _repo.writeBlob(
      BlobWriteRequest(
        collection: _collection(vaultId),
        id: blobId,
        bytes: Stream.value(bytes),
        length: bytes.length,
      ),
    );
  }

  Future<void> deleteBlobs(List<String> blobIds, {required String vaultId}) async {
    final collection = _collection(vaultId);
    for (final blobId in blobIds) {
      await _repo.deleteBlob(collection, blobId);
    }
  }

  Future<Uint8List?> read(String blobId, {required String vaultId}) async {
    final result = await _repo.readBlob(
      BlobReadRequest(collection: _collection(vaultId), id: blobId),
    );
    if (result == null) return null;
    final builder = BytesBuilder();
    await for (final chunk in result.bytes) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}
