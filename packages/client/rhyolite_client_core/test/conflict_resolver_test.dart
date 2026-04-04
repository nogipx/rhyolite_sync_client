import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_client_core/src/engine/conflict_resolver.dart';
import 'package:rhyolite_client_core/src/engine/file_registry.dart';
import 'package:rhyolite_client_core/src/engine/vault_config.dart';
import 'package:rhyolite_client_core/src/local/local_blob_store.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:rpc_blob/rpc_blob.dart';
import 'package:test/test.dart';

import 'helpers/test_io.dart';

// ---------------------------------------------------------------------------
// In-memory IBlobStorage for the remote side
// ---------------------------------------------------------------------------

class _RemoteStorage implements IBlobStorage {
  final Map<String, Uint8List> _store = {};

  void seed(String blobId, Uint8List bytes) => _store[blobId] = bytes;

  @override
  Future<Map<String, Uint8List>> download(List<String> blobIds) async {
    final result = <String, Uint8List>{};
    for (final blobId in blobIds) {
      final bytes = _store[blobId];
      if (bytes == null) throw StateError('Remote blob not found: $blobId');
      result[blobId] = bytes;
    }
    return result;
  }

  @override
  Future<void> upload(List<(Uint8List bytes, String blobId)> blobs) async {
    for (final (bytes, blobId) in blobs) {
      _store[blobId] = bytes;
    }
  }
}

// ---------------------------------------------------------------------------
// Scenario setup helpers
// ---------------------------------------------------------------------------

const _vaultId = 'v1';
const _fileId = 'f1';

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

