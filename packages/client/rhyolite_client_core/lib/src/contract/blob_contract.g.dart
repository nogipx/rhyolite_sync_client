// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'blob_contract.dart';

// **************************************************************************
// RpcDartGenerator
// **************************************************************************

// ignore_for_file: type=lint, unused_element

class BlobContractNames {
  const BlobContractNames._();
  static const service = 'RhyoliteBlob';
  static String instance(String suffix) => '$service\_$suffix';
  static const upload = 'upload';
  static const download = 'download';
}

class BlobContractCodecs {
  const BlobContractCodecs._();
  static const codecBlobChunk = RpcCodec<BlobChunk>.withDecoder(
    BlobChunk.fromJson,
  );
  static const codecBulkDownloadBlobRequest =
      RpcCodec<BulkDownloadBlobRequest>.withDecoder(
        BulkDownloadBlobRequest.fromJson,
      );
  static const codecBulkUploadBlobResponse =
      RpcCodec<BulkUploadBlobResponse>.withDecoder(
        BulkUploadBlobResponse.fromJson,
      );
}

class BlobContractCaller extends RpcCallerContract implements IBlobContract {
  BlobContractCaller(
    RpcCallerEndpoint endpoint, {
    String? serviceNameOverride,
    RpcDataTransferMode dataTransferMode = RpcDataTransferMode.codec,
  }) : super(
         serviceNameOverride ?? BlobContractNames.service,
         endpoint,
         dataTransferMode: dataTransferMode,
       );

  @override
  Future<BulkUploadBlobResponse> upload(
    Stream<BlobChunk> requests, {
    RpcContext? context,
  }) {
    return callClientStream<BlobChunk, BulkUploadBlobResponse>(
      methodName: BlobContractNames.upload,
      requestCodec: BlobContractCodecs.codecBlobChunk,
      responseCodec: BlobContractCodecs.codecBulkUploadBlobResponse,
      requests: requests,
      context: context,
    );
  }

  @override
  Stream<BlobChunk> download(
    BulkDownloadBlobRequest request, {
    RpcContext? context,
  }) {
    return callServerStream<BulkDownloadBlobRequest, BlobChunk>(
      methodName: BlobContractNames.download,
      requestCodec: BlobContractCodecs.codecBulkDownloadBlobRequest,
      responseCodec: BlobContractCodecs.codecBlobChunk,
      request: request,
      context: context,
    );
  }
}

abstract class BlobContractResponder extends RpcResponderContract
    implements IBlobContract {
  BlobContractResponder({
    String? serviceNameOverride,
    RpcDataTransferMode dataTransferMode = RpcDataTransferMode.codec,
  }) : super(
         serviceNameOverride ?? BlobContractNames.service,
         dataTransferMode: dataTransferMode,
       );

  @override
  void setup() {
    addClientStreamMethod<BlobChunk, BulkUploadBlobResponse>(
      methodName: BlobContractNames.upload,
      handler: upload,
      requestCodec: BlobContractCodecs.codecBlobChunk,
      responseCodec: BlobContractCodecs.codecBulkUploadBlobResponse,
    );
    addServerStreamMethod<BulkDownloadBlobRequest, BlobChunk>(
      methodName: BlobContractNames.download,
      handler: download,
      requestCodec: BlobContractCodecs.codecBulkDownloadBlobRequest,
      responseCodec: BlobContractCodecs.codecBlobChunk,
    );
  }
}
