import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

class ApplyRemoteNodesUseCase {
  final IGraphEditable<NodeRecord> graph;

  const ApplyRemoteNodesUseCase(this.graph);

  void call(List<NodeRecord> remoteNodes) {
    final sorted = [...remoteNodes]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (final record in sorted) {
      if (graph.containsNode(record.key)) continue;

      final node = _nodeFromRecord(record);
      graph.addNode(node);
      graph.updateNodeData(record.key, record);

      if (record.parentKey != null) {
        final parent = graph.getNodeByKey(record.parentKey!);
        if (parent == null) {
          throw StateError('Parent node not found for key: ${record.parentKey}');
        }
        graph.addEdge(parent, node);
      }
    }
  }

  Node _nodeFromRecord(NodeRecord record) => switch (record) {
        VaultRecord() => VaultNode(record.key),
        FileRecord() => FileNode(record.key),
        ChangeRecord() => ChangeNode(record.key),
        MoveRecord() => MoveNode(record.key),
        DeleteRecord() => DeleteNode(record.key),
      };
}