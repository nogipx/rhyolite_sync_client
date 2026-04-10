import 'dart:typed_data';

import 'package:rhyolite_graph/rhyolite_graph.dart';

import '../engine/rate_limiter.dart';

/// Decorates [IBlobStorage] with token-bucket rate limiting.
class RateLimitedBlobStorage implements IBlobStorage {
  const RateLimitedBlobStorage(this._inner, this._limiter);

  final IBlobStorage _inner;
  final RateLimiter _limiter;

  @override
  Future<Map<String, Uint8List>> download(List<String> blobIds) async {
    await _limiter.acquire();
    return _inner.download(blobIds);
  }

  @override
  Future<void> upload(List<(Uint8List bytes, String blobId)> blobs) async {
    await _limiter.acquire();
    return _inner.upload(blobs);
  }
}
