import 'dart:async';

import 'package:paseto_dart/paseto_dart.dart';
import 'package:rhyolite_client_account/rhyolite_client_account.dart';
import 'package:rpc_dart/rpc_dart.dart';

/// Server-side interceptor that verifies PASETO v4.public Bearer tokens locally.
///
/// Drop-in replacement for [SupabaseTokenVerifier] when using [SqliteAuthServiceResponder].
/// Requires only the Ed25519 public key — no network call needed.
///
/// Usage:
/// ```dart
/// final interceptor = PasetoTokenVerifier(
///   publicKey: tokenService.publicKey,
///   publicMethods: {'RhyoliteAuth/signIn', 'RhyoliteAuth/signUp'},
/// );
/// ```
class PasetoTokenVerifier implements IRpcInterceptor {
  PasetoTokenVerifier({
    required PaserkPublicKey publicKey,
    Set<String> publicMethods = const {},
  }) : _publicKey = publicKey,
       _publicMethods = publicMethods;

  final PaserkPublicKey _publicKey;
  final Set<String> _publicMethods;

  bool _isPublic(RpcMiddlewareContext call) =>
      _publicMethods.contains('${call.serviceName}/${call.methodName}') ||
      _publicMethods.contains(call.methodName);

  Future<RpcContext> _authenticate(RpcMiddlewareContext call) async {
    final authHeader = call.context.getHeader('authorization');
    if (authHeader == null || !authHeader.startsWith('Bearer ')) {
      throw RpcException(
        'unauthenticated: missing or invalid Authorization header',
      );
    }

    final token = authHeader.substring('Bearer '.length);

    try {
      final payload = await Paseto.verifyPublicToken(
        token: token,
        publicKey: _publicKey,
      );

      final exp = payload['exp'] as int?;
      if (exp != null && DateTime.now().millisecondsSinceEpoch ~/ 1000 >= exp) {
        throw RpcException('unauthenticated: token expired');
      }

      final userId = payload['sub'] as String?;
      if (userId == null) {
        throw RpcException('unauthenticated: missing sub claim');
      }

      return call.context
          .withValue(RhyoliteAuthKeys.userId, userId)
          .withValue(RhyoliteAuthKeys.userToken, token);
    } on RpcException {
      rethrow;
    } catch (_) {
      throw RpcException('unauthenticated: invalid token');
    }
  }

  @override
  Future<TResponse> interceptUnary<TRequest, TResponse>(
    RpcMiddlewareContext call,
    TRequest request,
    RpcUnaryNext<TRequest, TResponse> next,
  ) async {
    if (!_isPublic(call)) call.updateContext(await _authenticate(call));
    return next(call.context, request);
  }

  @override
  FutureOr<Stream<TResponse>> interceptServerStream<TRequest, TResponse>(
    RpcMiddlewareContext call,
    TRequest request,
    RpcServerStreamNext<TRequest, TResponse> next,
  ) async {
    if (!_isPublic(call)) call.updateContext(await _authenticate(call));
    return next(call.context, request);
  }

  @override
  Future<TResponse> interceptClientStream<TRequest, TResponse>(
    RpcMiddlewareContext call,
    Stream<TRequest> requests,
    RpcClientStreamNext<TRequest, TResponse> next,
  ) async {
    if (!_isPublic(call)) call.updateContext(await _authenticate(call));
    return next(call.context, requests);
  }

  @override
  FutureOr<Stream<TResponse>> interceptBidirectionalStream<TRequest, TResponse>(
    RpcMiddlewareContext call,
    Stream<TRequest> requests,
    RpcBidirectionalStreamNext<TRequest, TResponse> next,
  ) async {
    if (!_isPublic(call)) call.updateContext(await _authenticate(call));
    return next(call.context, requests);
  }
}
