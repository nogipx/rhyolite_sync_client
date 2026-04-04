// ignore_for_file: uri_has_not_been_generated

import 'dart:async';

import 'package:rpc_dart/rpc_dart.dart';

part 'vault_contract.g.dart';

// --- DTOs ---

class VaultDto implements IRpcSerializable {
  const VaultDto({
    required this.vaultId,
    required this.vaultName,
    this.verificationToken,
  });

  final String vaultId;
  final String vaultName;

  /// Null if E2EE has not been set up for this vault yet.
  final String? verificationToken;

  factory VaultDto.fromJson(Map<String, dynamic> json) => VaultDto(
    vaultId: json['vault_id'] as String,
    vaultName: json['vault_name'] as String,
    verificationToken: json['verification_token'] as String?,
  );

  @override
  Map<String, dynamic> toJson() => {
    'vault_id': vaultId,
    'vault_name': vaultName,
    if (verificationToken != null) 'verification_token': verificationToken,
  };
}

class ListVaultsRequest implements IRpcSerializable {
  const ListVaultsRequest();

  factory ListVaultsRequest.fromJson(Map<String, dynamic> _) =>
      const ListVaultsRequest();

  @override
  Map<String, dynamic> toJson() => const {};
}

class ListVaultsResponse implements IRpcSerializable {
  const ListVaultsResponse({required this.vaults});

  final List<VaultDto> vaults;

  factory ListVaultsResponse.fromJson(Map<String, dynamic> json) =>
      ListVaultsResponse(
        vaults: (json['vaults'] as List)
            .cast<Map<String, dynamic>>()
            .map(VaultDto.fromJson)
            .toList(),
      );

  @override
  Map<String, dynamic> toJson() => {
    'vaults': vaults.map((v) => v.toJson()).toList(),
  };
}

class CreateVaultRequest implements IRpcSerializable {
  const CreateVaultRequest({required this.vaultId, required this.vaultName});

  final String vaultId;
  final String vaultName;

  factory CreateVaultRequest.fromJson(Map<String, dynamic> json) =>
      CreateVaultRequest(
        vaultId: json['vault_id'] as String,
        vaultName: json['vault_name'] as String,
      );

  @override
  Map<String, dynamic> toJson() => {
    'vault_id': vaultId,
    'vault_name': vaultName,
  };
}

class CreateVaultResponse implements IRpcSerializable {
  const CreateVaultResponse();

  factory CreateVaultResponse.fromJson(Map<String, dynamic> _) =>
      const CreateVaultResponse();

  @override
  Map<String, dynamic> toJson() => const {};
}

class UpdateVerificationTokenRequest implements IRpcSerializable {
  const UpdateVerificationTokenRequest({
    required this.vaultId,
    required this.verificationToken,
  });

  final String vaultId;
  final String verificationToken;

  factory UpdateVerificationTokenRequest.fromJson(Map<String, dynamic> json) =>
      UpdateVerificationTokenRequest(
        vaultId: json['vault_id'] as String,
        verificationToken: json['verification_token'] as String,
      );

  @override
  Map<String, dynamic> toJson() => {
    'vault_id': vaultId,
    'verification_token': verificationToken,
  };
}

class UpdateVerificationTokenResponse implements IRpcSerializable {
  const UpdateVerificationTokenResponse();

  factory UpdateVerificationTokenResponse.fromJson(Map<String, dynamic> _) =>
      const UpdateVerificationTokenResponse();

  @override
  Map<String, dynamic> toJson() => const {};
}

// --- Contract ---

/// Vault management contract — JWT required.
@RpcService(name: 'RhyoliteVault', transferMode: RpcDataTransferMode.codec)
abstract class IVaultContract {
  @RpcMethod.unary(name: 'listVaults')
  Future<ListVaultsResponse> listVaults(
    ListVaultsRequest request, {
    RpcContext? context,
  });

  @RpcMethod.unary(name: 'createVault')
  Future<CreateVaultResponse> createVault(
    CreateVaultRequest request, {
    RpcContext? context,
  });

  @RpcMethod.unary(name: 'updateVerificationToken')
  Future<UpdateVerificationTokenResponse> updateVerificationToken(
    UpdateVerificationTokenRequest request, {
    RpcContext? context,
  });
}
