import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:uuid/uuid.dart';

import '../local/file_stat_cache.dart';
import '../local/local_blob_store.dart';
import '../platform/i_platform_io.dart';
import 'file_registry.dart';

class StartupReconciler {
  const StartupReconciler({
    required this.graph,
    required this.fileRegistry,
    required this.localBlobStore,
    required this.vaultId,
    required this.io,
    this.statCache,
    this.ioConcurrency = 16,
  });

  final Graph<NodeRecord> graph;
  final FileRegistry fileRegistry;
  final LocalBlobStore localBlobStore;
  final String vaultId;
  final IPlatformIO io;

  /// Optional persistent stat cache. When provided, Phase B skips reading
  /// files whose mtime+size match the cached entry.
  final FileStatCache? statCache;

  /// Max number of concurrent file reads.
  final int ioConcurrency;

  Future<StartupResult> call(String vaultPath) async {
    final newRecords = <NodeRecord>[];

    newRecords.addAll(await _phaseA(vaultPath));
    newRecords.addAll(await _phaseB(vaultPath));
    newRecords.addAll(await _phaseC(vaultPath));

    final orphanedRecords = _pruneAllFiles();

    return StartupResult(newRecords: newRecords, orphanedRecords: orphanedRecords);
  }

  List<NodeRecord> _pruneAllFiles() {
    final orphaned = <NodeRecord>[];
    for (final entry in graph.nodeData.entries) {
      if (entry.value is! FileRecord) continue;
      final fileNode = graph.getNodeByKey(entry.key);
      if (fileNode != null) {
        orphaned.addAll(PruneLeafBranchesUseCase(graph).call(fileNode));
      }
    }
    return orphaned;
  }

  // Phase A: new files on disk not in registry — read in parallel.
  Future<List<NodeRecord>> _phaseA(String vaultPath) async {
    if (!await io.dirExists(vaultPath)) return [];

    final allFiles = (await io.listFiles(vaultPath))
        .where((f) => !_isHidden(f, vaultPath))
        .toList();

    final newPaths = allFiles
        .map((abs) => (abs: abs, rel: _toRelative(abs, vaultPath)))
        .where((f) => fileRegistry.fileIdByPath(f.rel) == null)
        .toList();

    // Read all new files in parallel, then mutate graph sequentially.
    final reads = await _parallel(
      newPaths.map((f) => () => _readFile(f.abs)).toList(),
      concurrency: ioConcurrency,
    );

    final records = <NodeRecord>[];
    for (var i = 0; i < newPaths.length; i++) {
      final relativePath = newPaths[i].rel;
      final absolutePath = newPaths[i].abs;
      final bytes = reads[i];
      final blobId = _sha256(bytes);
      final fileId = _deterministicFileId(vaultId, relativePath);
      final fileNodeKey = fileId;
      final now = DateTime.now();

      final fileRecord = FileRecord(
        key: fileNodeKey,
        vaultId: vaultId,
        parentKey: graph.root.key,
        isSynced: false,
        createdAt: now,
        fileId: fileId,
        path: relativePath,
      );

      if (graph.getNodeByKey(fileNodeKey) == null) {
        graph.apply([fileRecord]);
        records.add(fileRecord);
      }
      final existingFileNode = graph.getNodeByKey(fileNodeKey)!;

      await localBlobStore.write(bytes, blobId, vaultId: vaultId);
      final changeRecord =
          RecordChangeUseCase(graph)(existingFileNode, blobId, bytes.length);
      graph.apply([changeRecord]);

      fileRegistry.register(relativePath, fileId, fileNodeKey);
      records.add(changeRecord);

      // Persist stat so Phase B can skip this file on next start.
      final stat = await io.statFile(absolutePath);
      if (stat != null && statCache != null) {
        await statCache!.save(
          relativePath,
          CachedFileStat(
            mtimeMs: stat.mtimeMs,
            sizeBytes: stat.sizeBytes,
            blobId: blobId,
          ),
        );
      }
    }

    return records;
  }

