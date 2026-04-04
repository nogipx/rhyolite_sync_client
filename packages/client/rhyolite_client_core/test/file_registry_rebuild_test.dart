import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:test/test.dart';

import 'package:rhyolite_client_core/src/engine/file_registry.dart';

// ---------------------------------------------------------------------------
// Graph builder helpers
// ---------------------------------------------------------------------------

const _vaultId = 'v1';
const _fileId = 'f1';

final _t0 = DateTime(2024, 1, 1);

Graph<NodeRecord> _base() {
  final vault = VaultNode('vault');
  final file = FileNode('file');
  final g = Graph<NodeRecord>(root: vault);
  g.addNode(file);
  g.addEdge(vault, file);
  g.updateNodeData('vault', VaultRecord(key: 'vault', vaultId: _vaultId, isSynced: true, createdAt: _t0, name: 'T'));
  g.updateNodeData('file', FileRecord(key: 'file', vaultId: _vaultId, parentKey: 'vault', isSynced: true, createdAt: _t0, fileId: _fileId, path: 'doc.md'));
  return g;
}

ChangeRecord _change(String key, String parent, DateTime at, {String? blobId}) =>
    ChangeRecord(key: key, vaultId: _vaultId, parentKey: parent, isSynced: true, createdAt: at, fileId: _fileId, blobId: blobId ?? 'b_$key', sizeBytes: 10);

MoveRecord _move(String key, String parent, String from, String to) =>
    MoveRecord(key: key, vaultId: _vaultId, parentKey: parent, isSynced: true, createdAt: _t0, fileId: _fileId, fromPath: from, toPath: to);

