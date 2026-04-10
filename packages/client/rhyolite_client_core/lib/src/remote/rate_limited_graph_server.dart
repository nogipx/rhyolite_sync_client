import 'package:rhyolite_graph/rhyolite_graph.dart';

import '../engine/rate_limiter.dart';

/// Decorates [IGraphServer] with token-bucket rate limiting.
/// Every outbound RPC call acquires one token before proceeding.
class RateLimitedGraphServer implements IGraphServer {
  const RateLimitedGraphServer(this._inner, this._limiter);

  final IGraphServer _inner;
  final RateLimiter _limiter;

  @override
  Future<List<FilePullResult>> pull(List<FileSyncCursor> cursors) async {
    await _limiter.acquire();
    return _inner.pull(cursors);
  }

  @override
  Future<void> push(List<NodeRecord> nodes) async {
    await _limiter.acquire();
    return _inner.push(nodes);
  }

  @override
  Future<int> getVaultEpoch() async {
    await _limiter.acquire();
    return _inner.getVaultEpoch();
  }

  @override
  Future<void> resetVault() async {
    await _limiter.acquire();
    return _inner.resetVault();
  }

  @override
  Future<String> acquireLock(String vaultId) async {
    await _limiter.acquire();
    return _inner.acquireLock(vaultId);
  }

  @override
  Future<void> releaseLock(String vaultId, String lockToken) async {
    await _limiter.acquire();
    return _inner.releaseLock(vaultId, lockToken);
  }

  @override
  Future<void> renewLock(String vaultId, String lockToken) async {
    await _limiter.acquire();
    return _inner.renewLock(vaultId, lockToken);
  }

  @override
  Future<void> deleteNodes(List<String> keys) async {
    await _limiter.acquire();
    return _inner.deleteNodes(keys);
  }
}
