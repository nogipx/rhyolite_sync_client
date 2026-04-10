// ignore_for_file: uri_has_not_been_generated

import 'dart:async';

import 'package:rpc_dart/rpc_dart.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

part 'sync_contract.g.dart';

// --- DTOs ---

class PullRequest implements IRpcSerializable {
  const PullRequest({
    required this.vaultId,
    required this.cursors,
  });

  final String vaultId;
  final List<FileSyncCursor> cursors;

  factory PullRequest.fromJson(Map<String, dynamic> json) => PullRequest(
    vaultId: json['vaultId'] as String,
    cursors: (json['cursors'] as List)
        .map((e) => FileSyncCursor(
              fileId: e['fileId'] as String,
              lastSyncedKey: e['lastSyncedKey'] as String?,
            ))
        .toList(),
  );

  @override
  Map<String, dynamic> toJson() => {
    'vaultId': vaultId,
    'cursors': cursors
        .map((c) => {
              'fileId': c.fileId,
              if (c.lastSyncedKey != null) 'lastSyncedKey': c.lastSyncedKey,
            })
        .toList(),
  };
}

class PullResponse implements IRpcSerializable {
  const PullResponse({required this.results});

  final List<FilePullResult> results;

  factory PullResponse.fromJson(Map<String, dynamic> json) => PullResponse(
    results: (json['results'] as List)
        .map((e) => FilePullResult(
              fileId: e['fileId'] as String,
              nodes: (e['nodes'] as List)
                  .map((n) => NodeRecord.fromJson(Map<String, dynamic>.from(n as Map)))
                  .toList(),
            ))
        .toList(),
  );

  @override
  Map<String, dynamic> toJson() => {
    'results': results
        .map((r) => {
              'fileId': r.fileId,
              'nodes': r.nodes.map((n) => n.toJson()).toList(),
            })
        .toList(),
  };
}

class PushRequest implements IRpcSerializable {
  const PushRequest({required this.vaultId, required this.nodes});

  final String vaultId;
  final List<NodeRecord> nodes;

  factory PushRequest.fromJson(Map<String, dynamic> json) => PushRequest(
    vaultId: json['vaultId'] as String,
    nodes: (json['nodes'] as List)
        .map((e) => NodeRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );

  @override
  Map<String, dynamic> toJson() => {
    'vaultId': vaultId,
    'nodes': nodes.map((n) => n.toJson()).toList(),
  };
}

class PushResponse implements IRpcSerializable {
  const PushResponse();

  factory PushResponse.fromJson(Map<String, dynamic> _) => const PushResponse();

  @override
  Map<String, dynamic> toJson() => const {};
}

class AcquireLockRequest implements IRpcSerializable {
  const AcquireLockRequest({required this.vaultId});

  final String vaultId;

  factory AcquireLockRequest.fromJson(Map<String, dynamic> json) =>
      AcquireLockRequest(vaultId: json['vaultId'] as String);

  @override
  Map<String, dynamic> toJson() => {'vaultId': vaultId};
}

class AcquireLockResponse implements IRpcSerializable {
  const AcquireLockResponse({required this.lockToken});

  final String lockToken;

  factory AcquireLockResponse.fromJson(Map<String, dynamic> json) =>
      AcquireLockResponse(lockToken: json['lockToken'] as String);

  @override
  Map<String, dynamic> toJson() => {'lockToken': lockToken};
}

class ReleaseLockRequest implements IRpcSerializable {
  const ReleaseLockRequest({required this.vaultId, required this.lockToken});

  final String vaultId;
  final String lockToken;

  factory ReleaseLockRequest.fromJson(Map<String, dynamic> json) =>
      ReleaseLockRequest(
        vaultId: json['vaultId'] as String,
        lockToken: json['lockToken'] as String,
      );

  @override
  Map<String, dynamic> toJson() => {
    'vaultId': vaultId,
    'lockToken': lockToken,
  };
}

class ReleaseLockResponse implements IRpcSerializable {
  const ReleaseLockResponse();

  factory ReleaseLockResponse.fromJson(Map<String, dynamic> _) =>
      const ReleaseLockResponse();

  @override
  Map<String, dynamic> toJson() => const {};
}

class RenewLockRequest implements IRpcSerializable {
  const RenewLockRequest({required this.vaultId, required this.lockToken});

