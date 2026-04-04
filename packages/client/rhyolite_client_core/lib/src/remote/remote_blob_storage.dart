import 'dart:typed_data';

import 'package:rhyolite_graph/rhyolite_graph.dart';

import '../contract/blob_contract.dart';

const _chunkSize = 256 * 1024;

class RemoteBlobStorage implements IBlobStorage {
  RemoteBlobStorage({
    required BlobContractCaller caller,
    required this.vaultId,
    IVaultCipher? cipher,
  }) : _caller = caller, _cipher = cipher;

  final BlobContractCaller _caller;
  final String vaultId;
  final IVaultCipher? _cipher;

  @override
  Future<Map<String, Uint8List>> download(List<String> blobIds) async {
    if (blobIds.isEmpty) return {};
    final stream = _caller.download(
      BulkDownloadBlobRequest(vaultId: vaultId, blobIds: blobIds),
    );
    final result = <String, Uint8List>{};
    String? currentBlobId;
    BytesBuilder? currentBuilder;
    await for (final chunk in stream) {
      if (chunk.blobId != null) {
        currentBlobId = chunk.blobId;
        currentBuilder = BytesBuilder();
      }
      currentBuilder?.add(chunk.bytes);
      if (chunk.last && currentBlobId != null && currentBuilder != null) {
        final raw = currentBuilder.takeBytes();
        final cipher = _cipher;
        result[currentBlobId] = cipher != null ? await cipher.decrypt(raw) : raw;
        currentBlobId = null;
        currentBuilder = null;
      }
    }
    return result;
  }

  @override
  Future<void> upload(List<(Uint8List bytes, String blobId)> blobs) async {
    if (blobs.isEmpty) return;
    await _caller.upload(_toBulkChunks(blobs));
  }

  Stream<BlobChunk> _toBulkChunks(
    List<(Uint8List bytes, String blobId)> blobs,
  ) async* {
    for (final (rawBytes, blobId) in blobs) {
      final cipher = _cipher;
      final data = cipher != null ? await cipher.encrypt(rawBytes) : rawBytes;
      yield* _toChunks(data, blobId);
    }
  }

  Stream<BlobChunk> _toChunks(Uint8List bytes, String blobId) async* {
    // Always yield at least one chunk to carry blobId/vaultId metadata.
    // An empty stream causes the server to throw before returning a response,
    // which the RPC framework doesn't propagate — resulting in a 30s timeout.
    if (bytes.isEmpty) {
      yield BlobChunk(
        bytes: Uint8List(0),
        offset: 0,
        last: true,
        blobId: blobId,
        vaultId: vaultId,
      );
      return;
    }
    var offset = 0;
    var first = true;
    while (offset < bytes.length) {
      final end = (offset + _chunkSize).clamp(0, bytes.length);
      yield BlobChunk(
        bytes: bytes.sublist(offset, end),
        offset: offset,
        last: end == bytes.length,
        blobId: first ? blobId : null,
        vaultId: first ? vaultId : null,
      );
      offset = end;
      first = false;
    }
  }
}
