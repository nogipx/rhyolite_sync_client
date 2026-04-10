import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

import '../local/local_blob_store.dart';
import '../local/local_node_store.dart';

class LocalGCUseCase {
  const LocalGCUseCase({
    required this.graph,
    required this.nodeStore,
    required this.blobStore,
    required this.vaultId,
  });

  final IGraphEditable<NodeRecord> graph;
  final LocalNodeStore nodeStore;
  final LocalBlobStore blobStore;
  final String vaultId;

  Future<void> call() async {
    final result = GraphGCUseCase(graph).call();
    if (result.isEmpty) return;

    result.apply(graph);
    await nodeStore.deleteKeys(result.removedNodeKeys, vaultId: vaultId);
    await blobStore.deleteBlobs(result.removedBlobIds, vaultId: vaultId);
  }
}
