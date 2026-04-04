import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

extension GraphExtensions on IGraph<NodeRecord> {
  Node findLeaf(Node start) {
    var current = start;
    while (true) {
      final children = getNodeEdges(current);
      if (children.isEmpty) return current;
      if (children.length == 1) {
        current = children.first;
      } else {
        // Fork: pick the child whose subtree leaf has the latest createdAt.
        Node? best;
        DateTime? bestTime;
        for (final child in children) {
          final leaf = findLeaf(child);
          final record = getNodeData(leaf.key);
          final t = record?.createdAt;
          if (t != null && (bestTime == null || t.isAfter(bestTime))) {
            bestTime = t;
            best = child;
          }
        }
        current = best ?? children.first;
      }
    }
  }
}
