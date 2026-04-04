import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

class FileRegistry {
  final Map<String, String> _pathToFileId = {};
  final Map<String, String> _fileIdToNodeKey = {};
  final Map<String, String> _fileIdToPath = {};

  Map<String, String> get pathToFileId => Map.unmodifiable(_pathToFileId);
  Map<String, String> get fileIdToNodeKey => Map.unmodifiable(_fileIdToNodeKey);
  Map<String, String> get fileIdToPath => Map.unmodifiable(_fileIdToPath);

  String? fileIdByPath(String relativePath) => _pathToFileId[relativePath];
  String? nodeKeyByFileId(String fileId) => _fileIdToNodeKey[fileId];
  String? pathByFileId(String fileId) => _fileIdToPath[fileId];

  void register(String relativePath, String fileId, String nodeKey) {
    _pathToFileId[relativePath] = fileId;
    _fileIdToNodeKey[fileId] = nodeKey;
    _fileIdToPath[fileId] = relativePath;
  }

  void updatePath(String fromPath, String toPath) {
    final fileId = _pathToFileId.remove(fromPath);
    if (fileId != null) {
      _pathToFileId[toPath] = fileId;
      _fileIdToPath[fileId] = toPath;
    }
  }

  void remove(String relativePath) {
    final fileId = _pathToFileId.remove(relativePath);
    if (fileId != null) {
      _fileIdToNodeKey.remove(fileId);
      _fileIdToPath.remove(fileId);
    }
  }

  void rebuild(IGraph<NodeRecord> graph) {
    _pathToFileId.clear();
    _fileIdToNodeKey.clear();
    _fileIdToPath.clear();

    for (final entry in graph.nodeData.entries) {
      final record = entry.value;
      if (record is! FileRecord) continue;

      final fileNode = graph.getNodeByKey(record.key);
      if (fileNode == null) continue;

      // Walk the chain from file node to find current path and check deletion.
      // On forks (conflicts), pick the child whose subtree leaf has the latest
      // createdAt — same heuristic as findLeaf uses.
      var currentPath = record.path;
      var deleted = false;
      var current = fileNode;

      while (true) {
        final children = graph.getNodeEdges(current);
        if (children.isEmpty) break;
        current = children.length == 1
            ? children.first
            : _bestChild(graph, children);
        final childRecord = graph.getNodeData(current.key);
        if (childRecord is DeleteRecord) {
          deleted = true;
          // Don't break — a subsequent ChangeRecord means the file was recreated.
        } else if (childRecord is ChangeRecord) {
          deleted = false;
        } else if (childRecord is MoveRecord) {
          deleted = false;
          currentPath = childRecord.toPath;
        }
      }

      if (!deleted) {
        register(currentPath, record.fileId, record.key);
      }
    }
  }
}

/// Picks the child whose reachable leaf has the latest [NodeRecord.createdAt].
Node _bestChild(IGraph<NodeRecord> graph, Set<Node> children) {
  Node? best;
  DateTime? bestTime;
  for (final child in children) {
    final leaf = graph.findLeaf(child);
    final t = graph.getNodeData(leaf.key)?.createdAt;
    if (t != null && (bestTime == null || t.isAfter(bestTime))) {
      bestTime = t;
      best = child;
    }
  }
  return best ?? children.first;
}
