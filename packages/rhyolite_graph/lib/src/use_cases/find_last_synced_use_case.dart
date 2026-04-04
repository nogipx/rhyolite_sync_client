import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

class FindLastSyncedUseCase {
  final IGraph<NodeRecord> graph;

  const FindLastSyncedUseCase(this.graph);

  Node? call(Node fileNode) {
    Node? current = graph.findLeaf(fileNode);
    while (current != null) {
      final record = graph.getNodeData(current.key);
      if (record != null && record.isSynced) return current;
      current = graph.getNodeParent(current);
    }
    return null;
  }

}