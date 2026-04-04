// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_contract.dart';

// **************************************************************************
// RpcDartGenerator
// **************************************************************************

// ignore_for_file: type=lint, unused_element

class SyncContractNames {
  const SyncContractNames._();
  static const service = 'RhyoliteSync';
  static String instance(String suffix) => '$service\_$suffix';
  static const pull = 'pull';
  static const push = 'push';
  static const acquireLock = 'acquireLock';
  static const releaseLock = 'releaseLock';
  static const getVaultEpoch = 'getVaultEpoch';
  static const resetVault = 'resetVault';
}

class SyncContractCodecs {
  const SyncContractCodecs._();
  static const codecAcquireLockRequest =
      RpcCodec<AcquireLockRequest>.withDecoder(AcquireLockRequest.fromJson);
  static const codecAcquireLockResponse =
      RpcCodec<AcquireLockResponse>.withDecoder(AcquireLockResponse.fromJson);
  static const codecGetVaultEpochRequest =
      RpcCodec<GetVaultEpochRequest>.withDecoder(GetVaultEpochRequest.fromJson);
  static const codecGetVaultEpochResponse =
      RpcCodec<GetVaultEpochResponse>.withDecoder(
        GetVaultEpochResponse.fromJson,
      );
  static const codecPullRequest = RpcCodec<PullRequest>.withDecoder(
    PullRequest.fromJson,
  );
  static const codecPullResponse = RpcCodec<PullResponse>.withDecoder(
    PullResponse.fromJson,
  );
  static const codecPushRequest = RpcCodec<PushRequest>.withDecoder(
    PushRequest.fromJson,
  );
  static const codecPushResponse = RpcCodec<PushResponse>.withDecoder(
    PushResponse.fromJson,
  );
  static const codecReleaseLockRequest =
      RpcCodec<ReleaseLockRequest>.withDecoder(ReleaseLockRequest.fromJson);
  static const codecReleaseLockResponse =
      RpcCodec<ReleaseLockResponse>.withDecoder(ReleaseLockResponse.fromJson);
  static const codecResetVaultRequest = RpcCodec<ResetVaultRequest>.withDecoder(
    ResetVaultRequest.fromJson,
  );
  static const codecResetVaultResponse =
      RpcCodec<ResetVaultResponse>.withDecoder(ResetVaultResponse.fromJson);
}

class SyncContractCaller extends RpcCallerContract implements ISyncContract {
  SyncContractCaller(
    RpcCallerEndpoint endpoint, {
    String? serviceNameOverride,
    RpcDataTransferMode dataTransferMode = RpcDataTransferMode.codec,
  }) : super(
         serviceNameOverride ?? SyncContractNames.service,
         endpoint,
         dataTransferMode: dataTransferMode,
       );

  @override
  Future<PullResponse> pull(PullRequest request, {RpcContext? context}) {
    return callUnary<PullRequest, PullResponse>(
      methodName: SyncContractNames.pull,
      requestCodec: SyncContractCodecs.codecPullRequest,
      responseCodec: SyncContractCodecs.codecPullResponse,
      request: request,
      context: context,
    );
  }

  @override
  Future<PushResponse> push(PushRequest request, {RpcContext? context}) {
    return callUnary<PushRequest, PushResponse>(
      methodName: SyncContractNames.push,
      requestCodec: SyncContractCodecs.codecPushRequest,
      responseCodec: SyncContractCodecs.codecPushResponse,
      request: request,
      context: context,
    );
  }

  @override
  Future<AcquireLockResponse> acquireLock(
    AcquireLockRequest request, {
    RpcContext? context,
  }) {
    return callUnary<AcquireLockRequest, AcquireLockResponse>(
      methodName: SyncContractNames.acquireLock,
      requestCodec: SyncContractCodecs.codecAcquireLockRequest,
      responseCodec: SyncContractCodecs.codecAcquireLockResponse,
      request: request,
      context: context,
    );
  }

  @override
  Future<ReleaseLockResponse> releaseLock(
    ReleaseLockRequest request, {
    RpcContext? context,
  }) {
    return callUnary<ReleaseLockRequest, ReleaseLockResponse>(
      methodName: SyncContractNames.releaseLock,
      requestCodec: SyncContractCodecs.codecReleaseLockRequest,
      responseCodec: SyncContractCodecs.codecReleaseLockResponse,
      request: request,
      context: context,
    );
  }

  @override
  Future<GetVaultEpochResponse> getVaultEpoch(
    GetVaultEpochRequest request, {
    RpcContext? context,
  }) {
    return callUnary<GetVaultEpochRequest, GetVaultEpochResponse>(
      methodName: SyncContractNames.getVaultEpoch,
      requestCodec: SyncContractCodecs.codecGetVaultEpochRequest,
      responseCodec: SyncContractCodecs.codecGetVaultEpochResponse,
      request: request,
      context: context,
    );
  }

  @override
  Future<ResetVaultResponse> resetVault(
    ResetVaultRequest request, {
    RpcContext? context,
  }) {
    return callUnary<ResetVaultRequest, ResetVaultResponse>(
      methodName: SyncContractNames.resetVault,
      requestCodec: SyncContractCodecs.codecResetVaultRequest,
      responseCodec: SyncContractCodecs.codecResetVaultResponse,
      request: request,
      context: context,
    );
  }
}

abstract class SyncContractResponder extends RpcResponderContract
    implements ISyncContract {
  SyncContractResponder({
    String? serviceNameOverride,
    RpcDataTransferMode dataTransferMode = RpcDataTransferMode.codec,
  }) : super(
         serviceNameOverride ?? SyncContractNames.service,
         dataTransferMode: dataTransferMode,
       );

  @override
  void setup() {
    addUnaryMethod<PullRequest, PullResponse>(
      methodName: SyncContractNames.pull,
      handler: pull,
      requestCodec: SyncContractCodecs.codecPullRequest,
      responseCodec: SyncContractCodecs.codecPullResponse,
    );
    addUnaryMethod<PushRequest, PushResponse>(
      methodName: SyncContractNames.push,
      handler: push,
      requestCodec: SyncContractCodecs.codecPushRequest,
      responseCodec: SyncContractCodecs.codecPushResponse,
    );
    addUnaryMethod<AcquireLockRequest, AcquireLockResponse>(
      methodName: SyncContractNames.acquireLock,
      handler: acquireLock,
      requestCodec: SyncContractCodecs.codecAcquireLockRequest,
      responseCodec: SyncContractCodecs.codecAcquireLockResponse,
    );
    addUnaryMethod<ReleaseLockRequest, ReleaseLockResponse>(
      methodName: SyncContractNames.releaseLock,
      handler: releaseLock,
      requestCodec: SyncContractCodecs.codecReleaseLockRequest,
      responseCodec: SyncContractCodecs.codecReleaseLockResponse,
    );
    addUnaryMethod<GetVaultEpochRequest, GetVaultEpochResponse>(
      methodName: SyncContractNames.getVaultEpoch,
      handler: getVaultEpoch,
      requestCodec: SyncContractCodecs.codecGetVaultEpochRequest,
      responseCodec: SyncContractCodecs.codecGetVaultEpochResponse,
    );
    addUnaryMethod<ResetVaultRequest, ResetVaultResponse>(
      methodName: SyncContractNames.resetVault,
      handler: resetVault,
      requestCodec: SyncContractCodecs.codecResetVaultRequest,
      responseCodec: SyncContractCodecs.codecResetVaultResponse,
    );
  }
}
