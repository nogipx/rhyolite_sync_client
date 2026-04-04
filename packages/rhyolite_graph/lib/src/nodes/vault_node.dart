import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

class VaultNode extends Node implements IRhyoliteNode {
  VaultNode(super.key);

  @override
  Map<String, dynamic> toJson() => {};

  @override
  String toString() => 'VaultNode($key)';
}
