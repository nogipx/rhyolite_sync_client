import 'dart:typed_data';

abstract interface class IContentMerger {
  /// Returns merged bytes, or null if merge failed.
  Uint8List? tryMerge(Uint8List base, Uint8List local, Uint8List remote);
}