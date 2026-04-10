import 'dart:io';
import 'dart:typed_data';

import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_client_core/src/engine/file_registry.dart';
import 'package:rhyolite_client_core/src/engine/startup_reconciler.dart';
import 'package:rhyolite_client_core/src/local/file_stat_cache.dart';
import 'package:rhyolite_client_core/src/local/local_blob_store.dart';
import 'package:rhyolite_client_core/src/platform/i_platform_io.dart'
    show FileStatInfo;
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:rpc_blob/rpc_blob.dart';
import 'package:rpc_data/rpc_data.dart';
import 'package:test/test.dart';

import 'helpers/test_io.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Must be a valid UUID — used as namespace for Uuid.v5 in StartupReconciler.
const _vaultId = '550e8400-e29b-41d4-a716-446655440000';


Graph<NodeRecord> _emptyGraph(String vaultId) {
  final vault = VaultNode(vaultId);
  final g = Graph<NodeRecord>(root: vault);
  g.updateNodeData(
    vaultId,
    VaultRecord(
      key: vaultId,
      vaultId: vaultId,
      isSynced: false,
      createdAt: DateTime.now(),
      name: 'Test',
    ),
  );
  return g;
}

// ---------------------------------------------------------------------------
// Instrumented IO that counts reads and allows stat overrides
// ---------------------------------------------------------------------------

class _InstrumentedIO extends TestIO {
  int readCount = 0;
  final Map<String, FileStatInfo> _statOverrides = {};

  void overrideStat(String absolutePath, FileStatInfo stat) {
    _statOverrides[absolutePath] = stat;
  }

  @override
  Future<Uint8List> readFile(String path) async {
    readCount++;
    return super.readFile(path);
  }

