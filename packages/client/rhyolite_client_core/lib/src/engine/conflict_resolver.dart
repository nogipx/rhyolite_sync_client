import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:data_manage/data_manage.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:path/path.dart' as p;
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:uuid/uuid.dart';

import '../local/local_blob_store.dart';
import '../platform/i_platform_io.dart';
import 'file_registry.dart';
import 'vault_config.dart';

const _textExtensions = {
  'md', 'txt', 'dart', 'js', 'ts', 'jsx', 'tsx',
  'json', 'yaml', 'yml', 'toml', 'xml', 'html', 'htm',
  'css', 'scss', 'sass', 'sh', 'bash', 'zsh',
  'py', 'rb', 'go', 'rs', 'java', 'kt', 'swift',
  'c', 'cpp', 'h', 'hpp', 'cs', 'ini', 'conf',
  'properties', 'env', 'csv', 'sql', 'graphql', 'proto',
};

class ConflictResolution {
  const ConflictResolution({
    required this.recordsForDisk,
    required this.newLocalRecords,
  });

  final List<NodeRecord> recordsForDisk;
  final List<NodeRecord> newLocalRecords;
}

class ConflictResolver {
  ConflictResolver({
    required this.graph,
    required this.fileRegistry,
    required this.localBlobStore,
    required this.remoteBlobStorage,
    required this.vaultPath,
    required this.vaultId,
    required this.strategy,
    required this.io,
  });

  final IGraphEditable<NodeRecord> graph;
  final FileRegistry fileRegistry;
  final LocalBlobStore localBlobStore;
  final IBlobStorage remoteBlobStorage;
  final String vaultPath;
  final String vaultId;
  final ConflictStrategy strategy;
  final IPlatformIO io;

  Future<ConflictResolution> call(
    Node fileNode,
    Node localLeafBeforePull,
    List<NodeRecord> pulledRecords,
  ) async {
    final localRecord = graph.getNodeData(localLeafBeforePull.key);

    // Local delete vs remote delete — both agree, mark local as synced and skip.
    if (localRecord is DeleteRecord && !localRecord.isSynced) {
      final remoteAlsoDeleted = pulledRecords.any(
        (r) => r is DeleteRecord && r.fileId == localRecord.fileId,
      );
      if (remoteAlsoDeleted) {
        final synced = localRecord.withSynced();
        graph.updateNodeData(localRecord.key, synced);
        return ConflictResolution(recordsForDisk: [], newLocalRecords: [synced]);
      }
    }

    if (localRecord is! ChangeRecord || localRecord.isSynced) {
      return ConflictResolution(recordsForDisk: pulledRecords, newLocalRecords: []);
    }

    final fileRecord = graph.getNodeData(fileNode.key);
    if (fileRecord is! FileRecord) {
      return ConflictResolution(recordsForDisk: pulledRecords, newLocalRecords: []);
    }

    final localChange = localRecord;

    // Find the root of the remote branch: pulled ChangeRecord for this file
    // whose parentKey is not itself in the pulled set.
    final pulledKeys = pulledRecords.map((r) => r.key).toSet();
    final remoteChangeRecords = pulledRecords
        .whereType<ChangeRecord>()
        .where((r) => r.fileId == fileRecord.fileId)
        .toList();

    if (remoteChangeRecords.isEmpty) {
      return ConflictResolution(recordsForDisk: pulledRecords, newLocalRecords: []);
    }

    final remoteRoot = remoteChangeRecords.firstWhere(
      (r) => !pulledKeys.contains(r.parentKey),
      orElse: () => remoteChangeRecords.first,
    );
    final remoteRootNode = graph.getNodeByKey(remoteRoot.key);
    if (remoteRootNode == null) {
      return ConflictResolution(recordsForDisk: pulledRecords, newLocalRecords: []);
    }

    // Walk to the actual leaf of the remote branch.
    final remoteLeafNode = graph.findLeaf(remoteRootNode);
    final remoteChange = graph.getNodeData(remoteLeafNode.key);
    if (remoteChange is! ChangeRecord) {
      return ConflictResolution(recordsForDisk: pulledRecords, newLocalRecords: []);
    }

    return _resolve(fileRecord, localChange, remoteChange, pulledRecords);
  }

  Future<ConflictResolution> _resolve(
    FileRecord fileRecord,
    ChangeRecord localChange,
    ChangeRecord remoteChange,
    List<NodeRecord> pulledRecords,
  ) async {
    final relativePath = fileRegistry.pathByFileId(fileRecord.fileId);
    if (relativePath == null) {
      return ConflictResolution(recordsForDisk: pulledRecords, newLocalRecords: []);
    }

    final ext = p.extension(relativePath).replaceAll('.', '').toLowerCase();
    final isText = _textExtensions.contains(ext);

    if (isText) {
      final mergedText = await _tryTextMerge(localChange, remoteChange);
      if (mergedText != null) {
        return _applyCleanMerge(
          fileRecord, remoteChange, pulledRecords, mergedText, relativePath, localChange,
        );
      }
    }

    return _applyStrategy(fileRecord, localChange, remoteChange, pulledRecords, relativePath);
  }

