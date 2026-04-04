import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

class PushUseCase {
  final IGraphEditable<NodeRecord> graph;
  final IGraphServer server;
  final IBlobStorage localBlobs;
  final IBlobStorage remoteBlobs;

  const PushUseCase({
    required this.graph,
    required this.server,
    required this.localBlobs,
    required this.remoteBlobs,
  });

  Future<void> call(List<Node> fileNodes, {int batchSize = 10}) async {
    for (var i = 0; i < fileNodes.length; i += batchSize) {
      final batch = fileNodes.skip(i).take(batchSize).toList();

      final unsyncedNodes = batch
          .expand((fileNode) => GetUnsyncedNodesUseCase(graph)(fileNode))
          .toList();

      if (unsyncedNodes.isEmpty) continue;

      final blobIds = unsyncedNodes
          .whereType<ChangeRecord>()
          .map((r) => r.blobId)
          .toList();
      if (blobIds.isNotEmpty) {
        final localBlobMap = await localBlobs.download(blobIds);
        final blobsToUpload = blobIds
            .map((id) => (localBlobMap[id]!, id))
            .toList();
        await remoteBlobs.upload(blobsToUpload);
      }

      await server.push(unsyncedNodes);

      for (final record in unsyncedNodes) {
        graph.updateNodeData(record.key, record.withSynced());
      }
    }
  }
}