/// Builds the graph state that exists AFTER a remote pull created a fork:
///
///   vault → fileNode → c_base(synced) → c_local(unsynced)   ← localLeafBeforePull
///                                     → c_remote(synced)     ← just pulled
({
  Node fileNode,
  Graph<NodeRecord> graph,
  Node localNode,
  LocalBlobStore localStore,
  ConflictResolver Function([ConflictStrategy? s]) makeResolver,
  FileRegistry registry,
  Node remoteNode,
  _RemoteStorage remoteStorage,
})
_buildScenario({
  required String filePath,
  required Uint8List baseBlob,
  required Uint8List localBlob,
  required Uint8List remoteBlob,
  required Directory tempDir,
  DateTime? localCreatedAt,
  DateTime? remoteCreatedAt,
  ConflictStrategy strategy = ConflictStrategy.lww,
}) {
  final t0 = DateTime(2024, 1, 1);
  localCreatedAt ??= t0.add(Duration(seconds: 2));
  remoteCreatedAt ??= t0.add(Duration(seconds: 3));

  final vaultNode = VaultNode('vault');
  final fileNode = FileNode('file-node');
  final cBase = ChangeNode('c-base');
  final cLocal = ChangeNode('c-local');
  final cRemote = ChangeNode('c-remote');

  final graph = Graph<NodeRecord>(root: vaultNode);
  for (final n in [fileNode, cBase, cLocal, cRemote]) {
    graph.addNode(n);
  }
  graph.addEdge(vaultNode, fileNode);
  graph.addEdge(fileNode, cBase);
  graph.addEdge(cBase, cLocal);
  graph.addEdge(cBase, cRemote); // fork

  graph.updateNodeData(
    'vault',
    VaultRecord(
      key: 'vault',
      vaultId: _vaultId,
      isSynced: true,
      createdAt: t0,
      name: 'T',
    ),
  );
  graph.updateNodeData(
    'file-node',
    FileRecord(
      key: 'file-node',
      vaultId: _vaultId,
      parentKey: 'vault',
      isSynced: true,
      createdAt: t0,
      fileId: _fileId,
      path: filePath,
    ),
  );
  graph.updateNodeData(
    'c-base',
    ChangeRecord(
      key: 'c-base',
      vaultId: _vaultId,
      parentKey: 'file-node',
      isSynced: true,
      createdAt: t0.add(Duration(seconds: 1)),
      fileId: _fileId,
      blobId: 'blob-base',
      sizeBytes: baseBlob.length,
    ),
  );
  graph.updateNodeData(
    'c-local',
    ChangeRecord(
      key: 'c-local',
      vaultId: _vaultId,
      parentKey: 'c-base',
      isSynced: false,
      createdAt: localCreatedAt,
      fileId: _fileId,
      blobId: 'blob-local',
      sizeBytes: localBlob.length,
    ),
  );
  graph.updateNodeData(
    'c-remote',
    ChangeRecord(
      key: 'c-remote',
      vaultId: _vaultId,
      parentKey: 'c-base',
      isSynced: true,
      createdAt: remoteCreatedAt,
      fileId: _fileId,
      blobId: 'blob-remote',
      sizeBytes: remoteBlob.length,
    ),
  );

  final registry = FileRegistry()..register(filePath, _fileId, 'file-node');
  final localStore = LocalBlobStore(InMemoryBlobRepository());
  final remoteStorage = _RemoteStorage()..seed('blob-remote', remoteBlob);

  ConflictResolver buildResolver([ConflictStrategy? s]) => ConflictResolver(
    graph: graph,
    fileRegistry: registry,
    localBlobStore: localStore,
    remoteBlobStorage: remoteStorage,
    vaultPath: tempDir.path,
    vaultId: _vaultId,
    strategy: s ?? strategy,
    io: TestIO(),
  );

  return (
    graph: graph,
    fileNode: fileNode as Node,
    localNode: cLocal as Node,
    remoteNode: cRemote as Node,
    registry: registry,
    localStore: localStore,
    remoteStorage: remoteStorage,
    makeResolver: buildResolver,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('conflict_resolver_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // ------------------------------------------------------------------
  // No-conflict fast paths
  // ------------------------------------------------------------------

  group('no conflict', () {
    test('passes through when pulled list is empty', () async {
      final s = _buildScenario(
        filePath: 'doc.md',
        baseBlob: _utf8('base'),
        localBlob: _utf8('local'),
        remoteBlob: _utf8('remote'),
        tempDir: tempDir,
      );

      final resolution = await s.makeResolver().call(
        s.fileNode,
        s.localNode,
        <NodeRecord>[],
      );

      expect(resolution.recordsForDisk, isEmpty);
      expect(resolution.newLocalRecords, isEmpty);
    });

    test('passes through when local leaf is already synced', () async {
      final s = _buildScenario(
        filePath: 'doc.md',
        baseBlob: _utf8('base'),
        localBlob: _utf8('local'),
        remoteBlob: _utf8('remote'),
        tempDir: tempDir,
      );

      // Mark local leaf as synced → no conflict
      s.graph.updateNodeData(
        'c-local',
        ChangeRecord(
          key: 'c-local',
          vaultId: _vaultId,
          parentKey: 'c-base',
          isSynced: true,
          createdAt: DateTime(2024, 1, 1, 0, 0, 2),
          fileId: _fileId,
          blobId: 'blob-local',
          sizeBytes: 5,
        ),
      );

      final remoteChange = s.graph.getNodeData('c-remote') as ChangeRecord;
      final resolution = await s.makeResolver().call(s.fileNode, s.localNode, [
        remoteChange,
      ]);

      expect(resolution.newLocalRecords, isEmpty);
    });

    test(
      'passes through when pulled records have no ChangeRecord for this file',
      () async {
        final s = _buildScenario(
          filePath: 'doc.md',
          baseBlob: _utf8('base'),
          localBlob: _utf8('local'),
          remoteBlob: _utf8('remote'),
          tempDir: tempDir,
        );

        final otherChange = ChangeRecord(
          key: 'other',
          vaultId: _vaultId,
          parentKey: 'c-base',
          isSynced: true,
          createdAt: DateTime(2024),
          fileId: 'other-file',
          blobId: 'blob-other',
          sizeBytes: 5,
        );

        final resolution = await s.makeResolver().call(
          s.fileNode,
          s.localNode,
          [otherChange],
        );

        expect(resolution.newLocalRecords, isEmpty);
      },
    );
  });

  // ------------------------------------------------------------------
  // Text file (.md) — clean 3-way merge
  //
  // Non-overlapping edits: local edits line 1, remote edits line 3.
  // diff-match-patch cleanly merges both changes.
  // ------------------------------------------------------------------

  group('text merge (.md)', () {
    const baseText = 'Line 1\nLine 2\nLine 3\n';
    const localText = 'Line 1 [LOCAL]\nLine 2\nLine 3\n';
    const remoteText = 'Line 1\nLine 2\nLine 3 [REMOTE]\n';

    test('clean merge: writes merged file to disk with both edits', () async {
      final s = _buildScenario(
        filePath: 'notes/doc.md',
        baseBlob: _utf8(baseText),
        localBlob: _utf8(localText),
        remoteBlob: _utf8(remoteText),
        tempDir: tempDir,
      );

      await s.localStore.write(_utf8(baseText), 'blob-base', vaultId: _vaultId);
      await s.localStore.write(
        _utf8(localText),
        'blob-local',
        vaultId: _vaultId,
      );
      Directory('${tempDir.path}/notes').createSync();

      final remoteChange = s.graph.getNodeData('c-remote') as ChangeRecord;
      final resolution = await s.makeResolver().call(s.fileNode, s.localNode, [
        remoteChange,
      ]);

      expect(resolution.newLocalRecords, hasLength(1));
      expect(resolution.newLocalRecords.first, isA<ChangeRecord>());

      final merged = resolution.newLocalRecords.first as ChangeRecord;
      expect(merged.parentKey, equals('c-remote'));
      expect(merged.isSynced, isFalse);

      final written = File('${tempDir.path}/notes/doc.md').readAsStringSync();
      expect(written, contains('Line 1 [LOCAL]'));
      expect(written, contains('Line 3 [REMOTE]'));
    });

    test(
      'clean merge: conflicting ChangeRecord is excluded from recordsForDisk',
      () async {
        final s = _buildScenario(
          filePath: 'doc.md',
          baseBlob: _utf8(baseText),
          localBlob: _utf8(localText),
          remoteBlob: _utf8(remoteText),
          tempDir: tempDir,
        );

        await s.localStore.write(
          _utf8(baseText),
          'blob-base',
          vaultId: _vaultId,
        );
        await s.localStore.write(
          _utf8(localText),
          'blob-local',
          vaultId: _vaultId,
        );

        final remoteChange = s.graph.getNodeData('c-remote') as ChangeRecord;
        final resolution = await s.makeResolver().call(
          s.fileNode,
          s.localNode,
          [remoteChange],
        );

        expect(
          resolution.recordsForDisk.whereType<ChangeRecord>().where(
            (r) => r.fileId == _fileId,
          ),
          isEmpty,
        );
      },
    );

    test(
      'clean merge: merged ChangeRecord is a child of remoteChange in the graph',
      () async {
        final s = _buildScenario(
          filePath: 'doc.md',
          baseBlob: _utf8(baseText),
          localBlob: _utf8(localText),
          remoteBlob: _utf8(remoteText),
          tempDir: tempDir,
        );

        await s.localStore.write(
          _utf8(baseText),
          'blob-base',
          vaultId: _vaultId,
        );
        await s.localStore.write(
          _utf8(localText),
          'blob-local',
          vaultId: _vaultId,
        );

        final remoteChange = s.graph.getNodeData('c-remote') as ChangeRecord;
        final resolution = await s.makeResolver().call(
          s.fileNode,
          s.localNode,
          [remoteChange],
        );

        final merged = resolution.newLocalRecords.first as ChangeRecord;
        final mergedNode = s.graph.getNodeByKey(merged.key);
        expect(mergedNode, isNotNull);
        expect(s.graph.getNodeParent(mergedNode!)?.key, equals('c-remote'));

        // c-remote now has the merged node as its only child (local branch pruned)
        final remoteNode = s.graph.getNodeByKey('c-remote')!;
        expect(s.graph.getNodeEdges(remoteNode), contains(mergedNode));
        expect(s.graph.containsNode('c-local'), isFalse);
      },
    );

    test('clean merge: merged blob is stored in local blob store', () async {
      final s = _buildScenario(
        filePath: 'doc.md',
        baseBlob: _utf8(baseText),
        localBlob: _utf8(localText),
        remoteBlob: _utf8(remoteText),
        tempDir: tempDir,
      );

      await s.localStore.write(_utf8(baseText), 'blob-base', vaultId: _vaultId);
      await s.localStore.write(
        _utf8(localText),
        'blob-local',
        vaultId: _vaultId,
      );

      final remoteChange = s.graph.getNodeData('c-remote') as ChangeRecord;
      final resolution = await s.makeResolver().call(s.fileNode, s.localNode, [
        remoteChange,
      ]);

      final merged = resolution.newLocalRecords.first as ChangeRecord;
      final stored = await s.localStore.read(merged.blobId, vaultId: _vaultId);
      expect(stored, isNotNull);
      final content = utf8.decode(stored!);
      expect(content, contains('Line 1 [LOCAL]'));
      expect(content, contains('Line 3 [REMOTE]'));
    });
  });

  // ------------------------------------------------------------------
  // Text file (.md) — dmp fails, falls back to strategy
  //
  // base / local / remote are constructed with completely disjoint
  // character sets so patchApply cannot find context → returns false.
  // ------------------------------------------------------------------

  group('text merge fallback when dmp fails (.md)', () {
    // All three texts use different "namespaces" of characters/markers so
    // the patch from base→remote has no matchable context in local.
    const baseText = '=BASE=LINE=ONE=\n=BASE=LINE=TWO=\n';
    const localText = '#LOCAL#CHANGE#1\n#LOCAL#CHANGE#2\n';
    const remoteText = '@REMOTE@EDIT@A\n@REMOTE@EDIT@B\n';

    test(
      'dmp fails → LWW remote wins when remote.createdAt > local.createdAt',
      () async {
        final s = _buildScenario(
          filePath: 'doc.md',
          baseBlob: _utf8(baseText),
          localBlob: _utf8(localText),
          remoteBlob: _utf8(remoteText),
          tempDir: tempDir,
          localCreatedAt: DateTime(2024, 1, 1, 0, 0, 1),
          remoteCreatedAt: DateTime(2024, 1, 1, 0, 0, 9),
        );

        await s.localStore.write(
          _utf8(baseText),
          'blob-base',
          vaultId: _vaultId,
        );
        await s.localStore.write(
          _utf8(localText),
          'blob-local',
          vaultId: _vaultId,
        );

        final remoteChange = s.graph.getNodeData('c-remote') as ChangeRecord;
        final resolution = await s.makeResolver().call(
          s.fileNode,
          s.localNode,
          [remoteChange],
        );

        expect(resolution.newLocalRecords, isEmpty);
        expect(resolution.recordsForDisk, contains(remoteChange));
      },
    );

    test(
      'dmp fails → LWW local wins when local.createdAt > remote.createdAt',
      () async {
        final s = _buildScenario(
          filePath: 'doc.md',
          baseBlob: _utf8(baseText),
          localBlob: _utf8(localText),
          remoteBlob: _utf8(remoteText),
          tempDir: tempDir,
          localCreatedAt: DateTime(2024, 1, 1, 0, 0, 9),
          remoteCreatedAt: DateTime(2024, 1, 1, 0, 0, 1),
        );

        await s.localStore.write(
          _utf8(baseText),
          'blob-base',
          vaultId: _vaultId,
        );
        await s.localStore.write(
          _utf8(localText),
          'blob-local',
          vaultId: _vaultId,
        );

        final remoteChange = s.graph.getNodeData('c-remote') as ChangeRecord;
        final resolution = await s.makeResolver().call(
          s.fileNode,
          s.localNode,
          [remoteChange],
        );

        expect(resolution.newLocalRecords, hasLength(1));
        final resRec = resolution.newLocalRecords.first as ChangeRecord;
        expect(resRec.blobId, equals('blob-local'));
        expect(resRec.parentKey, equals('c-remote'));
        expect(resRec.isSynced, isFalse);

        // Local branch pruned
        expect(s.graph.containsNode('c-local'), isFalse);
      },
    );

    test('dmp fails → conflictCopy creates copy with remote content', () async {
      final s = _buildScenario(
        filePath: 'report.md',
        baseBlob: _utf8(baseText),
        localBlob: _utf8(localText),
        remoteBlob: _utf8(remoteText),
        tempDir: tempDir,
        strategy: ConflictStrategy.conflictCopy,
      );

      await s.localStore.write(_utf8(baseText), 'blob-base', vaultId: _vaultId);
      await s.localStore.write(
        _utf8(localText),
        'blob-local',
        vaultId: _vaultId,
      );

      final remoteChange = s.graph.getNodeData('c-remote') as ChangeRecord;
      final resolution = await s
          .makeResolver(ConflictStrategy.conflictCopy)
          .call(s.fileNode, s.localNode, [remoteChange]);

      expect(resolution.newLocalRecords, hasLength(2));
      final cfFile = resolution.newLocalRecords[0] as FileRecord;
      expect(cfFile.path, contains('conflict copy'));
      expect(cfFile.path, endsWith('.md'));
      final cfDisk = File('${tempDir.path}/${cfFile.path}');
      expect(cfDisk.existsSync(), isTrue);
      expect(utf8.decode(cfDisk.readAsBytesSync()), equals(remoteText));
    });
  });

  // ------------------------------------------------------------------
  // Multi-hop remote chain
  //
  // Bob made two changes: c_remote_1 → c_remote_2.
  // pulledRecords contains both. We must resolve against c_remote_2
  // (the leaf), not c_remote_1.
  // ------------------------------------------------------------------

  group('multi-hop remote chain', () {
    const baseText = 'Line 1\nLine 2\nLine 3\n';
    const localText = 'Line 1 [LOCAL]\nLine 2\nLine 3\n';
    const remote1Text = 'Line 1\nLine 2 [REMOTE-1]\nLine 3\n';
    const remote2Text = 'Line 1\nLine 2 [REMOTE-2]\nLine 3\n';

    test('merges against remote chain leaf, not first pulled record', () async {
      final t0 = DateTime(2024, 1, 1);

      final vaultNode = VaultNode('vault');
      final fileNode = FileNode('file-node');
      final cBase = ChangeNode('c-base');
      final cLocal = ChangeNode('c-local');
      final cRemote1 = ChangeNode('c-remote-1');
      final cRemote2 = ChangeNode('c-remote-2');

      final graph = Graph<NodeRecord>(root: vaultNode);
      for (final n in [fileNode, cBase, cLocal, cRemote1, cRemote2]) {
        graph.addNode(n);
      }
      graph.addEdge(vaultNode, fileNode);
      graph.addEdge(fileNode, cBase);
      graph.addEdge(cBase, cLocal);
      graph.addEdge(cBase, cRemote1); // fork
      graph.addEdge(cRemote1, cRemote2); // chain

      graph.updateNodeData(
        'vault',
        VaultRecord(
          key: 'vault',
          vaultId: _vaultId,
          isSynced: true,
          createdAt: t0,
          name: 'T',
        ),
      );
      graph.updateNodeData(
        'file-node',
        FileRecord(
          key: 'file-node',
          vaultId: _vaultId,
          parentKey: 'vault',
          isSynced: true,
          createdAt: t0,
          fileId: _fileId,
          path: 'doc.md',
        ),
      );
      graph.updateNodeData(
        'c-base',
        ChangeRecord(
          key: 'c-base',
          vaultId: _vaultId,
          parentKey: 'file-node',
          isSynced: true,
          createdAt: t0.add(Duration(seconds: 1)),
          fileId: _fileId,
          blobId: 'blob-base',
          sizeBytes: _utf8(baseText).length,
        ),
      );
      graph.updateNodeData(
        'c-local',
        ChangeRecord(
          key: 'c-local',
          vaultId: _vaultId,
          parentKey: 'c-base',
          isSynced: false,
          createdAt: t0.add(Duration(seconds: 2)),
          fileId: _fileId,
          blobId: 'blob-local',
          sizeBytes: _utf8(localText).length,
        ),
      );
      graph.updateNodeData(
        'c-remote-1',
        ChangeRecord(
          key: 'c-remote-1',
          vaultId: _vaultId,
          parentKey: 'c-base',
          isSynced: true,
          createdAt: t0.add(Duration(seconds: 3)),
          fileId: _fileId,
          blobId: 'blob-remote-1',
          sizeBytes: _utf8(remote1Text).length,
        ),
      );
      graph.updateNodeData(
        'c-remote-2',
        ChangeRecord(
          key: 'c-remote-2',
          vaultId: _vaultId,
          parentKey: 'c-remote-1',
          isSynced: true,
          createdAt: t0.add(Duration(seconds: 4)),
          fileId: _fileId,
          blobId: 'blob-remote-2',
          sizeBytes: _utf8(remote2Text).length,
        ),
      );

      final registry = FileRegistry()..register('doc.md', _fileId, 'file-node');
      final localStore = LocalBlobStore(InMemoryBlobRepository());
      await localStore.write(_utf8(baseText), 'blob-base', vaultId: _vaultId);
      await localStore.write(_utf8(localText), 'blob-local', vaultId: _vaultId);

      final remoteStorage = _RemoteStorage()
        ..seed('blob-remote-1', _utf8(remote1Text))
        ..seed('blob-remote-2', _utf8(remote2Text));

      final resolver = ConflictResolver(
        graph: graph,
        fileRegistry: registry,
        localBlobStore: localStore,
        remoteBlobStorage: remoteStorage,
        vaultPath: tempDir.path,
        vaultId: _vaultId,
        strategy: ConflictStrategy.lww,
        io: TestIO(),
      );

      final r1 = graph.getNodeData('c-remote-1') as ChangeRecord;
      final r2 = graph.getNodeData('c-remote-2') as ChangeRecord;
      final resolution = await resolver.call(fileNode, cLocal, [r1, r2]);

      // Resolution record must chain off the leaf (c-remote-2), not c-remote-1.
      expect(resolution.newLocalRecords, hasLength(1));
      final merged = resolution.newLocalRecords.first as ChangeRecord;
      expect(merged.parentKey, equals('c-remote-2'));

      // Content: Alice's edit + Bob's final state (REMOTE-2), not intermediate (REMOTE-1).
      final written = File('${tempDir.path}/doc.md').readAsStringSync();
      expect(written, contains('[LOCAL]'));
      expect(written, contains('[REMOTE-2]'));
      expect(written, isNot(contains('[REMOTE-1]')));
    });
  });

  // ------------------------------------------------------------------
  // Binary file (.bin) — skips text merge, goes directly to LWW
  // ------------------------------------------------------------------

  group('LWW strategy (binary .bin)', () {
    final baseBin = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF, 0x01]);
    final localBin = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF, 0x02]);
    final remoteBin = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF, 0x03]);

    test('remote wins when remote.createdAt > local.createdAt', () async {
      final s = _buildScenario(
        filePath: 'data.bin',
        baseBlob: baseBin,
        localBlob: localBin,
        remoteBlob: remoteBin,
        tempDir: tempDir,
        localCreatedAt: DateTime(2024, 1, 1, 0, 0, 1),
        remoteCreatedAt: DateTime(2024, 1, 1, 0, 0, 5),
      );

      await s.localStore.write(baseBin, 'blob-base', vaultId: _vaultId);
      await s.localStore.write(localBin, 'blob-local', vaultId: _vaultId);

      final remoteChange = s.graph.getNodeData('c-remote') as ChangeRecord;
      final resolution = await s.makeResolver().call(s.fileNode, s.localNode, [
        remoteChange,
      ]);

      // Remote wins: pulled records passed through unchanged, no new local records
      expect(resolution.newLocalRecords, isEmpty);
      expect(resolution.recordsForDisk, contains(remoteChange));

      // Local branch pruned: c-local must no longer exist in the graph
      expect(s.graph.containsNode('c-local'), isFalse);
    });

    test('local wins when local.createdAt > remote.createdAt', () async {
      final s = _buildScenario(
        filePath: 'data.bin',
        baseBlob: baseBin,
        localBlob: localBin,
        remoteBlob: remoteBin,
        tempDir: tempDir,
        localCreatedAt: DateTime(2024, 1, 1, 0, 0, 9),
        remoteCreatedAt: DateTime(2024, 1, 1, 0, 0, 3),
      );

      await s.localStore.write(baseBin, 'blob-base', vaultId: _vaultId);
      await s.localStore.write(localBin, 'blob-local', vaultId: _vaultId);

      final remoteChange = s.graph.getNodeData('c-remote') as ChangeRecord;
      final resolution = await s.makeResolver().call(s.fileNode, s.localNode, [
        remoteChange,
      ]);

      // Local wins: resolution record with local blobId chained on top of remote
      expect(resolution.newLocalRecords, hasLength(1));
      final resRec = resolution.newLocalRecords.first as ChangeRecord;
      expect(resRec.parentKey, equals('c-remote'));
      expect(resRec.blobId, equals('blob-local'));
      expect(resRec.isSynced, isFalse);

      // Local branch pruned
      expect(s.graph.containsNode('c-local'), isFalse);
    });

    test(
      'local wins: resolution node is added to graph as child of remoteNode',
      () async {
        final s = _buildScenario(
          filePath: 'data.bin',
          baseBlob: baseBin,
          localBlob: localBin,
          remoteBlob: remoteBin,
          tempDir: tempDir,
          localCreatedAt: DateTime(2024, 1, 1, 0, 0, 9),
          remoteCreatedAt: DateTime(2024, 1, 1, 0, 0, 3),
        );

        await s.localStore.write(baseBin, 'blob-base', vaultId: _vaultId);
        await s.localStore.write(localBin, 'blob-local', vaultId: _vaultId);

        final remoteChange = s.graph.getNodeData('c-remote') as ChangeRecord;
        final resolution = await s.makeResolver().call(
          s.fileNode,
          s.localNode,
          [remoteChange],
        );

        final resRec = resolution.newLocalRecords.first as ChangeRecord;
        final resNode = s.graph.getNodeByKey(resRec.key);
        expect(resNode, isNotNull);
        expect(s.graph.getNodeParent(resNode!)?.key, equals('c-remote'));
      },
    );

    test(
      'local wins: remote ChangeRecord excluded from recordsForDisk',
      () async {
        final s = _buildScenario(
          filePath: 'data.bin',
          baseBlob: baseBin,
          localBlob: localBin,
          remoteBlob: remoteBin,
          tempDir: tempDir,
          localCreatedAt: DateTime(2024, 1, 1, 0, 0, 9),
          remoteCreatedAt: DateTime(2024, 1, 1, 0, 0, 3),
        );

        await s.localStore.write(baseBin, 'blob-base', vaultId: _vaultId);
        await s.localStore.write(localBin, 'blob-local', vaultId: _vaultId);

        final remoteChange = s.graph.getNodeData('c-remote') as ChangeRecord;
        final resolution = await s.makeResolver().call(
          s.fileNode,
          s.localNode,
          [remoteChange],
        );

        expect(
          resolution.recordsForDisk.whereType<ChangeRecord>().where(
            (r) => r.key == 'c-remote',
          ),
          isEmpty,
        );
      },
    );
  });

  // ------------------------------------------------------------------
  // conflictCopy strategy (binary .bin)
  // ------------------------------------------------------------------

  group('conflictCopy strategy (binary .bin)', () {
    final baseBin = Uint8List.fromList([0x01, 0x02]);
    final localBin = Uint8List.fromList([0x01, 0x02, 0x03]);
    final remoteBin = Uint8List.fromList([0x01, 0x02, 0x04]);

    test('creates conflict copy file on disk with remote content', () async {
      final s = _buildScenario(
        filePath: 'file.bin',
        baseBlob: baseBin,
        localBlob: localBin,
        remoteBlob: remoteBin,
        tempDir: tempDir,
        strategy: ConflictStrategy.conflictCopy,
      );

      await s.localStore.write(baseBin, 'blob-base', vaultId: _vaultId);
      await s.localStore.write(localBin, 'blob-local', vaultId: _vaultId);

      final remoteChange = s.graph.getNodeData('c-remote') as ChangeRecord;
      final resolution = await s
          .makeResolver(ConflictStrategy.conflictCopy)
          .call(s.fileNode, s.localNode, [remoteChange]);

      expect(resolution.newLocalRecords, hasLength(2));

      final cfFile = resolution.newLocalRecords[0] as FileRecord;
      final cfChange = resolution.newLocalRecords[1] as ChangeRecord;

      expect(cfFile.path, contains('conflict copy'));
      expect(cfFile.path, endsWith('.bin'));

      final cfDisk = File('${tempDir.path}/${cfFile.path}');
      expect(cfDisk.existsSync(), isTrue);
      expect(cfDisk.readAsBytesSync(), equals(remoteBin));

      expect(cfChange.blobId, equals(remoteChange.blobId));
    });

    test(
      'main file is NOT overwritten: remote ChangeRecord excluded from recordsForDisk',
      () async {
        final s = _buildScenario(
          filePath: 'file.bin',
          baseBlob: baseBin,
          localBlob: localBin,
          remoteBlob: remoteBin,
          tempDir: tempDir,
          strategy: ConflictStrategy.conflictCopy,
        );

        await s.localStore.write(baseBin, 'blob-base', vaultId: _vaultId);
        await s.localStore.write(localBin, 'blob-local', vaultId: _vaultId);

        final remoteChange = s.graph.getNodeData('c-remote') as ChangeRecord;
        final resolution = await s
            .makeResolver(ConflictStrategy.conflictCopy)
            .call(s.fileNode, s.localNode, [remoteChange]);

        expect(
          resolution.recordsForDisk.whereType<ChangeRecord>().where(
            (r) => r.fileId == _fileId,
          ),
          isEmpty,
        );
      },
    );

    test('conflict copy records are added to graph and registry', () async {
      final s = _buildScenario(
        filePath: 'file.bin',
        baseBlob: baseBin,
        localBlob: localBin,
        remoteBlob: remoteBin,
        tempDir: tempDir,
        strategy: ConflictStrategy.conflictCopy,
      );

      await s.localStore.write(baseBin, 'blob-base', vaultId: _vaultId);
      await s.localStore.write(localBin, 'blob-local', vaultId: _vaultId);

      final remoteChange = s.graph.getNodeData('c-remote') as ChangeRecord;
      final resolution = await s
          .makeResolver(ConflictStrategy.conflictCopy)
          .call(s.fileNode, s.localNode, [remoteChange]);

      final cfFile = resolution.newLocalRecords[0] as FileRecord;
      final cfChange = resolution.newLocalRecords[1] as ChangeRecord;

      // Both nodes in the graph
      expect(s.graph.getNodeByKey(cfFile.key), isNotNull);
      expect(s.graph.getNodeByKey(cfChange.key), isNotNull);

      // ChangeRecord is child of FileRecord
      expect(cfChange.parentKey, equals(cfFile.key));

      // FileRecord registered in registry
      expect(s.registry.pathByFileId(cfFile.fileId), equals(cfFile.path));
    });

    test(
      'conflict copy path follows "name (conflict copy DATE).ext" pattern',
      () async {
        final s = _buildScenario(
          filePath: 'archive/data.bin',
          baseBlob: baseBin,
          localBlob: localBin,
          remoteBlob: remoteBin,
          tempDir: tempDir,
          strategy: ConflictStrategy.conflictCopy,
        );

        await s.localStore.write(baseBin, 'blob-base', vaultId: _vaultId);
        await s.localStore.write(localBin, 'blob-local', vaultId: _vaultId);
        Directory('${tempDir.path}/archive').createSync();

        final remoteChange = s.graph.getNodeData('c-remote') as ChangeRecord;
        final resolution = await s
            .makeResolver(ConflictStrategy.conflictCopy)
            .call(s.fileNode, s.localNode, [remoteChange]);

        final cfFile = resolution.newLocalRecords[0] as FileRecord;
        expect(cfFile.path, startsWith('archive/'));
        expect(cfFile.path, contains('data (conflict copy '));
        expect(cfFile.path, endsWith('.bin'));
      },
    );
  });
}
