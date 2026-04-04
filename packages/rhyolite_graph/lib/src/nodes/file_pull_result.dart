import 'node_record.dart';

class FilePullResult {
  const FilePullResult({
    required this.fileId,
    required this.nodes,
  });

  final String fileId;
  final List<NodeRecord> nodes;
}
