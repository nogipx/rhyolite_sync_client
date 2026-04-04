import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:uuid/uuid.dart';

class RecordDeleteUseCase {
  final IGraphEditable<NodeRecord> graph;

  const RecordDeleteUseCase(this.graph);

  DeleteRecord call(Node fileNode) {
    final fileRecord = graph.getNodeData(fileNode.key) as FileRecord;
    final leaf = graph.findLeaf(fileNode);
    final record = DeleteRecord(
      key: const Uuid().v5(Namespace.url.value, '${leaf.key}:delete'),
      vaultId: fileRecord.vaultId,
      parentKey: leaf.key,
      isSynced: false,
      createdAt: DateTime.now(),
      fileId: fileRecord.fileId,
    );
    final node = DeleteNode(record.key);
    graph.addNode(node);
    graph.addEdge(leaf, node);
    graph.updateNodeData(record.key, record);
    return record;
  }

}