  final String vaultId;
  final String lockToken;

  factory RenewLockRequest.fromJson(Map<String, dynamic> json) =>
      RenewLockRequest(
        vaultId: json['vaultId'] as String,
        lockToken: json['lockToken'] as String,
      );

  @override
  Map<String, dynamic> toJson() => {
    'vaultId': vaultId,
    'lockToken': lockToken,
  };
}

class RenewLockResponse implements IRpcSerializable {
  const RenewLockResponse();

  factory RenewLockResponse.fromJson(Map<String, dynamic> _) =>
      const RenewLockResponse();

  @override
  Map<String, dynamic> toJson() => const {};
}

class GetVaultEpochRequest implements IRpcSerializable {
  const GetVaultEpochRequest({required this.vaultId});

  final String vaultId;

  factory GetVaultEpochRequest.fromJson(Map<String, dynamic> json) =>
      GetVaultEpochRequest(vaultId: json['vaultId'] as String);

  @override
  Map<String, dynamic> toJson() => {'vaultId': vaultId};
}

class GetVaultEpochResponse implements IRpcSerializable {
  const GetVaultEpochResponse({required this.epoch});

  final int epoch;

  factory GetVaultEpochResponse.fromJson(Map<String, dynamic> json) =>
      GetVaultEpochResponse(epoch: json['epoch'] as int);

  @override
  Map<String, dynamic> toJson() => {'epoch': epoch};
}

class ResetVaultRequest implements IRpcSerializable {
  const ResetVaultRequest({required this.vaultId});

  final String vaultId;

  factory ResetVaultRequest.fromJson(Map<String, dynamic> json) =>
      ResetVaultRequest(vaultId: json['vaultId'] as String);

  @override
  Map<String, dynamic> toJson() => {'vaultId': vaultId};
}

class ResetVaultResponse implements IRpcSerializable {
  const ResetVaultResponse();

  factory ResetVaultResponse.fromJson(Map<String, dynamic> _) =>
      const ResetVaultResponse();

  @override
  Map<String, dynamic> toJson() => const {};
}

class DeleteNodesRequest implements IRpcSerializable {
  const DeleteNodesRequest({required this.vaultId, required this.keys});

  final String vaultId;
  final List<String> keys;

  factory DeleteNodesRequest.fromJson(Map<String, dynamic> json) =>
      DeleteNodesRequest(
        vaultId: json['vaultId'] as String,
        keys: List<String>.from(json['keys'] as List),
      );

  @override
  Map<String, dynamic> toJson() => {'vaultId': vaultId, 'keys': keys};
}

class DeleteNodesResponse implements IRpcSerializable {
  const DeleteNodesResponse();

  factory DeleteNodesResponse.fromJson(Map<String, dynamic> _) =>
      const DeleteNodesResponse();

  @override
  Map<String, dynamic> toJson() => const {};
}

// --- Contract ---

@RpcService(name: 'RhyoliteSync', transferMode: RpcDataTransferMode.codec)
abstract class ISyncContract {
  @RpcMethod.unary(name: 'pull')
  Future<PullResponse> pull(PullRequest request, {RpcContext? context});

  @RpcMethod.unary(name: 'push')
  Future<PushResponse> push(PushRequest request, {RpcContext? context});

  @RpcMethod.unary(name: 'acquireLock')
  Future<AcquireLockResponse> acquireLock(
    AcquireLockRequest request, {
    RpcContext? context,
  });

  @RpcMethod.unary(name: 'releaseLock')
  Future<ReleaseLockResponse> releaseLock(
    ReleaseLockRequest request, {
    RpcContext? context,
  });

  @RpcMethod.unary(name: 'renewLock')
  Future<RenewLockResponse> renewLock(
    RenewLockRequest request, {
    RpcContext? context,
  });

  @RpcMethod.unary(name: 'getVaultEpoch')
  Future<GetVaultEpochResponse> getVaultEpoch(
    GetVaultEpochRequest request, {
    RpcContext? context,
  });

  @RpcMethod.unary(name: 'resetVault')
  Future<ResetVaultResponse> resetVault(
    ResetVaultRequest request, {
    RpcContext? context,
  });

  @RpcMethod.unary(name: 'deleteNodes')
  Future<DeleteNodesResponse> deleteNodes(
    DeleteNodesRequest request, {
    RpcContext? context,
  });
}
