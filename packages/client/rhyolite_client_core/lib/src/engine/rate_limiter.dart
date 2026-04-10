import 'dart:math';

/// Token bucket rate limiter.
///
/// Allows up to [maxPerSecond] calls per second. Callers [acquire] a token
/// before each network request; if the bucket is empty they wait until
/// enough tokens have refilled.
///
/// A single shared instance in [SyncEngine] coordinates all outbound RPC
/// calls (graph pull/push and blob upload/download) under one budget.
class RateLimiter {
  RateLimiter({required this.maxPerSecond})
      : _tokens = maxPerSecond.toDouble(),
        _lastRefill = DateTime.now();

  final int maxPerSecond;

  double _tokens;
  DateTime _lastRefill;

  /// Acquires [count] tokens, waiting if the bucket is empty.
  Future<void> acquire([int count = 1]) async {
    assert(count >= 1 && count <= maxPerSecond);
    while (true) {
      _refill();
      if (_tokens >= count) {
        _tokens -= count;
        return;
      }
      // Wait until enough tokens are available.
      final needed = count - _tokens;
      final waitMs = (needed / maxPerSecond * 1000).ceil();
      await Future.delayed(Duration(milliseconds: waitMs));
    }
  }

  void _refill() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRefill).inMicroseconds / 1e6;
    _tokens = min(_tokens + elapsed * maxPerSecond, maxPerSecond.toDouble());
    _lastRefill = now;
  }
}
