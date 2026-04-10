import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final now = DateTime(2024);

  group('PullUseCase', () {
    test('returns empty list when server has no new nodes', () async {
      final r = buildStandardGraph();
      final server = MockGraphServer()..pullResponse = [];

      final result = await PullUseCase(graph: r.graph, server: server)([r.fileNode]);
      expect(result, isEmpty);
    });

    test('returns remote nodes without applying them to the graph', () async {
      final r = buildStandardGraph();
      final remoteNodes = <NodeRecord>[
        ChangeRecord(key: 'c5', vaultId: 'v1', parentKey: 'c4', isSynced: true, createdAt: now.add(Duration(seconds: 5)), fileId: 'f1', blobId: 'b5', sizeBytes: 50),
      ];
      final server = MockGraphServer()..pullResponse = remoteNodes;

      final result = await PullUseCase(graph: r.graph, server: server)([r.fileNode]);

      expect(result.single.nodes, equals(remoteNodes));
      expect(r.graph.containsNode('c5'), isFalse);
    });

    test('passes correct fileId and lastSyncedKey to server', () async {
      final r = buildStandardGraph();
      List<FileSyncCursor>? capturedCursors;

      final server = _CapturingServer(onPull: (cursors) {
        capturedCursors = cursors;
        return [];
      });

      await PullUseCase(graph: r.graph, server: server)([r.fileNode]);

      expect(capturedCursors?.single.fileId, equals('f1'));
      expect(capturedCursors?.single.lastSyncedKey, equals('c2'));
    });

    test('passes null lastSyncedKey when no synced nodes exist', () async {
      final vaultNode = VaultNode('vault');
      final fileNode = FileNode('file');
      final graph = Graph<NodeRecord>(root: vaultNode);
      graph.addNode(fileNode);
      graph.addEdge(vaultNode, fileNode);
      graph.updateNodeData('vault', VaultRecord(key: 'vault', isSynced: false, createdAt: now, vaultId: 'v1', name: 'T'));
      graph.updateNodeData('file', FileRecord(key: 'file', vaultId: 'v1', parentKey: 'vault', isSynced: false, createdAt: now, fileId: 'f1', path: '/a.md'));

      List<FileSyncCursor>? capturedCursors;
      await PullUseCase(
        graph: graph,
        server: _CapturingServer(onPull: (cursors) {
          capturedCursors = cursors;
          return [];
        }),
      )([fileNode]);

      expect(capturedCursors?.single.lastSyncedKey, isNull);
    });

    test('throws when node is not a FileRecord', () async {
      final r = buildStandardGraph();
      final server = MockGraphServer();

      expect(
        () => PullUseCase(graph: r.graph, server: server)([r.vaultNode]),
        throwsStateError,
      );
    });
  });
}

class _CapturingServer implements IGraphServer {
  final List<NodeRecord> Function(List<FileSyncCursor>) onPull;
  _CapturingServer({required this.onPull});

  @override
  Future<List<FilePullResult>> pull(List<FileSyncCursor> cursors) async =>
      cursors.map((c) => FilePullResult(fileId: c.fileId, nodes: onPull(cursors))).toList();

  @override
  Future<void> push(List<NodeRecord> nodes) async {}

  @override
  Future<String> acquireLock(String vaultId) async => '';

  @override
  Future<void> releaseLock(String vaultId, String lockToken) async {}

  @override
  Future<void> renewLock(String vaultId, String lockToken) async {}

  @override
  Future<int> getVaultEpoch() async => 0;

  @override
  Future<void> resetVault() async {}

  @override
  Future<void> deleteNodes(List<String> keys) async {}
}
