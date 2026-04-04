import 'package:rhyolite_client_account/rhyolite_client_account.dart';
import 'package:uuid/uuid.dart';

enum ConflictStrategy { lww, conflictCopy }

/// Throws [FormatException] if [value] does not look like a UUID v4.
String _requireUuid(String value, String field) {
  final uuidRe = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  if (!uuidRe.hasMatch(value)) {
    throw FormatException('VaultConfig: invalid UUID in field "$field"', value);
  }
  return value;
}

/// Strips ASCII control characters and limits length.
/// Throws [FormatException] if [value] is empty after sanitization or exceeds [maxLen].
String _sanitizeText(String value, String field, {int maxLen = 256}) {
  final sanitized = value.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
  if (sanitized.isEmpty) {
    throw FormatException(
      'VaultConfig: field "$field" is empty after sanitization',
    );
  }
  if (sanitized.length > maxLen) {
    throw FormatException(
      'VaultConfig: field "$field" exceeds $maxLen characters',
    );
  }
  return sanitized;
}

/// Validates that [value] contains only base64 characters (+ padding).
/// Throws [FormatException] otherwise.
String _requireBase64(String value, String field) {
  final b64Re = RegExp(r'^[A-Za-z0-9+/=]+$');
  if (!b64Re.hasMatch(value)) {
    throw FormatException(
      'VaultConfig: field "$field" contains invalid base64 characters',
      value,
    );
  }
  return value;
}

class VaultConfig {
  const VaultConfig({
    required this.vaultId,
    required this.vaultName,
    this.e2eeEnabled = false,
    this.verificationToken,
    this.conflictStrategy = ConflictStrategy.lww,
    this.pullIntervalSeconds = 5,
    this.tokenProvider,
  });

  factory VaultConfig.newVault({
    required String vaultName,
    bool e2eeEnabled = false,
    ConflictStrategy conflictStrategy = ConflictStrategy.lww,
    int pullIntervalSeconds = 5,
  }) => VaultConfig(
    vaultId: const Uuid().v4(),
    vaultName: vaultName,
    e2eeEnabled: e2eeEnabled,
    conflictStrategy: conflictStrategy,
    pullIntervalSeconds: pullIntervalSeconds,
  );

  factory VaultConfig.fromJson(Map<String, dynamic> json) {
    final rawToken = json['verificationToken'] as String?;
    return VaultConfig(
      vaultId: _requireUuid(json['vaultId'] as String, 'vaultId'),
      vaultName: _sanitizeText(json['vaultName'] as String, 'vaultName'),
      e2eeEnabled: json['e2eeEnabled'] as bool? ?? false,
      verificationToken: rawToken != null
          ? _requireBase64(rawToken, 'verificationToken')
          : null,
      conflictStrategy: ConflictStrategy.values.byName(
        json['conflictStrategy'] as String? ?? 'lww',
      ),
      pullIntervalSeconds: ((json['pullIntervalSeconds'] as int? ?? 5)).clamp(
        5,
        3600,
      ),
    );
  }

  final String vaultId;
  final String vaultName;

  /// Whether E2EE is enabled for this vault.
  final bool e2eeEnabled;

  /// Encrypted verification token — used to validate the passphrase without
  /// storing the raw key. Base64 of encrypt("rhyolite-verify").
  final String? verificationToken;
  final ConflictStrategy conflictStrategy;
  final int pullIntervalSeconds;

  /// Optional token provider. When set, a [BearerTokenInterceptor] is
  /// added to the RPC endpoint to attach Bearer tokens to every call.
  /// Not serialized to/from JSON — must be set in code.
  final IBearerTokenProvider? tokenProvider;

  VaultConfig copyWith({
    String? vaultId,
    String? vaultName,
    bool? e2eeEnabled,
    String? verificationToken,
    ConflictStrategy? conflictStrategy,
    int? pullIntervalSeconds,
    IBearerTokenProvider? tokenProvider,
  }) => VaultConfig(
    vaultId: vaultId ?? this.vaultId,
    vaultName: vaultName ?? this.vaultName,
    e2eeEnabled: e2eeEnabled ?? this.e2eeEnabled,
    verificationToken: verificationToken ?? this.verificationToken,
    conflictStrategy: conflictStrategy ?? this.conflictStrategy,
    pullIntervalSeconds: pullIntervalSeconds ?? this.pullIntervalSeconds,
    tokenProvider: tokenProvider ?? this.tokenProvider,
  );

  Map<String, dynamic> toJson() => {
    'vaultId': vaultId,
    'vaultName': vaultName,
    'e2eeEnabled': e2eeEnabled,
    if (verificationToken != null) 'verificationToken': verificationToken,
    'conflictStrategy': conflictStrategy.name,
    'pullIntervalSeconds': pullIntervalSeconds,
  };
}
