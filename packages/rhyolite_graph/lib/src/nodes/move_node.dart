import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

class MoveNode extends Node implements IRhyoliteNode {
  MoveNode(super.key);

  @override
  Map<String, dynamic> toJson() => {};

  @override
  String toString() => 'MoveNode($key)';
}
