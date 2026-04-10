import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:uuid/uuid.dart';

class RecordDeleteUseCase {
  final IGraph<NodeRecord> graph;

  const RecordDeleteUseCase(this.graph);

  DeleteRecord call(Node fileNode) {
    final fileRecord = graph.getNodeData(fileNode.key) as FileRecord;
    final leaf = graph.findLeaf(fileNode);
    return DeleteRecord(
      key: const Uuid().v5(Namespace.url.value, '${leaf.key}:delete'),
      vaultId: fileRecord.vaultId,
      parentKey: leaf.key,
      isSynced: false,
      createdAt: DateTime.now(),
      fileId: fileRecord.fileId,
    );
  }
}
