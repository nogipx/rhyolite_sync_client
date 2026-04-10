import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

class GCResult {
  const GCResult({
    required this.removedNodeKeys,
    required this.removedBlobIds,
    required this.removedNodes,
  });

  final List<String> removedNodeKeys;
  final List<String> removedBlobIds;
  final List<Node> removedNodes;

  bool get isEmpty => removedNodeKeys.isEmpty && removedBlobIds.isEmpty;

  void apply(IGraphEditable<NodeRecord> graph) {
    for (final node in removedNodes) {
      graph.removeNode(node);
    }
  }
}

/// Removes orphaned nodes from the graph.
///
/// A node is orphaned if it has no parent edge in the graph
/// (i.e. absent from [IGraphData.parents]) and is not a legitimate
/// root ([VaultRecord] or [FileRecord]).
///
/// Orphaned subtrees appear after [IGraphEditable.removeEdge] is called
/// on a losing conflict branch. This use case collects every such node
/// together with its entire downstream subtree and removes them.
class GraphGCUseCase {
  const GraphGCUseCase(this.graph);

  final IGraph<NodeRecord> graph;

  GCResult call() {
    // Nodes that have a parent edge registered.
    final nodesWithParent = graph.parents.keys.map((n) => n.key).toSet();

    // Orphan roots: nodes without a parent edge that are not legitimate roots.
    final orphanRoots = graph.nodes.values.where((n) {
      if (nodesWithParent.contains(n.key)) return false;
      final record = graph.getNodeData(n.key);
      return record is! VaultRecord && record is! FileRecord;
    }).toList();

    if (orphanRoots.isEmpty) {
      return const GCResult(
        removedNodeKeys: [],
        removedBlobIds: [],
        removedNodes: [],
      );
    }

    final removedKeys = <String>[];
    final removedBlobIds = <String>[];
    final removedNodes = <Node>[];

    for (final orphanRoot in orphanRoots) {
      // BFS to collect the orphan root and its entire subtree.
      final queue = [orphanRoot];
      while (queue.isNotEmpty) {
        final node = queue.removeLast();
        queue.addAll(graph.getNodeEdges(node));
        final record = graph.getNodeData(node.key);
        if (record is ChangeRecord) removedBlobIds.add(record.blobId);
        removedNodes.add(node);
        removedKeys.add(node.key);
      }
    }

    return GCResult(
      removedNodeKeys: removedKeys,
      removedBlobIds: removedBlobIds,
      removedNodes: removedNodes,
    );
  }
}
