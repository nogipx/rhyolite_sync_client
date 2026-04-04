import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:uuid/uuid.dart';

class RecordMoveUseCase {
  final IGraphEditable<NodeRecord> graph;

  const RecordMoveUseCase(this.graph);

  MoveRecord call(Node fileNode, String fromPath, String toPath) {
    final fileRecord = graph.getNodeData(fileNode.key) as FileRecord;
    final leaf = graph.findLeaf(fileNode);
    final record = MoveRecord(
      key: const Uuid().v5(Namespace.url.value, '${leaf.key}:$toPath'),
      vaultId: fileRecord.vaultId,
      parentKey: leaf.key,
      isSynced: false,
      createdAt: DateTime.now(),
      fileId: fileRecord.fileId,
      fromPath: fromPath,
      toPath: toPath,
    );
    final node = MoveNode(record.key);
    graph.addNode(node);
    graph.addEdge(leaf, node);
    graph.updateNodeData(record.key, record);
    return record;
  }

}
