import '../client/rpc_account_client.dart';

/// Source of a Bearer token for outgoing RPC requests.
abstract interface class IBearerTokenProvider {
  Future<String> getToken();
}

/// Delegates to [RpcAccountClient.ensureValidToken], which refreshes
/// the access token automatically when it is expired.
class RpcAccountClientTokenProvider implements IBearerTokenProvider {
  RpcAccountClientTokenProvider(this._client);

  final RpcAccountClient _client;

  @override
  Future<String> getToken() => _client.ensureValidToken();
}

/// Returns a fixed token. Useful for tests or server-to-server calls
/// where the token is managed externally.
class StaticTokenProvider implements IBearerTokenProvider {
  StaticTokenProvider(this._token);

  final String _token;

  @override
  Future<String> getToken() async => _token;
}
