// ignore_for_file: uri_has_not_been_generated

import 'dart:async';

import 'package:rpc_dart/rpc_dart.dart';

part 'blob_contract.g.dart';

// --- DTOs ---

class BlobChunk implements IRpcSerializable {
  const BlobChunk({
    required this.bytes,
    required this.offset,
    required this.last,
    this.blobId,
    this.vaultId,
  });

  final Uint8List bytes;
  final int offset;
  final bool last;

  /// Only set in the first chunk of an upload.
  final String? blobId;

  /// Only set in the first chunk of an upload.
  final String? vaultId;

  factory BlobChunk.fromJson(Map<String, dynamic> json) => BlobChunk(
    bytes: Uint8List.fromList((json['bytes'] as List).cast<int>()),
    offset: json['offset'] as int,
    last: json['last'] as bool,
    blobId: json['blobId'] as String?,
    vaultId: json['vaultId'] as String?,
  );

  @override
  Map<String, dynamic> toJson() => {
    'bytes': bytes,
    'offset': offset,
    'last': last,
    if (blobId != null) 'blobId': blobId,
    if (vaultId != null) 'vaultId': vaultId,
  };
}

class BulkUploadBlobResponse implements IRpcSerializable {
  const BulkUploadBlobResponse({required this.blobIds});

  final List<String> blobIds;

  factory BulkUploadBlobResponse.fromJson(Map<String, dynamic> json) =>
      BulkUploadBlobResponse(
        blobIds: List<String>.from(json['blobIds'] as List? ?? const []),
      );

  @override
  Map<String, dynamic> toJson() => {'blobIds': blobIds};
}

class BulkDownloadBlobRequest implements IRpcSerializable {
  const BulkDownloadBlobRequest({required this.vaultId, required this.blobIds});

  final String vaultId;
  final List<String> blobIds;

  factory BulkDownloadBlobRequest.fromJson(Map<String, dynamic> json) =>
      BulkDownloadBlobRequest(
        vaultId: json['vaultId'] as String,
        blobIds: List<String>.from(json['blobIds'] as List? ?? const []),
      );

  @override
  Map<String, dynamic> toJson() => {'vaultId': vaultId, 'blobIds': blobIds};
}

// --- Contract ---

@RpcService(name: 'RhyoliteBlob', transferMode: RpcDataTransferMode.codec)
abstract class IBlobContract {
  @RpcMethod(name: 'upload', kind: RpcMethodKind.clientStream)
  Future<BulkUploadBlobResponse> upload(
    Stream<BlobChunk> chunks, {
    RpcContext? context,
  });

  @RpcMethod(name: 'download', kind: RpcMethodKind.serverStream)
  Stream<BlobChunk> download(
    BulkDownloadBlobRequest request, {
    RpcContext? context,
  });
}
