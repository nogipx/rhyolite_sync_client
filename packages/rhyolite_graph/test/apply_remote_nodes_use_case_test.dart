import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2024);

  group('ApplyRemoteNodesUseCase', () {
    late Graph<NodeRecord> graph;
    late Node vaultNode;
    late Node fileNode;

    setUp(() {
      vaultNode = VaultNode('vault');
      fileNode = FileNode('file');
      graph = Graph<NodeRecord>(root: vaultNode);
      graph.addNode(fileNode);
      graph.addEdge(vaultNode, fileNode);
      graph.updateNodeData('vault', VaultRecord(key: 'vault', isSynced: true, createdAt: now, vaultId: 'v1', name: 'T'));
      graph.updateNodeData('file', FileRecord(key: 'file', vaultId: 'v1', parentKey: 'vault', isSynced: true, createdAt: now, fileId: 'f1', path: '/a.md'));
    });

    test('adds nodes to graph with correct structure', () {
      final nodes = [
        ChangeRecord(key: 'c1', vaultId: 'v1', parentKey: 'file', isSynced: true, createdAt: now.add(Duration(seconds: 1)), fileId: 'f1', blobId: 'b1', sizeBytes: 10),
        ChangeRecord(key: 'c2', vaultId: 'v1', parentKey: 'c1', isSynced: true, createdAt: now.add(Duration(seconds: 2)), fileId: 'f1', blobId: 'b2', sizeBytes: 20),
      ];

      ApplyRemoteNodesUseCase(graph)(nodes);

      expect(graph.containsNode('c1'), isTrue);
      expect(graph.containsNode('c2'), isTrue);
      expect(graph.getNodeParent(Node('c1')), equals(fileNode));
      expect(graph.getNodeParent(Node('c2')), equals(Node('c1')));
    });

    test('sorts nodes by createdAt before applying', () {
      final nodes = [
        ChangeRecord(key: 'c2', vaultId: 'v1', parentKey: 'c1', isSynced: true, createdAt: now.add(Duration(seconds: 2)), fileId: 'f1', blobId: 'b2', sizeBytes: 20),
        ChangeRecord(key: 'c1', vaultId: 'v1', parentKey: 'file', isSynced: true, createdAt: now.add(Duration(seconds: 1)), fileId: 'f1', blobId: 'b1', sizeBytes: 10),
      ];

      // c2 before c1 in list — should still work after sort
      expect(() => ApplyRemoteNodesUseCase(graph)(nodes), returnsNormally);
      expect(graph.containsNode('c1'), isTrue);
      expect(graph.containsNode('c2'), isTrue);
    });

    test('stores node data correctly', () {
      final record = ChangeRecord(key: 'c1', vaultId: 'v1', parentKey: 'file', isSynced: true, createdAt: now, fileId: 'f1', blobId: 'b1', sizeBytes: 10);
      ApplyRemoteNodesUseCase(graph)([record]);

      final stored = graph.getNodeData('c1') as ChangeRecord;
      expect(stored.blobId, equals('b1'));
      expect(stored.sizeBytes, equals(10));
    });

    test('throws StateError when parent not found', () {
      final nodes = [
        ChangeRecord(key: 'c1', vaultId: 'v1', parentKey: 'nonexistent', isSynced: true, createdAt: now, fileId: 'f1', blobId: 'b1', sizeBytes: 10),
      ];

      expect(() => ApplyRemoteNodesUseCase(graph)(nodes), throwsStateError);
    });
  });
}