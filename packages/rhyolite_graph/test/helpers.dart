import 'dart:typed_data';
import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';

// ===========================================================================
// Graph builder
// ===========================================================================

/// Builds a standard test graph:
/// vault(synced) → file(synced) → c1(synced) → c2(synced) → c3(unsynced) → c4(unsynced)
({Graph<NodeRecord> graph, Node vaultNode, Node fileNode, Node c1, Node c2, Node c3, Node c4})
    buildStandardGraph() {
  final now = DateTime(2024);

  final vaultNode = VaultNode('vault');
  final fileNode = FileNode('file');
  final c1 = ChangeNode('c1');
  final c2 = ChangeNode('c2');
  final c3 = ChangeNode('c3');
  final c4 = ChangeNode('c4');

  final graph = Graph<NodeRecord>(root: vaultNode);
  graph.addNode(fileNode);
  graph.addNode(c1);
  graph.addNode(c2);
  graph.addNode(c3);
  graph.addNode(c4);

  graph.addEdge(vaultNode, fileNode);
  graph.addEdge(fileNode, c1);
  graph.addEdge(c1, c2);
  graph.addEdge(c2, c3);
  graph.addEdge(c3, c4);

  graph.updateNodeData('vault', VaultRecord(key: 'vault', vaultId: 'v1', isSynced: true, createdAt: now, name: 'Test'));
  graph.updateNodeData('file', FileRecord(key: 'file', vaultId: 'v1', parentKey: 'vault', isSynced: true, createdAt: now, fileId: 'f1', path: '/note.md'));
  graph.updateNodeData('c1', ChangeRecord(key: 'c1', vaultId: 'v1', parentKey: 'file', isSynced: true, createdAt: now.add(Duration(seconds: 1)), fileId: 'f1', blobId: 'blob1', sizeBytes: 10));
  graph.updateNodeData('c2', ChangeRecord(key: 'c2', vaultId: 'v1', parentKey: 'c1', isSynced: true, createdAt: now.add(Duration(seconds: 2)), fileId: 'f1', blobId: 'blob2', sizeBytes: 20));
  graph.updateNodeData('c3', ChangeRecord(key: 'c3', vaultId: 'v1', parentKey: 'c2', isSynced: false, createdAt: now.add(Duration(seconds: 3)), fileId: 'f1', blobId: 'blob3', sizeBytes: 30));
  graph.updateNodeData('c4', ChangeRecord(key: 'c4', vaultId: 'v1', parentKey: 'c3', isSynced: false, createdAt: now.add(Duration(seconds: 4)), fileId: 'f1', blobId: 'blob4', sizeBytes: 40));

  return (graph: graph, vaultNode: vaultNode, fileNode: fileNode, c1: c1, c2: c2, c3: c3, c4: c4);
}

NodeRecord record(Graph<NodeRecord> graph, String key) => graph.getNodeData(key)!;

// ===========================================================================
// Mocks
// ===========================================================================

class MockGraphServer implements IGraphServer {
  List<NodeRecord> pullResponse = [];
  List<NodeRecord>? pushedNodes;
  String? acquiredVaultId;
  bool lockReleased = false;

  @override
  Future<List<FilePullResult>> pull(List<FileSyncCursor> cursors) async =>
      cursors.map((c) => FilePullResult(fileId: c.fileId, nodes: pullResponse)).toList();

  @override
  Future<void> push(List<NodeRecord> nodes) async => pushedNodes = nodes;

  @override
  Future<String> acquireLock(String vaultId) async {
    acquiredVaultId = vaultId;
    return 'test-lock-token';
  }

  @override
  Future<void> releaseLock(String vaultId, String lockToken) async => lockReleased = true;

  @override
  Future<void> renewLock(String vaultId, String lockToken) async {}

  @override
  Future<int> getVaultEpoch() async => 0;

  @override
  Future<void> resetVault() async {}

  @override
  Future<void> deleteNodes(List<String> keys) async {}
}

class MockBlobStorage implements IBlobStorage {
  final Map<String, Uint8List> store;

  MockBlobStorage([Map<String, Uint8List>? initial]) : store = initial ?? {};

  @override
  Future<Map<String, Uint8List>> download(List<String> blobIds) async {
    final result = <String, Uint8List>{};
    for (final blobId in blobIds) {
      final bytes = store[blobId];
      if (bytes == null) throw StateError('Blob not found: $blobId');
      result[blobId] = bytes;
    }
    return result;
  }

  @override
  Future<void> upload(List<(Uint8List bytes, String blobId)> blobs) async {
    for (final (bytes, blobId) in blobs) {
      store[blobId] = bytes;
    }
  }
}

class MockContentMerger implements IContentMerger {
  final Uint8List? mergeResult;

  const MockContentMerger({this.mergeResult});

  @override
  Uint8List? tryMerge(Uint8List base, Uint8List local, Uint8List remote) => mergeResult;
}
