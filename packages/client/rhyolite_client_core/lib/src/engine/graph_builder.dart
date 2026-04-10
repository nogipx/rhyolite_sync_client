import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

class GraphBuilder {
  const GraphBuilder();

  Graph<NodeRecord>? call(List<NodeRecord> records) {
    final vaultRecord = records.whereType<VaultRecord>().firstOrNull;
    if (vaultRecord == null) return null;

    final vaultNode = VaultNode(vaultRecord.key);
    final graph = Graph<NodeRecord>(root: vaultNode);
    graph.updateNodeData(vaultRecord.key, vaultRecord);

    final rest = records.where((r) => r is! VaultRecord).toList();

    for (final record in rest) {
      final node = _nodeFromRecord(record);
      graph.addNode(node);
      graph.updateNodeData(record.key, record);
    }

    for (final record in rest) {
      if (record.parentKey != null) {
        final parent = graph.getNodeByKey(record.parentKey!);
        if (parent != null) {
          final node = _nodeFromRecord(record);
          graph.addEdge(parent, node);
        }
      }
    }

    return graph;
  }

  Node _nodeFromRecord(NodeRecord record) => switch (record) {
    VaultRecord() => VaultNode(record.key),
    FileRecord() => FileNode(record.key),
    ChangeRecord() => ChangeNode(record.key),
    MoveRecord() => MoveNode(record.key),
    DeleteRecord() => DeleteNode(record.key),
  };
}
