import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2024);

  late Graph<NodeRecord> graph;
  late Node vaultNode;
  late Node fileNode;

  setUp(() {
    vaultNode = VaultNode('vault');
    fileNode = FileNode('file');
    graph = Graph<NodeRecord>(root: vaultNode);
    graph.addNode(fileNode);
    graph.addEdge(vaultNode, fileNode);
    graph.updateNodeData('vault', VaultRecord(key: 'vault', vaultId: 'v1', isSynced: true, createdAt: now, name: 'T'));
    graph.updateNodeData('file', FileRecord(key: 'file', vaultId: 'v1', parentKey: 'vault', isSynced: true, createdAt: now, fileId: 'f1', path: '/a.md'));
  });

  group('graph.apply', () {
    test('adds new node to graph', () {
      final record = ChangeRecord(key: 'c1', vaultId: 'v1', parentKey: 'file', isSynced: true, createdAt: now.add(Duration(seconds: 1)), fileId: 'f1', blobId: 'b1', sizeBytes: 10);

      graph.apply([record]);

      expect(graph.containsNode('c1'), isTrue);
      expect(graph.getNodeData('c1'), equals(record));
    });

    test('connects node to its parent', () {
      final record = ChangeRecord(key: 'c1', vaultId: 'v1', parentKey: 'file', isSynced: true, createdAt: now.add(Duration(seconds: 1)), fileId: 'f1', blobId: 'b1', sizeBytes: 10);

      graph.apply([record]);

      expect(graph.getNodeParent(Node('c1')), equals(fileNode));
    });

    test('skips already-existing nodes', () {
      final record = ChangeRecord(key: 'c1', vaultId: 'v1', parentKey: 'file', isSynced: true, createdAt: now.add(Duration(seconds: 1)), fileId: 'f1', blobId: 'b1', sizeBytes: 10);
      graph.apply([record]);

      final updated = ChangeRecord(key: 'c1', vaultId: 'v1', parentKey: 'file', isSynced: false, createdAt: now.add(Duration(seconds: 1)), fileId: 'f1', blobId: 'b2', sizeBytes: 99);
      graph.apply([updated]);

      expect((graph.getNodeData('c1') as ChangeRecord).blobId, equals('b1'));
    });

    test('sorts by createdAt so parent is inserted before child', () {
      final c2 = ChangeRecord(key: 'c2', vaultId: 'v1', parentKey: 'c1', isSynced: true, createdAt: now.add(Duration(seconds: 2)), fileId: 'f1', blobId: 'b2', sizeBytes: 20);
      final c1 = ChangeRecord(key: 'c1', vaultId: 'v1', parentKey: 'file', isSynced: true, createdAt: now.add(Duration(seconds: 1)), fileId: 'f1', blobId: 'b1', sizeBytes: 10);

      expect(() => graph.apply([c2, c1]), returnsNormally);
      expect(graph.containsNode('c1'), isTrue);
      expect(graph.containsNode('c2'), isTrue);
    });

    test('throws StateError when parentKey not found in graph', () {
      final record = ChangeRecord(key: 'c1', vaultId: 'v1', parentKey: 'nonexistent', isSynced: true, createdAt: now, fileId: 'f1', blobId: 'b1', sizeBytes: 10);

      expect(() => graph.apply([record]), throwsStateError);
    });

    test('applies multiple records in one call', () {
      final c1 = ChangeRecord(key: 'c1', vaultId: 'v1', parentKey: 'file', isSynced: true, createdAt: now.add(Duration(seconds: 1)), fileId: 'f1', blobId: 'b1', sizeBytes: 10);
      final c2 = ChangeRecord(key: 'c2', vaultId: 'v1', parentKey: 'c1', isSynced: true, createdAt: now.add(Duration(seconds: 2)), fileId: 'f1', blobId: 'b2', sizeBytes: 20);

      graph.apply([c1, c2]);

      expect(graph.containsNode('c1'), isTrue);
      expect(graph.containsNode('c2'), isTrue);
      expect(graph.getNodeParent(Node('c2')), equals(Node('c1')));
    });
  });
}