  @override
  Future<FileStatInfo?> statFile(String path) async {
    if (_statOverrides.containsKey(path)) return _statOverrides[path];
    return super.statFile(path);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Directory tmpDir;
  late _InstrumentedIO io;
  late LocalBlobStore blobStore;
  late InMemoryDataRepository dataRepo;
  late FileStatCache statCache;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('reconciler_test_');
    io = _InstrumentedIO();
    blobStore = LocalBlobStore(InMemoryBlobRepository());
    dataRepo = InMemoryDataRepository();
    statCache = FileStatCache(dataRepo, _vaultId);
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  // -------------------------------------------------------------------------
  // Phase A — new files
  // -------------------------------------------------------------------------

  group('Phase A (new files)', () {
    test('creates FileRecord + ChangeRecord for a new file', () async {
      await File('${tmpDir.path}/note.md').writeAsString('hello');

      final graph = _emptyGraph(_vaultId);
      final registry = FileRegistry();
      final records = await StartupReconciler(
        graph: graph,
        fileRegistry: registry,
        localBlobStore: blobStore,
        vaultId: _vaultId,
        io: io,
      ).call(tmpDir.path).then((r) => r.newRecords);

      expect(records, hasLength(2)); // FileRecord + ChangeRecord
      expect(records.whereType<FileRecord>(), hasLength(1));
      expect(records.whereType<ChangeRecord>(), hasLength(1));
      expect(registry.fileIdByPath('note.md'), isNotNull);
    });

    test('ignores hidden files (dot-prefixed segments)', () async {
      await File('${tmpDir.path}/.obsidian/config')
          .create(recursive: true)
          .then((f) => f.writeAsBytes(Uint8List(0)));
      await File('${tmpDir.path}/visible.md').writeAsString('hi');

      final graph = _emptyGraph(_vaultId);
      final registry = FileRegistry();
      final records = await StartupReconciler(
        graph: graph,
        fileRegistry: registry,
        localBlobStore: blobStore,
        vaultId: _vaultId,
        io: io,
      ).call(tmpDir.path).then((r) => r.newRecords);

      // Only visible.md → FileRecord + ChangeRecord
      expect(records, hasLength(2));
      expect(registry.fileIdByPath('visible.md'), isNotNull);
      expect(registry.fileIdByPath('.obsidian/config'), isNull);
    });

    test('saves stat cache entry after processing new file', () async {
      await File('${tmpDir.path}/note.md').writeAsString('hello');

      final graph = _emptyGraph(_vaultId);
      final registry = FileRegistry();
      await StartupReconciler(
        graph: graph,
        fileRegistry: registry,
        localBlobStore: blobStore,
        vaultId: _vaultId,
        io: io,
        statCache: statCache,
      ).call(tmpDir.path).then((r) => r.newRecords);

      final cached = await statCache.get('note.md');
      expect(cached, isNotNull);
      expect(cached!.blobId, isNotEmpty);
      expect(cached.sizeBytes, greaterThan(0));
    });
  });

  // -------------------------------------------------------------------------
  // Phase B — modified files
  // -------------------------------------------------------------------------

  group('Phase B (modified files)', () {
    test('detects content change and emits ChangeRecord', () async {
      final file = File('${tmpDir.path}/note.md');
      await file.writeAsString('v1');

      // First run: register the file.
      final graph = _emptyGraph(_vaultId);
      final registry = FileRegistry();
      await StartupReconciler(
        graph: graph,
        fileRegistry: registry,
        localBlobStore: blobStore,
        vaultId: _vaultId,
        io: io,
      ).call(tmpDir.path).then((r) => r.newRecords);

      // Modify the file.
      await file.writeAsString('v2');

      // Second run: should detect the change.
      final records2 = await StartupReconciler(
        graph: graph,
        fileRegistry: registry,
        localBlobStore: blobStore,
        vaultId: _vaultId,
        io: io,
      ).call(tmpDir.path).then((r) => r.newRecords);

      expect(records2.whereType<ChangeRecord>(), hasLength(1));
    });

    test('skips file read on stat cache hit (mtime+size match)', () async {
      final file = File('${tmpDir.path}/note.md');
      await file.writeAsString('hello');

      // First run — populates cache.
      final graph = _emptyGraph(_vaultId);
      final registry = FileRegistry();
      await StartupReconciler(
        graph: graph,
        fileRegistry: registry,
        localBlobStore: blobStore,
        vaultId: _vaultId,
        io: io,
        statCache: statCache,
      ).call(tmpDir.path).then((r) => r.newRecords);

      final readsAfterFirstRun = io.readCount;

      // Second run — file not changed, cache should match → no read in Phase B.
      final records2 = await StartupReconciler(
        graph: graph,
        fileRegistry: registry,
        localBlobStore: blobStore,
        vaultId: _vaultId,
        io: io,
        statCache: statCache,
      ).call(tmpDir.path).then((r) => r.newRecords);

      expect(records2.whereType<ChangeRecord>(), isEmpty);
      // Phase B should not have read the file again.
      expect(io.readCount, equals(readsAfterFirstRun),
          reason: 'stat cache hit should skip file read');
    });

    test('reads file when mtime changed (stat cache miss)', () async {
      final file = File('${tmpDir.path}/note.md');
      await file.writeAsString('v1');

      // First run.
      final graph = _emptyGraph(_vaultId);
      final registry = FileRegistry();
      await StartupReconciler(
        graph: graph,
        fileRegistry: registry,
        localBlobStore: blobStore,
        vaultId: _vaultId,
        io: io,
        statCache: statCache,
      ).call(tmpDir.path).then((r) => r.newRecords);

      final readsAfterFirstRun = io.readCount;

      // Overwrite with different content → new mtime.
      await file.writeAsString('v2');

      final records2 = await StartupReconciler(
        graph: graph,
        fileRegistry: registry,
        localBlobStore: blobStore,
        vaultId: _vaultId,
        io: io,
        statCache: statCache,
      ).call(tmpDir.path).then((r) => r.newRecords);

      expect(records2.whereType<ChangeRecord>(), hasLength(1));
      expect(io.readCount, greaterThan(readsAfterFirstRun),
          reason: 'file must be read when mtime changed');
    });

    test('no ChangeRecord when stat differs but content identical', () async {
      final file = File('${tmpDir.path}/note.md');
      await file.writeAsString('same');

      final graph = _emptyGraph(_vaultId);
      final registry = FileRegistry();
      await StartupReconciler(
        graph: graph,
        fileRegistry: registry,
        localBlobStore: blobStore,
        vaultId: _vaultId,
        io: io,
        statCache: statCache,
      ).call(tmpDir.path).then((r) => r.newRecords);

      // Simulate a stale stat: mtime differs but content is the same.
      final absolutePath = '${tmpDir.path}/note.md';
      io.overrideStat(
        absolutePath,
        const FileStatInfo(mtimeMs: 9999999, sizeBytes: 4),
      );

      final records2 = await StartupReconciler(
        graph: graph,
        fileRegistry: registry,
        localBlobStore: blobStore,
        vaultId: _vaultId,
        io: io,
        statCache: statCache,
      ).call(tmpDir.path).then((r) => r.newRecords);

      // Content identical → no ChangeRecord even though stat was stale.
      expect(records2.whereType<ChangeRecord>(), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Phase C — deleted files
  // -------------------------------------------------------------------------

  group('Phase C (deleted files)', () {
    test('emits DeleteRecord for file removed from disk', () async {
      final file = File('${tmpDir.path}/gone.md');
      await file.writeAsString('bye');

      final graph = _emptyGraph(_vaultId);
      final registry = FileRegistry();
      await StartupReconciler(
        graph: graph,
        fileRegistry: registry,
        localBlobStore: blobStore,
        vaultId: _vaultId,
        io: io,
      ).call(tmpDir.path).then((r) => r.newRecords);

      await file.delete();

      final records2 = await StartupReconciler(
        graph: graph,
        fileRegistry: registry,
        localBlobStore: blobStore,
        vaultId: _vaultId,
        io: io,
      ).call(tmpDir.path).then((r) => r.newRecords);

      expect(records2.whereType<DeleteRecord>(), hasLength(1));
      expect(registry.fileIdByPath('gone.md'), isNull);
    });

    test('removes stat cache entry on deletion', () async {
      final file = File('${tmpDir.path}/gone.md');
      await file.writeAsString('bye');

      final graph = _emptyGraph(_vaultId);
      final registry = FileRegistry();
      await StartupReconciler(
        graph: graph,
        fileRegistry: registry,
        localBlobStore: blobStore,
        vaultId: _vaultId,
        io: io,
        statCache: statCache,
      ).call(tmpDir.path).then((r) => r.newRecords);

      expect(await statCache.get('gone.md'), isNotNull);

      await file.delete();

      await StartupReconciler(
        graph: graph,
        fileRegistry: registry,
        localBlobStore: blobStore,
        vaultId: _vaultId,
        io: io,
        statCache: statCache,
      ).call(tmpDir.path).then((r) => r.newRecords);

      expect(await statCache.get('gone.md'), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Parallel I/O
  // -------------------------------------------------------------------------

  group('parallel I/O', () {
    test('processes multiple files correctly with concurrency=4', () async {
      // 20 files triggers multiple parallel batches (concurrency=4 → 5 batches).
      for (var i = 0; i < 20; i++) {
        await File('${tmpDir.path}/file_$i.md').writeAsString('content $i');
      }

      final graph = _emptyGraph(_vaultId);
      final registry = FileRegistry();
      final records = await StartupReconciler(
        graph: graph,
        fileRegistry: registry,
        localBlobStore: blobStore,
        vaultId: _vaultId,
        io: io,
        ioConcurrency: 4,
      ).call(tmpDir.path).then((r) => r.newRecords);

      // 20 files × (FileRecord + ChangeRecord) = 40 records.
      expect(records.whereType<FileRecord>(), hasLength(20));
      expect(records.whereType<ChangeRecord>(), hasLength(20));
      expect(registry.pathToFileId.length, equals(20));
    });

    test('concurrency=1 and concurrency=16 produce identical blob hashes',
        () async {
      for (var i = 0; i < 10; i++) {
        await File('${tmpDir.path}/f$i.md').writeAsString('data $i');
      }

      final graph1 = _emptyGraph(_vaultId);
      final registry1 = FileRegistry();
      final records1 = await StartupReconciler(
        graph: graph1,
        fileRegistry: registry1,
        localBlobStore: LocalBlobStore(InMemoryBlobRepository()),
        vaultId: _vaultId,
        io: _InstrumentedIO(),
        ioConcurrency: 1,
      ).call(tmpDir.path).then((r) => r.newRecords);

      final graph2 = _emptyGraph(_vaultId);
      final registry2 = FileRegistry();
      final records2 = await StartupReconciler(
        graph: graph2,
        fileRegistry: registry2,
        localBlobStore: LocalBlobStore(InMemoryBlobRepository()),
        vaultId: _vaultId,
        io: _InstrumentedIO(),
        ioConcurrency: 16,
      ).call(tmpDir.path).then((r) => r.newRecords);

      expect(records1.length, equals(records2.length));
      expect(
        records1.whereType<ChangeRecord>().map((r) => r.blobId).toSet(),
        equals(records2.whereType<ChangeRecord>().map((r) => r.blobId).toSet()),
      );
    });
  });
}
