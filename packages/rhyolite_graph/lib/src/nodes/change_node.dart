import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

class ChangeNode extends Node implements IRhyoliteNode {
  ChangeNode(super.key);

  @override
  Map<String, dynamic> toJson() => {};

  @override
  String toString() => 'ChangeNode($key)';
}
