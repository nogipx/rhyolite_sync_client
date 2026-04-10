import 'package:rhyolite_client_core/src/engine/rate_limiter.dart';
import 'package:test/test.dart';

void main() {
  group('RateLimiter', () {
    test('allows maxPerSecond calls immediately (bucket starts full)', () async {
      final limiter = RateLimiter(maxPerSecond: 5);

      // All 5 tokens should be consumed without waiting.
      final sw = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        await limiter.acquire();
      }
      sw.stop();

      // Should complete well under 100ms (no waits).
      expect(sw.elapsedMilliseconds, lessThan(100));
    });

    test('blocks when bucket is empty and resumes after refill', () async {
      final limiter = RateLimiter(maxPerSecond: 10);

      // Drain the bucket.
      for (var i = 0; i < 10; i++) {
        await limiter.acquire();
      }

      // 11th acquire should take at least ~100ms (1 token at 10/sec = 100ms).
      final sw = Stopwatch()..start();
      await limiter.acquire();
      sw.stop();

      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(80),
          reason: 'must wait for token to refill');
    });

    test('throughput does not exceed maxPerSecond after initial burst', () async {
      const rate = 20; // 20/sec → ~10 calls in 500ms
      final limiter = RateLimiter(maxPerSecond: rate);

      // Drain the initial full bucket so we're measuring only the refill rate.
      for (var i = 0; i < rate; i++) {
        await limiter.acquire();
      }

      var calls = 0;
      final sw = Stopwatch()..start();

      // After draining, fire for 500ms — only refilled tokens allowed.
      while (sw.elapsedMilliseconds < 500) {
        await limiter.acquire();
        calls++;
      }

      // At 20/sec for 500ms: expect ~10 calls ± 2 for timing jitter.
      expect(calls, lessThanOrEqualTo(rate ~/ 2 + 3),
          reason: 'sustained rate must not exceed maxPerSecond');
    });

    test('multiple concurrent waiters all eventually complete', () async {
      final limiter = RateLimiter(maxPerSecond: 50);

      // Drain the bucket first.
      for (var i = 0; i < 50; i++) {
        await limiter.acquire();
      }

      // Launch 5 concurrent waiters.
      final futures = List.generate(5, (_) => limiter.acquire());
      final results = await Future.wait(futures).timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('waiters did not complete'),
      );

      expect(results, hasLength(5));
    });

    test('acquire is a no-op when tokens are available (no await)', () async {
      final limiter = RateLimiter(maxPerSecond: 100);

      // 100 tokens available — all should resolve immediately.
      final sw = Stopwatch()..start();
      await Future.wait(List.generate(100, (_) => limiter.acquire()));
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(200));
    });
  });
}

/// Simple timeout exception for tests.
class TimeoutException implements Exception {
  const TimeoutException(this.message);
  final String message;
  @override
  String toString() => 'TimeoutException: $message';
}
