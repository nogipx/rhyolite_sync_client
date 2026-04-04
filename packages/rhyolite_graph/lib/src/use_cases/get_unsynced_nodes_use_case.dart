import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

class GetUnsyncedNodesUseCase {
  final IGraph<NodeRecord> graph;

  const GetUnsyncedNodesUseCase(this.graph);

  List<NodeRecord> call(Node fileNode) {
    final result = <NodeRecord>[];
    Node? current = graph.findLeaf(fileNode);

    while (current != null) {
      final record = graph.getNodeData(current.key);
      if (record == null || record.isSynced) break;
      if (record is VaultRecord) break;
      result.add(record);
      current = graph.getNodeParent(current);
    }

    return result.reversed.toList();
  }

}