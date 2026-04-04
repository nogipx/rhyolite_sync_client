import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

class DeleteNode extends Node implements IRhyoliteNode {
  DeleteNode(super.key);

  @override
  Map<String, dynamic> toJson() => {};

  @override
  String toString() => 'DeleteNode($key)';
}
