import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime(2024);
  final t1 = t0.add(Duration(seconds: 1));
  final t2 = t0.add(Duration(seconds: 2));
  final t3 = t0.add(Duration(seconds: 3));
  final t4 = t0.add(Duration(seconds: 4));

  Graph<NodeRecord> base() {
    final vault = VaultNode('vault');
    final file = FileNode('file');
    final g = Graph<NodeRecord>(root: vault);
    g.addNode(file);
    g.addEdge(vault, file);
    g.updateNodeData(
      'vault',
      VaultRecord(
        key: 'vault',
        vaultId: 'v1',
        isSynced: true,
        createdAt: t0,
        name: 'T',
      ),
    );
    g.updateNodeData(
      'file',
      FileRecord(
        key: 'file',
        vaultId: 'v1',
        parentKey: 'vault',
        isSynced: true,
        createdAt: t0,
        fileId: 'f1',
        path: 'doc.md',
      ),
    );
    return g;
  }

  ChangeRecord change(String key, String parent, DateTime at) => ChangeRecord(
    key: key,
    vaultId: 'v1',
    parentKey: parent,
    isSynced: true,
    createdAt: at,
    fileId: 'f1',
    blobId: 'b_$key',
    sizeBytes: 10,
  );

  group('findLeaf', () {
    test('returns start node when it has no children', () {
      final g = base();
      final file = g.getNodeByKey('file')!;
      expect(g.findLeaf(file), equals(file));
    });

    test('follows a single-branch chain to the end', () {
      final g = base();
      for (final (key, parent, at) in [
        ('c1', 'file', t1),
        ('c2', 'c1', t2),
        ('c3', 'c2', t3),
      ]) {
        final node = ChangeNode(key);
        g.addNode(node);
        g.addEdge(g.getNodeByKey(parent)!, node);
        g.updateNodeData(key, change(key, parent, at));
      }

      final leaf = g.findLeaf(g.getNodeByKey('file')!);
      expect(leaf.key, equals('c3'));
    });

    test('fork: picks the branch whose leaf has the later createdAt', () {
      // file → c1 → local(t2)
      //           → remote(t3)   ← later, should win
      final g = base();
      final c1 = ChangeNode('c1');
      final local = ChangeNode('local');
      final remote = ChangeNode('remote');

      g.addNode(c1);
      g.addNode(local);
      g.addNode(remote);
      g.addEdge(g.getNodeByKey('file')!, c1);
      g.addEdge(c1, local);
      g.addEdge(c1, remote);
      g.updateNodeData('c1', change('c1', 'file', t1));
      g.updateNodeData('local', change('local', 'c1', t2));
      g.updateNodeData('remote', change('remote', 'c1', t3));

      expect(g.findLeaf(g.getNodeByKey('file')!), equals(remote));
    });

    test('fork: picks local branch when local leaf is newer', () {
      // file → c1 → local(t4)  ← later, should win
      //           → remote(t3)
      final g = base();
      final c1 = ChangeNode('c1');
      final local = ChangeNode('local');
      final remote = ChangeNode('remote');

      g.addNode(c1);
      g.addNode(local);
      g.addNode(remote);
      g.addEdge(g.getNodeByKey('file')!, c1);
      g.addEdge(c1, local);
      g.addEdge(c1, remote);
      g.updateNodeData('c1', change('c1', 'file', t1));
      g.updateNodeData('local', change('local', 'c1', t4));
      g.updateNodeData('remote', change('remote', 'c1', t3));

      expect(g.findLeaf(g.getNodeByKey('file')!), equals(local));
    });

    test(
      'fork: resolution record on remote branch wins over orphaned local',
      () {
        // file → c1 → local(t2)           ← dead-end
        //           → remote(t3) → res(t4) ← deepest, should win
        final g = base();
        final c1 = ChangeNode('c1');
        final local = ChangeNode('local');
        final remote = ChangeNode('remote');
        final res = ChangeNode('res');

        g.addNode(c1);
        g.addNode(local);
        g.addNode(remote);
        g.addNode(res);
        g.addEdge(g.getNodeByKey('file')!, c1);
        g.addEdge(c1, local);
        g.addEdge(c1, remote);
        g.addEdge(remote, res);
        g.updateNodeData('c1', change('c1', 'file', t1));
        g.updateNodeData('local', change('local', 'c1', t2));
        g.updateNodeData('remote', change('remote', 'c1', t3));
        g.updateNodeData('res', change('res', 'remote', t4));

        expect(g.findLeaf(g.getNodeByKey('file')!), equals(res));
      },
    );

    test('fork: three-way fork picks the branch with latest leaf', () {
      // file → a(t1), b(t3), c(t2) → latest is b
      final g = base();
      for (final (key, at) in [('a', t1), ('b', t3), ('c', t2)]) {
        final node = ChangeNode(key);
        g.addNode(node);
        g.addEdge(g.getNodeByKey('file')!, node);
        g.updateNodeData(key, change(key, 'file', at));
      }

      expect(g.findLeaf(g.getNodeByKey('file')!).key, equals('b'));
    });
  });
}
