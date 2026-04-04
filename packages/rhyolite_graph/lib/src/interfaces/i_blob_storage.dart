import 'dart:typed_data';

abstract interface class IBlobStorage {
  Future<Map<String, Uint8List>> download(List<String> blobIds);
  Future<void> upload(List<(Uint8List bytes, String blobId)> blobs);
}