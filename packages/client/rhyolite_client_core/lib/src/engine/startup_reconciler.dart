import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:uuid/uuid.dart';

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
  });

  final Graph<NodeRecord> graph;
  final FileRegistry fileRegistry;
  final LocalBlobStore localBlobStore;
  final String vaultId;
  final IPlatformIO io;

  Future<List<NodeRecord>> call(String vaultPath) async {
    final newRecords = <NodeRecord>[];

    newRecords.addAll(await _phaseA(vaultPath));
    newRecords.addAll(await _phaseB(vaultPath));
    newRecords.addAll(await _phaseC(vaultPath));

    return newRecords;
  }

  // Phase A: new files on disk not in registry
  Future<List<NodeRecord>> _phaseA(String vaultPath) async {
    final records = <NodeRecord>[];
    if (!await io.dirExists(vaultPath)) return records;

    final allFiles = (await io.listFiles(vaultPath)).where((f) => !_isHidden(f, vaultPath));

    for (final absolutePath in allFiles) {
      final relativePath = _toRelative(absolutePath, vaultPath);
      if (fileRegistry.fileIdByPath(relativePath) != null) continue;

      final bytes = await io.readFile(absolutePath);
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

      final fileNode = FileNode(fileNodeKey);
      if (graph.getNodeByKey(fileNodeKey) == null) {
        graph.addNode(fileNode);
        graph.addEdge(graph.root, fileNode);
        graph.updateNodeData(fileNodeKey, fileRecord);
        records.add(fileRecord);
      }
      final existingFileNode = graph.getNodeByKey(fileNodeKey)!;

      await localBlobStore.write(bytes, blobId, vaultId: vaultId);

      final changeRecord = RecordChangeUseCase(graph)(existingFileNode, blobId, bytes.length);

      fileRegistry.register(relativePath, fileId, fileNodeKey);
      records.add(changeRecord);
    }

    return records;
  }

  // Phase B: modified files (in registry, content changed)
  Future<List<NodeRecord>> _phaseB(String vaultPath) async {
    final records = <NodeRecord>[];

    for (final entry in fileRegistry.pathToFileId.entries) {
      final relativePath = entry.key;
      final fileId = entry.value;
      final fullPath = '$vaultPath/$relativePath';
      if (!await io.fileExists(fullPath)) continue;

      final nodeKey = fileRegistry.nodeKeyByFileId(fileId);
      if (nodeKey == null) continue;

      final fileNode = graph.getNodeByKey(nodeKey);
      if (fileNode == null) continue;

      var leaf = graph.findLeaf(fileNode);
      final leafRecord = graph.getNodeData(leaf.key);
      if (leafRecord is DeleteRecord) continue;

      String? lastBlobId;
      if (leafRecord is ChangeRecord) {
        lastBlobId = leafRecord.blobId;
      }

      final bytes = await io.readFile(fullPath);
      final currentBlobId = _sha256(bytes);

      if (lastBlobId == currentBlobId) continue;

      await localBlobStore.write(bytes, currentBlobId, vaultId: vaultId);
      final changeRecord = RecordChangeUseCase(graph)(fileNode, currentBlobId, bytes.length);
      records.add(changeRecord);
    }

    return records;
  }

  // Phase C: deleted files (in registry, not on disk)
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
      records.add(deleteRecord);
      pathsToRemove.add(relativePath);
    }

    for (final path in pathsToRemove) {
      fileRegistry.remove(path);
    }

    return records;
  }

  String _sha256(Uint8List bytes) => sha256.convert(bytes).toString();

  /// Deterministic fileId: same vaultId + path always produces the same UUID.
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