  // Phase B: modified files (in registry, content changed) — stat cache + parallel reads.
  Future<List<NodeRecord>> _phaseB(String vaultPath) async {
    final entries = fileRegistry.pathToFileId.entries.toList();

    // Determine which files are candidates for reading (exist on disk, not deleted).
    final candidates = <({String rel, String abs, String fileId})>[];
    for (final entry in entries) {
      final rel = entry.key;
      final abs = '$vaultPath/$rel';
      if (!await io.fileExists(abs)) continue;

      final nodeKey = fileRegistry.nodeKeyByFileId(entry.value);
      if (nodeKey == null) continue;
      final fileNode = graph.getNodeByKey(nodeKey);
      if (fileNode == null) continue;
      final leaf = graph.findLeaf(fileNode);
      final leafRecord = graph.getNodeData(leaf.key);
      if (leafRecord is DeleteRecord) continue;

      candidates.add((rel: rel, abs: abs, fileId: entry.value));
    }

    // For each candidate: try stat cache first, read file only if changed.
    // Do stat checks in parallel, then reads only for dirty files.
    final statResults = await _parallel(
      candidates
          .map(
            (c) => () async {
              final stat = await io.statFile(c.abs);
              if (stat == null) return (c: c, stat: null, cached: null);
              final cached = await statCache?.get(c.rel);
              return (c: c, stat: stat, cached: cached);
            },
          )
          .toList(),
      concurrency: ioConcurrency,
    );

    // Split into cache-hits (skip) and dirty (need read).
    final dirty = <({String rel, String abs, String fileId})>[];
    final cacheHits = <({
      String rel,
      FileStatInfo stat,
      CachedFileStat cached,
    })>[];

    for (final r in statResults) {
      final stat = r.stat;
      final cached = r.cached;
      if (stat != null && cached != null && cached.matches(stat.mtimeMs, stat.sizeBytes)) {
        cacheHits.add((rel: r.c.rel, stat: stat, cached: cached));
      } else {
        dirty.add(r.c);
      }
    }

    // Read dirty files in parallel.
    final dirtyBytes = await _parallel(
      dirty.map((c) => () => _readFile(c.abs)).toList(),
      concurrency: ioConcurrency,
    );

    // Mutate graph sequentially for dirty files.
    final records = <NodeRecord>[];
    for (var i = 0; i < dirty.length; i++) {
      final c = dirty[i];
      final bytes = dirtyBytes[i];
      final currentBlobId = _sha256(bytes);

      final nodeKey = fileRegistry.nodeKeyByFileId(c.fileId);
      if (nodeKey == null) continue;
      final fileNode = graph.getNodeByKey(nodeKey);
      if (fileNode == null) continue;

      final leaf = graph.findLeaf(fileNode);
      final leafRecord = graph.getNodeData(leaf.key);
      String? lastBlobId;
      if (leafRecord is ChangeRecord) {
        lastBlobId = leafRecord.blobId;
      }

      if (lastBlobId == currentBlobId) {
        // Content unchanged (stat was stale or not available) — update cache only.
        final stat = await io.statFile(c.abs);
        if (stat != null && statCache != null) {
          await statCache!.save(
            c.rel,
            CachedFileStat(
              mtimeMs: stat.mtimeMs,
              sizeBytes: stat.sizeBytes,
              blobId: currentBlobId,
            ),
          );
        }
        continue;
      }

      await localBlobStore.write(bytes, currentBlobId, vaultId: vaultId);
      final changeRecord =
          RecordChangeUseCase(graph)(fileNode, currentBlobId, bytes.length);
      graph.apply([changeRecord]);
      records.add(changeRecord);

      final stat = await io.statFile(c.abs);
      if (stat != null && statCache != null) {
        await statCache!.save(
          c.rel,
          CachedFileStat(
            mtimeMs: stat.mtimeMs,
            sizeBytes: stat.sizeBytes,
            blobId: currentBlobId,
          ),
        );
      }
    }

    return records;
  }

  // Phase C: deleted files (in registry, not on disk).
  Future<List<NodeRecord>> _phaseC(String vaultPath) async {
    final records = <NodeRecord>[];
    final pathsToRemove = <String>[];

    for (final entry in fileRegistry.pathToFileId.entries) {
      final relativePath = entry.key;
      final fileId = entry.value;

      if (await io.fileExists('$vaultPath/$relativePath')) continue;

      final nodeKey = fileRegistry.nodeKeyByFileId(fileId);
      if (nodeKey == null) continue;
      final fileNode = graph.getNodeByKey(nodeKey);
      if (fileNode == null) continue;

      final leaf = graph.findLeaf(fileNode);
      if (graph.getNodeData(leaf.key) is DeleteRecord) continue;

      final deleteRecord = RecordDeleteUseCase(graph)(fileNode);
      graph.apply([deleteRecord]);
      records.add(deleteRecord);
      pathsToRemove.add(relativePath);
    }

    for (final path in pathsToRemove) {
      fileRegistry.remove(path);
      await statCache?.remove(path);
    }

    return records;
  }

  /// Runs [tasks] with at most [concurrency] running simultaneously.
  Future<List<T>> _parallel<T>(
    List<Future<T> Function()> tasks, {
    required int concurrency,
  }) async {
    if (tasks.isEmpty) return [];
    final results = List<T?>.filled(tasks.length, null);
    for (var i = 0; i < tasks.length; i += concurrency) {
      final chunk = tasks.skip(i).take(concurrency).toList();
      final chunkResults = await Future.wait(chunk.map((f) => f()));
      for (var j = 0; j < chunkResults.length; j++) {
        results[i + j] = chunkResults[j];
      }
    }
    return results.cast<T>();
  }

  Future<Uint8List> _readFile(String absolutePath) =>
      io.readFile(absolutePath);

  String _sha256(Uint8List bytes) => sha256.convert(bytes).toString();

  String _deterministicFileId(String vaultId, String relativePath) =>
      const Uuid().v5(vaultId, relativePath);

  String _toRelative(String absolute, String vaultPath) {
    final base = vaultPath.endsWith('/') ? vaultPath : '$vaultPath/';
    return absolute.startsWith(base) ? absolute.substring(base.length) : absolute;
  }

  bool _isHidden(String absolute, String vaultPath) {
    final relative = _toRelative(absolute, vaultPath);
    return relative.split('/').any((part) => part.startsWith('.'));
  }
}

class StartupResult {
  const StartupResult({required this.newRecords, required this.orphanedRecords});

  final List<NodeRecord> newRecords;
  final List<NodeRecord> orphanedRecords;
}
