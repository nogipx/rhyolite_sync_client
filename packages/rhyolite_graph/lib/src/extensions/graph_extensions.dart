import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

extension GraphEditableExtensions on IGraphEditable<NodeRecord> {
  /// Adds [records] to the graph, skipping already-existing nodes.
  /// Uses two passes: first add all nodes, then wire edges.
  /// For newly added nodes, throws if the parent is missing.
  /// For nodes that already exist and already have a parent, leaves them alone.
  void apply(List<NodeRecord> records) {
    final insertedKeys = <String>{};
    for (final record in records) {
      if (containsNode(record.key)) continue;
      addNode(_nodeFromRecord(record));
      updateNodeData(record.key, record);
      insertedKeys.add(record.key);
    }
    for (final record in records) {
      if (record.parentKey == null) continue;
      final node = getNodeByKey(record.key);
      final parent = getNodeByKey(record.parentKey!);
      if (node == null) continue;
      if (getNodeParent(node) != null) continue;
      if (parent == null) {
        if (insertedKeys.contains(record.key)) {
          throw StateError(
            'Parent "${record.parentKey}" not found for node "${record.key}"',
          );
        }
        continue;
      }
      addEdge(parent, node);
    }
  }

  /// Updates [isSynced] to true for each record whose key already exists in the graph.
  /// Skips records whose key is not found.
  void markSynced(List<NodeRecord> records) {
    for (final record in records) {
      if (containsNode(record.key)) {
        updateNodeData(record.key, record.withSynced());
      }
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

extension GraphExtensions on IGraph<NodeRecord> {
  Node findLeaf(Node start) {
    final stack = [start];
    Node? bestLeaf;
    int? bestMs;

    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      final children = getNodeEdges(current);
      if (children.isEmpty) {
        final record = getNodeData(current.key);
        if (record != null) {
          final ms = record.serverTimestampMs ??
              record.createdAt.millisecondsSinceEpoch;
          if (bestMs == null || ms > bestMs) {
            bestMs = ms;
            bestLeaf = current;
          }
        }
      } else {
        stack.addAll(children);
      }
    }

    return bestLeaf ?? start;
  }
}