DeleteRecord _delete(String key, String parent) =>
    DeleteRecord(key: key, vaultId: _vaultId, parentKey: parent, isSynced: true, createdAt: _t0, fileId: _fileId);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('FileRegistry.rebuild', () {
    group('linear chain', () {
      test('registers a simple file with no changes', () {
        final g = _base();
        final r = FileRegistry()..rebuild(g);
        expect(r.pathByFileId(_fileId), equals('doc.md'));
        expect(r.nodeKeyByFileId(_fileId), equals('file'));
      });

      test('registers path after a MoveRecord', () {
        final g = _base();
        final mv = MoveNode('mv');
        g.addNode(mv);
        g.addEdge(g.getNodeByKey('file')!, mv);
        g.updateNodeData('mv', _move('mv', 'file', 'doc.md', 'notes/doc.md'));

        final r = FileRegistry()..rebuild(g);
        expect(r.pathByFileId(_fileId), equals('notes/doc.md'));
      });

      test('does not register a deleted file', () {
        final g = _base();
        final del = DeleteNode('del');
        g.addNode(del);
        g.addEdge(g.getNodeByKey('file')!, del);
        g.updateNodeData('del', _delete('del', 'file'));

        final r = FileRegistry()..rebuild(g);
        expect(r.pathByFileId(_fileId), isNull);
      });

      test('rebuilds multiple files independently', () {
        final g = _base();
        // Add a second file
        final file2 = FileNode('file2');
        g.addNode(file2);
        g.addEdge(g.getNodeByKey('vault')!, file2);
        g.updateNodeData('file2', FileRecord(key: 'file2', vaultId: _vaultId, parentKey: 'vault', isSynced: true, createdAt: _t0, fileId: 'f2', path: 'other.md'));

        final r = FileRegistry()..rebuild(g);
        expect(r.pathByFileId(_fileId), equals('doc.md'));
        expect(r.pathByFileId('f2'), equals('other.md'));
      });
    });

    group('fork handling', () {
      // Graph after conflict pull:
      //   vault → file → c_local(t2, unsynced)
      //                → c_remote(t3, synced)   ← later, should win
      test('picks the branch with the later leaf createdAt', () {
        final g = _base();
        final cLocal = ChangeNode('c-local');
        final cRemote = ChangeNode('c-remote');
        g.addNode(cLocal);
        g.addNode(cRemote);
        g.addEdge(g.getNodeByKey('file')!, cLocal);
        g.addEdge(g.getNodeByKey('file')!, cRemote);
        g.updateNodeData('c-local', _change('c-local', 'file', _t0.add(Duration(seconds: 2))));
        g.updateNodeData('c-remote', _change('c-remote', 'file', _t0.add(Duration(seconds: 3))));

        // Path unchanged (both branches have same file, no MoveRecord)
        final r = FileRegistry()..rebuild(g);
        expect(r.pathByFileId(_fileId), equals('doc.md'));
      });

      test('resolution record on remote branch is followed', () {
        // file → c_local(t2)                      ← dead-end, leaf=t2
        //      → c_remote(t3) → res(t4, MoveRecord to renamed.md)  ← leaf=t4, wins
        final g = _base();
        final cLocal = ChangeNode('c-local');
        final cRemote = ChangeNode('c-remote');
        final res = MoveNode('res');
        g.addNode(cLocal);
        g.addNode(cRemote);
        g.addNode(res);
        g.addEdge(g.getNodeByKey('file')!, cLocal);
        g.addEdge(g.getNodeByKey('file')!, cRemote);
        g.addEdge(cRemote, res);
        g.updateNodeData('c-local', _change('c-local', 'file', _t0.add(Duration(seconds: 2))));
        g.updateNodeData('c-remote', _change('c-remote', 'file', _t0.add(Duration(seconds: 3))));
        // res must have createdAt > c_local so it wins the leaf comparison
        g.updateNodeData('res', MoveRecord(
          key: 'res', vaultId: _vaultId, parentKey: 'c-remote',
          isSynced: false, createdAt: _t0.add(Duration(seconds: 4)),
          fileId: _fileId, fromPath: 'doc.md', toPath: 'renamed.md',
        ));

        final r = FileRegistry()..rebuild(g);
        // Must follow c-remote → res branch and apply the rename
        expect(r.pathByFileId(_fileId), equals('renamed.md'));
      });

      test('file deleted on winning branch is not registered', () {
        // file → c_local(t4)          ← dead-end (local was newer but still loses to delete)
        //      → c_remote(t2) → del  ← remote branch has delete
        // c_remote wins by createdAt of del (but del has default _t0 timestamp)
        // Actually: remote branch leaf is del(_t0) vs local leaf c_local(t4) → local wins by time
        // So: rebuild follows c_local → file is still alive (not deleted)
        // Let's make c_remote + del have later timestamp to test deletion path
        final g = _base();
        final cLocal = ChangeNode('c-local');
        final cRemote = ChangeNode('c-remote');
        final del = DeleteNode('del');
        g.addNode(cLocal);
        g.addNode(cRemote);
        g.addNode(del);
        g.addEdge(g.getNodeByKey('file')!, cLocal);
        g.addEdge(g.getNodeByKey('file')!, cRemote);
        g.addEdge(cRemote, del);
        g.updateNodeData('c-local', _change('c-local', 'file', _t0.add(Duration(seconds: 1))));
        g.updateNodeData('c-remote', _change('c-remote', 'file', _t0.add(Duration(seconds: 2))));
        // del has _t0 — but we need del to be the leaf with later time than c_local
        g.updateNodeData('del', DeleteRecord(
          key: 'del', vaultId: _vaultId, parentKey: 'c-remote',
          isSynced: true, createdAt: _t0.add(Duration(seconds: 5)), fileId: _fileId,
        ));

        final r = FileRegistry()..rebuild(g);
        // del(t5) > c_local(t1) → remote branch wins → file is deleted
        expect(r.pathByFileId(_fileId), isNull);
      });

      test('local branch wins when local leaf is newer', () {
        // file → c_local(t5)   ← later, local wins
        //      → c_remote(t3)
        // No MoveRecord on local, file path should be doc.md
        final g = _base();
        final cLocal = ChangeNode('c-local');
        final cRemote = ChangeNode('c-remote');
        g.addNode(cLocal);
        g.addNode(cRemote);
        g.addEdge(g.getNodeByKey('file')!, cLocal);
        g.addEdge(g.getNodeByKey('file')!, cRemote);
        g.updateNodeData('c-local', _change('c-local', 'file', _t0.add(Duration(seconds: 5))));
        g.updateNodeData('c-remote', _change('c-remote', 'file', _t0.add(Duration(seconds: 3))));

        final r = FileRegistry()..rebuild(g);
        expect(r.pathByFileId(_fileId), equals('doc.md'));
      });
    });
  });
}
