import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

class GCResult {
  const GCResult({required this.removedNodeKeys, required this.removedBlobIds});

  final List<String> removedNodeKeys;
  final List<String> removedBlobIds;

  bool get isEmpty => removedNodeKeys.isEmpty && removedBlobIds.isEmpty;
}

/// Collects dead branches and orphaned nodes for a single file subtree.
///
/// A node is dead if:
/// - it is not reachable from any leaf walking up to [fileNode], OR
/// - its parent does not exist in the graph (orphaned).
///
/// Only runs when the file has a single leaf that is synced,
/// meaning all forks have been resolved and the state is stable.
class GraphGCUseCase {
  const GraphGCUseCase(this.graph);

  final IGraphEditable<NodeRecord> graph;

  GCResult call(Node fileNode) {
    // Collect all nodes in this file's subtree.
    final subtreeNodes = _collectSubtree(fileNode);

    // Find all leaves in the subtree (nodes with no children).
    final leaves = subtreeNodes
        .where((n) => graph.getNodeEdges(n).isEmpty)
        .toList();

    // Only GC when there is exactly one leaf and it is synced.
    if (leaves.length != 1) return const GCResult(removedNodeKeys: [], removedBlobIds: []);
    final leaf = leaves.first;
    final leafRecord = graph.getNodeData(leaf.key);
    if (leafRecord == null || !leafRecord.isSynced) {
      return const GCResult(removedNodeKeys: [], removedBlobIds: []);
    }

    // Build canonical path: leaf → fileNode.
    final canonicalKeys = <String>{};
    Node? cur = leaf;
    while (cur != null && cur.key != fileNode.key) {
      canonicalKeys.add(cur.key);
      cur = graph.getNodeParent(cur);
    }
    canonicalKeys.add(fileNode.key);

    // Dead = in subtree but not on canonical path, or orphaned.
    final deadNodes = subtreeNodes.where((n) {
      if (canonicalKeys.contains(n.key)) return false;
      // Also dead if parent missing.
      final record = graph.getNodeData(n.key);
      if (record?.parentKey != null &&
          graph.getNodeByKey(record!.parentKey!) == null) {
        return true;
      }
      return true;
    }).toList();

    if (deadNodes.isEmpty) return const GCResult(removedNodeKeys: [], removedBlobIds: []);

    final removedKeys = <String>[];
    final removedBlobIds = <String>[];

    for (final node in deadNodes) {
      final record = graph.getNodeData(node.key);
      if (record is ChangeRecord) removedBlobIds.add(record.blobId);
      graph.removeNode(node);
      removedKeys.add(node.key);
    }

    return GCResult(removedNodeKeys: removedKeys, removedBlobIds: removedBlobIds);
  }

  List<Node> _collectSubtree(Node root) {
    final result = <Node>[];
    final queue = [root];
    while (queue.isNotEmpty) {
      final node = queue.removeAt(0);
      result.add(node);
      queue.addAll(graph.getNodeEdges(node));
    }
    return result;
  }
}
