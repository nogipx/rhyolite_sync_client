import 'package:rhyolite_client_account/rhyolite_client_account.dart';
import 'package:rpc_dart/rpc_dart.dart';

/// RPC-based account client.
///
/// Replaces [SupabaseAuthClient] — talks to account-service via HTTP
/// using [IAuthContract], [IVaultContract], and [ISubscriptionContract].
///
/// Usage:
/// ```dart
/// final transport = RpcHttpCallerTransport(baseUrl: 'http://account:8081');
/// final endpoint = RpcCallerEndpoint(transport);
/// final client = RpcAccountClient(endpoint);
/// ```
class RpcAccountClient {
  RpcAccountClient(RpcCallerEndpoint endpoint)
    : _auth = AuthContractCaller(endpoint),
      _vault = VaultContractCaller(endpoint),
      _subscription = SubscriptionContractCaller(endpoint);

  final AuthContractCaller _auth;
  final VaultContractCaller _vault;
  final SubscriptionContractCaller _subscription;

  // ---------------------------------------------------------------------------
  // Session state
  // ---------------------------------------------------------------------------

  AuthSession? _session;

  AuthSession? get session => _session;
  String? get accessToken => _session?.accessToken;
  String? get email => _session?.email;
  String? get userId => _session?.userId;
  bool get isSignedIn => _session != null && !(_session!.isExpired);

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  Future<AuthSession> signUp(String email, String password) async {
    final session = await _auth.signUp(
      SignUpRequest(email: email, password: password),
    );
    _session = session;
    return session;
  }

  Future<AuthSession> signIn(String email, String password) async {
    final session = await _auth.signIn(
      SignInRequest(email: email, password: password),
    );
    _session = session;
    return session;
  }

  Future<AuthSession> refreshSession() async {
    final token = _session?.refreshToken;
    if (token == null) throw StateError('Not signed in');
    final session = await _auth.refresh(RefreshRequest(refreshToken: token));
    _session = session;
    return session;
  }

  /// Returns a valid access token, refreshing if needed.
  Future<String> ensureValidToken() async {
    final s = _session;
    if (s == null) throw StateError('Not signed in');
    if (s.isExpired) await refreshSession();
    return _session!.accessToken;
  }

  /// Verify email with token from the verification link.
  /// Returns true if a trial subscription was activated.
  Future<bool> verifyEmail(String token) async {
    final response = await _auth.verifyEmail(VerifyEmailRequest(token: token));
    return response.trialActivated;
  }

  Future<bool> getEmailVerified() async {
    final response = await _auth.getEmailVerified(
      const GetEmailVerifiedRequest(),
      context: await _authContext(),
    );
    return response.emailVerified;
  }

  Future<void> resendVerificationEmail() async {
    await _auth.resendVerificationEmail(
      const ResendVerificationRequest(),
      context: await _authContext(),
    );
  }

  Future<void> signOut() async {
    final token = _session?.refreshToken;
    if (token == null) return;
    try {
      await _auth.signOut(SignOutRequest(refreshToken: token));
    } finally {
      _session = null;
    }
  }

  /// Restore a previously persisted session without a network call.
  void useSession(AuthSession saved) {
    _session = saved;
  }

  // ---------------------------------------------------------------------------
  // Vaults
  // ---------------------------------------------------------------------------

  Future<List<VaultDto>> listVaults() async {
    final response = await _vault.listVaults(
      const ListVaultsRequest(),
      context: await _authContext(),
    );
    return response.vaults;
  }

  Future<void> createVault({
    required String vaultId,
    required String vaultName,
  }) async {
    await _vault.createVault(
      CreateVaultRequest(vaultId: vaultId, vaultName: vaultName),
      context: await _authContext(),
    );
  }

  Future<void> updateVerificationToken({
    required String vaultId,
    required String verificationToken,
  }) async {
    await _vault.updateVerificationToken(
      UpdateVerificationTokenRequest(
        vaultId: vaultId,
        verificationToken: verificationToken,
      ),
      context: await _authContext(),
    );
  }

  // ---------------------------------------------------------------------------
  // Subscription
  // ---------------------------------------------------------------------------

  Future<SubscriptionDto> getSubscription() async {
    return _subscription.getSubscription(
      const GetSubscriptionRequest(),
      context: await _authContext(),
    );
  }

  Future<List<InvoiceDto>> listInvoices() async {
    final response = await _subscription.listInvoices(
      const ListInvoicesRequest(),
      context: await _authContext(),
    );
    return response.invoices;
  }

  /// Returns the list of available products/plans from the server.
  /// Checks pending payments against Selfwork and activates subscription if any succeeded.
  Future<bool> restoreSubscription() async {
    final response = await _subscription.restoreSubscription(
      const RestoreSubscriptionRequest(),
      context: await _authContext(),
    );
    return response.restored;
  }

  Future<List<ProductDto>> listProducts() async {
    final response = await _subscription.listProducts(
      const ListProductsRequest(),
      context: await _authContext(),
    );
    return response.products;
  }

  /// Create a payment session. Returns the payment URL, or null if the
  /// subscription was activated without a redirect (e.g. dev simulation).
  Future<String?> createPayment({required String planId}) async {
    final response = await _subscription.createPayment(
      CreatePaymentRequest(planId: planId),
      context: await _authContext(),
    );
    return response.paymentUrl;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<RpcContext> _authContext() async {
    final token = await ensureValidToken();
    return RpcContextBuilder.inheritFrom(
      RpcContext.empty(),
    ).withBearerAuth(token).build();
  }
}
