import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

/// Detaches all side branches along the canonical path from the winning leaf
/// back to [fileNode].
///
/// At each node on the path, any children that are not the next step toward
/// the leaf are removed via [IGraphEditable.removeEdge], making them orphans
/// for [GraphGCUseCase] to clean up.
///
/// Call this after recording a local change, not after a pull.
class PruneLeafBranchesUseCase {
  const PruneLeafBranchesUseCase(this.graph);

  final IGraphEditable<NodeRecord> graph;

  /// Returns orphaned root records (with parentKey set to null) for each
  /// detached branch, so the caller can push them to the server.
  List<NodeRecord> call(Node fileNode) {
    final leaf = graph.findLeaf(fileNode);

    // Build canonical path: leaf → fileNode.
    final canonicalPath = graph.getFullVerticalPath(leaf);

    final orphanedRoots = <NodeRecord>[];

    // Walk from fileNode down the canonical path, pruning siblings at each step.
    var current = fileNode;
    while (current.key != leaf.key) {
      final children = graph.getNodeEdges(current);
      Node? next;
      for (final child in children) {
        if (canonicalPath.contains(child)) {
          next = child;
        } else {
          graph.removeEdge(current, child);
          final record = graph.getNodeData(child.key);
          if (record != null) orphanedRoots.add(record.withOrphaned());
        }
      }
      if (next == null) break;
      current = next;
    }

    return orphanedRoots;
  }
}
