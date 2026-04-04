import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('GetUnsyncedNodesUseCase', () {
    test('returns unsynced nodes in parent-first order', () {
      final r = buildStandardGraph();
      final result = GetUnsyncedNodesUseCase(r.graph)(r.fileNode);
      expect(result.map((r) => r.key), equals(['c3', 'c4']));
    });

    test('returns empty when all nodes are synced', () {
      final r = buildStandardGraph();
      r.graph.updateNodeData('c3', (r.graph.getNodeData('c3') as ChangeRecord).withSynced());
      r.graph.updateNodeData('c4', (r.graph.getNodeData('c4') as ChangeRecord).withSynced());

      final result = GetUnsyncedNodesUseCase(r.graph)(r.fileNode);
      expect(result, isEmpty);
    });

    test('returns all change nodes when none are synced', () {
      final now = DateTime(2024);
      final vaultNode = VaultNode('vault');
      final fileNode = FileNode('file');
      final c1 = ChangeNode('c1');
      final c2 = ChangeNode('c2');

      final graph = Graph<NodeRecord>(root: vaultNode);
      graph.addNode(fileNode);
      graph.addNode(c1);
      graph.addNode(c2);
      graph.addEdge(vaultNode, fileNode);
      graph.addEdge(fileNode, c1);
      graph.addEdge(c1, c2);
      graph.updateNodeData('vault', VaultRecord(key: 'vault', isSynced: false, createdAt: now, vaultId: 'v1', name: 'T'));
      graph.updateNodeData('file', FileRecord(key: 'file', vaultId: 'v1', parentKey: 'vault', isSynced: false, createdAt: now, fileId: 'f1', path: '/a.md'));
      graph.updateNodeData('c1', ChangeRecord(key: 'c1', vaultId: 'v1', parentKey: 'file', isSynced: false, createdAt: now, fileId: 'f1', blobId: 'b1', sizeBytes: 1));
      graph.updateNodeData('c2', ChangeRecord(key: 'c2', vaultId: 'v1', parentKey: 'c1', isSynced: false, createdAt: now, fileId: 'f1', blobId: 'b2', sizeBytes: 2));

      final result = GetUnsyncedNodesUseCase(graph)(fileNode);
      expect(result.map((r) => r.key), equals(['file', 'c1', 'c2']));
    });
  });
}
