import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('FindLastSyncedUseCase', () {
    test('returns last synced node when chain has synced prefix and unsynced tail', () {
      final r = buildStandardGraph();
      final result = FindLastSyncedUseCase(r.graph)(r.fileNode);
      expect(result, equals(r.c2));
    });

    test('returns null when no nodes are synced', () {
      final now = DateTime(2024);
      final vaultNode = VaultNode('vault');
      final fileNode = FileNode('file');
      final c1 = ChangeNode('c1');

      final graph = Graph<NodeRecord>(root: vaultNode);
      graph.addNode(fileNode);
      graph.addNode(c1);
      graph.addEdge(vaultNode, fileNode);
      graph.addEdge(fileNode, c1);
      graph.updateNodeData('vault', VaultRecord(key: 'vault', isSynced: false, createdAt: now, vaultId: 'v1', name: 'T'));
      graph.updateNodeData('file', FileRecord(key: 'file', vaultId: 'v1', parentKey: 'vault', isSynced: false, createdAt: now, fileId: 'f1', path: '/a.md'));
      graph.updateNodeData('c1', ChangeRecord(key: 'c1', vaultId: 'v1', parentKey: 'file', isSynced: false, createdAt: now, fileId: 'f1', blobId: 'b1', sizeBytes: 10));

      final result = FindLastSyncedUseCase(graph)(fileNode);
      expect(result, isNull);
    });

    test('returns leaf when all nodes are synced', () {
      final r = buildStandardGraph();
      r.graph.updateNodeData('c3', (r.graph.getNodeData('c3') as ChangeRecord).withSynced());
      r.graph.updateNodeData('c4', (r.graph.getNodeData('c4') as ChangeRecord).withSynced());

      final result = FindLastSyncedUseCase(r.graph)(r.fileNode);
      expect(result, equals(r.c4));
    });

    test('returns fileNode itself when it is the only synced node with no children', () {
      final now = DateTime(2024);
      final vaultNode = VaultNode('vault');
      final fileNode = FileNode('file');

      final graph = Graph<NodeRecord>(root: vaultNode);
      graph.addNode(fileNode);
      graph.addEdge(vaultNode, fileNode);
      graph.updateNodeData('vault', VaultRecord(key: 'vault', isSynced: true, createdAt: now, vaultId: 'v1', name: 'T'));
      graph.updateNodeData('file', FileRecord(key: 'file', vaultId: 'v1', parentKey: 'vault', isSynced: true, createdAt: now, fileId: 'f1', path: '/a.md'));

      final result = FindLastSyncedUseCase(graph)(fileNode);
      expect(result, equals(fileNode));
    });
  });
}
