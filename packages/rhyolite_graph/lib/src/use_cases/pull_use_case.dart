import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

class PullUseCase {
  final IGraphEditable<NodeRecord> graph;
  final IGraphServer server;

  const PullUseCase({required this.graph, required this.server});

  Future<List<FilePullResult>> call(
    List<Node> fileNodes, {
    int batchSize = 50,
  }) async {
    final result = <FilePullResult>[];

    for (var i = 0; i < fileNodes.length; i += batchSize) {
      final batch = fileNodes.skip(i).take(batchSize).toList();

      final cursors = batch.map((fileNode) {
        final fileRecord = graph.getNodeData(fileNode.key);
        if (fileRecord is! FileRecord) {
          throw StateError('Expected FileRecord for node: ${fileNode.key}');
        }
        final lastSynced = FindLastSyncedUseCase(graph)(fileNode);
        return FileSyncCursor(
          fileId: fileRecord.fileId,
          lastSyncedKey: lastSynced?.key,
        );
      }).toList();

      final batchResults = await server.pull(cursors);

      for (final filePullResult in batchResults) {
        if (filePullResult.nodes.isNotEmpty) {
          ApplyRemoteNodesUseCase(graph)(filePullResult.nodes);
          result.add(filePullResult);
        }
      }
    }

    return result;
  }
}