  Future<String?> _tryTextMerge(
    ChangeRecord localChange,
    ChangeRecord remoteChange,
  ) async {
    try {
      final localBytes = await localBlobStore.read(localChange.blobId, vaultId: vaultId);
      if (localBytes == null) return null;

      final remoteMap = await remoteBlobStorage.download([remoteChange.blobId]);
      final remoteBytes = remoteMap[remoteChange.blobId];
      if (remoteBytes == null) return null;
      final localText = utf8.decode(localBytes, allowMalformed: true);
      final remoteText = utf8.decode(remoteBytes, allowMalformed: true);

      // Find base: walk up from localChange to the last synced ChangeRecord.
      String? baseText;
      Node? cur = graph.getNodeByKey(localChange.key);
      while (cur != null) {
        cur = graph.getNodeParent(cur);
        if (cur == null) break;
        final rec = graph.getNodeData(cur.key);
        if (rec is ChangeRecord && rec.isSynced) {
          final localBase = await localBlobStore.read(rec.blobId, vaultId: vaultId);
          final baseMap = localBase == null
              ? await remoteBlobStorage.download([rec.blobId])
              : null;
          final baseBytes = localBase ?? baseMap?[rec.blobId];
          if (baseBytes == null) break;
          baseText = utf8.decode(baseBytes, allowMalformed: true);
          break;
        }
      }

      // Apply remote diff on top of local text (2-way if no base, 3-way otherwise).
      final patches = patchMake(baseText ?? localText, b: remoteText);
      final result = patchApply(patches, localText);
      final applied = result[1] as List<bool>;
      if (applied.every((x) => x)) return result[0] as String;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<ConflictResolution> _applyCleanMerge(
    FileRecord fileRecord,
    ChangeRecord remoteChange,
    List<NodeRecord> pulledRecords,
    String mergedText,
    String relativePath,
    ChangeRecord localChange,
  ) async {
    final mergedBytes = Uint8List.fromList(utf8.encode(mergedText));
    final mergedBlobId = _sha256(mergedBytes);

    await localBlobStore.write(mergedBytes, mergedBlobId, vaultId: vaultId);

    await io.writeFile('$vaultPath/$relativePath', mergedBytes);

    final remoteNode = graph.getNodeByKey(remoteChange.key)!;
    final mergedRecord = ChangeRecord(
      key: const Uuid().v5(Namespace.url.value, '${remoteChange.key}:$mergedBlobId'),
      vaultId: vaultId,
      parentKey: remoteChange.key,
      isSynced: false,
      createdAt: DateTime.now(),
      fileId: fileRecord.fileId,
      blobId: mergedBlobId,
      sizeBytes: mergedBytes.length,
    );
    if (!graph.containsNode(mergedRecord.key)) {
      final mergedNode = ChangeNode(mergedRecord.key);
      graph.addNode(mergedNode);
      graph.addEdge(remoteNode, mergedNode);
      graph.updateNodeData(mergedRecord.key, mergedRecord);
    }
    _pruneLocalBranch(localChange);

    // Exclude conflicting ChangeRecord from disk writes (we already wrote merged).
    final recordsForDisk = pulledRecords
        .where((r) => !(r is ChangeRecord && r.fileId == fileRecord.fileId))
        .toList();

    return ConflictResolution(recordsForDisk: recordsForDisk, newLocalRecords: [mergedRecord]);
  }

  Future<ConflictResolution> _applyStrategy(
    FileRecord fileRecord,
    ChangeRecord localChange,
    ChangeRecord remoteChange,
    List<NodeRecord> pulledRecords,
    String relativePath,
  ) async {
    switch (strategy) {
      case ConflictStrategy.lww:
        return _applyLww(fileRecord, localChange, remoteChange, pulledRecords);
      case ConflictStrategy.conflictCopy:
        return _applyConflictCopy(fileRecord, remoteChange, pulledRecords, relativePath);
    }
  }

  Future<ConflictResolution> _applyLww(
    FileRecord fileRecord,
    ChangeRecord localChange,
    ChangeRecord remoteChange,
    List<NodeRecord> pulledRecords,
  ) async {
    final remoteMs = remoteChange.serverTimestampMs ??
        remoteChange.createdAt.millisecondsSinceEpoch;
    final localMs = localChange.serverTimestampMs ??
        localChange.createdAt.millisecondsSinceEpoch;
    if (remoteMs > localMs) {
      // Remote wins — prune local branch and write remote content to disk normally.
      _pruneLocalBranch(localChange);
      return ConflictResolution(recordsForDisk: pulledRecords, newLocalRecords: []);
    }

    // Local wins — keep local on disk, create a resolution record on top of remote.
    final remoteNode = graph.getNodeByKey(remoteChange.key)!;
    final resolutionRecord = ChangeRecord(
      key: const Uuid().v5(Namespace.url.value, '${remoteChange.key}:${localChange.blobId}'),
      vaultId: vaultId,
      parentKey: remoteChange.key,
      isSynced: false,
      createdAt: DateTime.now(),
      fileId: fileRecord.fileId,
      blobId: localChange.blobId,
      sizeBytes: localChange.sizeBytes,
    );
    if (!graph.containsNode(resolutionRecord.key)) {
      final resolutionNode = ChangeNode(resolutionRecord.key);
      graph.addNode(resolutionNode);
      graph.addEdge(remoteNode, resolutionNode);
      graph.updateNodeData(resolutionRecord.key, resolutionRecord);
    }
    _pruneLocalBranch(localChange);

    final recordsForDisk = pulledRecords
        .where((r) => !(r is ChangeRecord && r.fileId == fileRecord.fileId))
        .toList();

    return ConflictResolution(recordsForDisk: recordsForDisk, newLocalRecords: [resolutionRecord]);
  }

  Future<ConflictResolution> _applyConflictCopy(
    FileRecord fileRecord,
    ChangeRecord remoteChange,
    List<NodeRecord> pulledRecords,
    String relativePath,
  ) async {
    final remoteMap = await remoteBlobStorage.download([remoteChange.blobId]);
    final remoteBytes = remoteMap[remoteChange.blobId];
    if (remoteBytes == null) {
      return ConflictResolution(recordsForDisk: pulledRecords, newLocalRecords: []);
    }

    final dir = p.dirname(relativePath);
    final basename = p.basenameWithoutExtension(relativePath);
    final ext = p.extension(relativePath);
    final date = DateTime.now().toIso8601String().split('T').first;
    final conflictName = '$basename (conflict copy $date)$ext';
    final conflictRelPath = dir == '.' ? conflictName : '$dir/$conflictName';
    final conflictFullPath = '$vaultPath/$conflictRelPath';

    await io.writeFile(conflictFullPath, remoteBytes);
    await localBlobStore.write(remoteBytes, remoteChange.blobId, vaultId: vaultId);

    final now = DateTime.now();
    final conflictFileId = const Uuid().v4();
    final conflictFileNodeKey = const Uuid().v4();

    final conflictFileRecord = FileRecord(
      key: conflictFileNodeKey,
      vaultId: vaultId,
      parentKey: graph.root.key,
      isSynced: false,
      createdAt: now,
      fileId: conflictFileId,
      path: conflictRelPath,
    );

    final conflictFileNode = FileNode(conflictFileNodeKey);
    graph.addNode(conflictFileNode);
    graph.addEdge(graph.root, conflictFileNode);
    graph.updateNodeData(conflictFileNodeKey, conflictFileRecord);
    fileRegistry.register(conflictRelPath, conflictFileId, conflictFileNodeKey);

    final conflictChangeRecord = ChangeRecord(
      key: const Uuid().v4(),
      vaultId: vaultId,
      parentKey: conflictFileNodeKey,
      isSynced: false,
      createdAt: now,
      fileId: conflictFileId,
      blobId: remoteChange.blobId,
      sizeBytes: remoteBytes.length,
    );
    final conflictChangeNode = ChangeNode(conflictChangeRecord.key);
    graph.addNode(conflictChangeNode);
    graph.addEdge(conflictFileNode, conflictChangeNode);
    graph.updateNodeData(conflictChangeRecord.key, conflictChangeRecord);

    // Keep local on disk — exclude conflicting ChangeRecord from disk writes.
    final recordsForDisk = pulledRecords
        .where((r) => !(r is ChangeRecord && r.fileId == fileRecord.fileId))
        .toList();

    return ConflictResolution(
      recordsForDisk: recordsForDisk,
      newLocalRecords: [conflictFileRecord, conflictChangeRecord],
    );
  }

  /// Detaches the losing local branch from the graph by removing the edge
  /// between the first synced ancestor and the first unsynced node.
  /// The detached subtree becomes orphaned and will be removed by GC.
  void _pruneLocalBranch(ChangeRecord localChange) {
    // Walk up to find the bottom-most unsynced node and its synced parent.
    Node? node = graph.getNodeByKey(localChange.key);
    Node? firstUnsynced;
    while (node != null) {
      final record = graph.getNodeData(node.key);
      if (record is! ChangeRecord || record.isSynced) break;
      firstUnsynced = node;
      node = graph.getNodeParent(node);
    }
    // node is now the synced ancestor; firstUnsynced is the branch root.
    if (node != null && firstUnsynced != null) {
      graph.removeEdge(node, firstUnsynced);
      GraphGCUseCase(graph).call().apply(graph);
    }
  }

  String _sha256(Uint8List bytes) => crypto.sha256.convert(bytes).toString();
}
