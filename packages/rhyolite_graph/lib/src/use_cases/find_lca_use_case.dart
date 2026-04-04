import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

class FindLcaUseCase {
  final IGraph<NodeRecord> graph;

  const FindLcaUseCase(this.graph);

  Node? call(Node a, Node b) {
    final pathA = graph.getPathToNode(a);
    final pathB = graph.getPathToNode(b);
    final common = pathA.intersection(pathB);

    if (common.isEmpty) return null;

    return common.reduce(
      (best, node) =>
          graph.getNodeLevel(node) > graph.getNodeLevel(best) ? node : best,
    );
  }
}
