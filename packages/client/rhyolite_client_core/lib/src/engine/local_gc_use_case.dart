import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

import '../local/local_blob_store.dart';
import '../local/local_node_store.dart';
import 'file_registry.dart';

class LocalGCUseCase {
  const LocalGCUseCase({
    required this.graph,
    required this.fileRegistry,
    required this.nodeStore,
    required this.blobStore,
    required this.vaultId,
  });

  final IGraphEditable<NodeRecord> graph;
  final FileRegistry fileRegistry;
  final LocalNodeStore nodeStore;
  final LocalBlobStore blobStore;
  final String vaultId;

  Future<void> call() async {
    final allFileNodeKeys = fileRegistry.fileIdToNodeKey.values.toList();

    for (final nodeKey in allFileNodeKeys) {
      final fileNode = graph.getNodeByKey(nodeKey);
      if (fileNode == null) continue;

      final result = GraphGCUseCase(graph).call(fileNode);
      if (result.isEmpty) continue;

      await nodeStore.deleteKeys(result.removedNodeKeys, vaultId: vaultId);
      await blobStore.deleteBlobs(result.removedBlobIds, vaultId: vaultId);
    }
  }
}
