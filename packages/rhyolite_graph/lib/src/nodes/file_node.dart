import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

class FileNode extends Node implements IRhyoliteNode {
  FileNode(super.key);

  @override
  Map<String, dynamic> toJson() => {};

  @override
  String toString() => 'FileNode($key)';
}
