import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:uuid/uuid.dart';

class RecordChangeUseCase {
  final IGraphEditable<NodeRecord> graph;

  const RecordChangeUseCase(this.graph);

  ChangeRecord call(Node fileNode, String blobId, int sizeBytes) {
    final fileRecord = graph.getNodeData(fileNode.key) as FileRecord;
    final leaf = graph.findLeaf(fileNode);
    final record = ChangeRecord(
      key: const Uuid().v5(Namespace.url.value, '${leaf.key}:$blobId'),
      vaultId: fileRecord.vaultId,
      parentKey: leaf.key,
      isSynced: false,
      createdAt: DateTime.now(),
      fileId: fileRecord.fileId,
      blobId: blobId,
      sizeBytes: sizeBytes,
    );
    if (graph.getNodeByKey(record.key) != null) {
      return graph.getNodeData(record.key) as ChangeRecord;
    }
    final node = ChangeNode(record.key);
    graph.addNode(node);
    graph.addEdge(leaf, node);
    graph.updateNodeData(record.key, record);
    return record;
  }

}
