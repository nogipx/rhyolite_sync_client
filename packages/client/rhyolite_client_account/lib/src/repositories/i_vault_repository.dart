import 'package:rpc_dart/rpc_dart.dart';

abstract interface class IVaultAuthRepository {
  Future<bool> userOwnsVault(String userId, String vaultId, {RpcContext? context});
  Future<void> createVaultForUser(String userId, String vaultId, {RpcContext? context});
}
