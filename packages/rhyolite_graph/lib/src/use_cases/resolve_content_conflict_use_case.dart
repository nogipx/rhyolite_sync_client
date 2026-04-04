import 'package:rhyolite_graph/rhyolite_graph.dart';

class ResolveContentConflictUseCase {
  final IBlobStorage blobStorage;
  final IContentMerger merger;

  const ResolveContentConflictUseCase({
    required this.blobStorage,
    required this.merger,
  });

  Future<ResolveResult> call(
    ChangeRecord local,
    ChangeRecord remote,
    ChangeRecord base,
    ResolveStrategy strategy,
  ) async {
    final blobs = await blobStorage.download([base.blobId, local.blobId, remote.blobId]);
    final baseBlob = blobs[base.blobId]!;
    final localBlob = blobs[local.blobId]!;
    final remoteBlob = blobs[remote.blobId]!;

    final merged = merger.tryMerge(baseBlob, localBlob, remoteBlob);
    if (merged != null) return MergedContent(merged);

    return switch (strategy) {
      ResolveStrategy.lww =>
        local.createdAt.isAfter(remote.createdAt) ? const AcceptLocal() : const AcceptRemote(),
      ResolveStrategy.conflictCopy => const AcceptBoth(),
    };
  }
}