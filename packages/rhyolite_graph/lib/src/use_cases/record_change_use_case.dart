import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:uuid/uuid.dart';

class RecordChangeUseCase {
  final IGraph<NodeRecord> graph;

  const RecordChangeUseCase(this.graph);

  ChangeRecord call(Node fileNode, String blobId, int sizeBytes) {
    final fileRecord = graph.getNodeData(fileNode.key) as FileRecord;
    final leaf = graph.findLeaf(fileNode);
    final key = const Uuid().v5(Namespace.url.value, '${leaf.key}:$blobId');
    if (graph.getNodeByKey(key) != null) {
      return graph.getNodeData(key) as ChangeRecord;
    }
    return ChangeRecord(
      key: key,
      vaultId: fileRecord.vaultId,
      parentKey: leaf.key,
      isSynced: false,
      createdAt: DateTime.now(),
      fileId: fileRecord.fileId,
      blobId: blobId,
      sizeBytes: sizeBytes,
    );
  }
}
