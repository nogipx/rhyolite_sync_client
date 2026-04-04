import 'package:rpc_dart/rpc_dart.dart';

abstract interface class ISubscriptionRepository {
  Future<bool> hasActiveSubscription(String userId, {required String userJwt, RpcContext? context});
}
