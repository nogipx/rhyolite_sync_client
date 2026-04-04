import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:uuid/uuid.dart';

import '../changes/file_change_event.dart';
import '../changes/i_change_provider.dart';
import '../local/local_blob_store.dart';
import '../local/local_node_store.dart';
import '../platform/i_platform_io.dart';
import 'file_registry.dart';
import 'sync_engine_event.dart';

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

class FileHandlerContext {
  FileHandlerContext({
    required this.graph,
    required this.fileRegistry,
    required this.pushUseCase,
    required this.nodeStore,
    required this.blobStore,
    required this.vaultPath,
    required this.vaultId,
    required this.io,
  });

  final IGraphEditable<NodeRecord> graph;
  final FileRegistry fileRegistry;
  final PushUseCase pushUseCase;
  final LocalNodeStore nodeStore;
  final LocalBlobStore blobStore;
  final String vaultPath;
  final String vaultId;
  final IPlatformIO io;
}

// ---------------------------------------------------------------------------
// Callable handlers
// ---------------------------------------------------------------------------

class HandleFileCreated {
  const HandleFileCreated(this.ctx, this.emit);

  final FileHandlerContext ctx;
  final void Function(SyncEngineEvent) emit;

  Future<void> call(String relativePath) async {
    emit(SyncFileCreated(relativePath));
    if (ctx.fileRegistry.fileIdByPath(relativePath) != null) {
      return HandleFileModified(ctx, emit).call(relativePath);
    }
    if (!await ctx.io.fileExists('${ctx.vaultPath}/$relativePath')) return;

    final fileId = _deterministicFileId(relativePath, ctx.vaultId);
    final fileNodeKey = fileId;

    // Node exists (previously deleted) — re-register and push ChangeRecord.
    if (ctx.graph.getNodeByKey(fileNodeKey) != null) {
      ctx.fileRegistry.register(relativePath, fileId, fileNodeKey);
      final fileNode = ctx.graph.getNodeByKey(fileNodeKey)!;
      final bytes = await ctx.io.readFile('${ctx.vaultPath}/$relativePath');
      final blobId = _sha256(bytes);
      await ctx.blobStore.write(bytes, blobId, vaultId: ctx.vaultId);
      final changeRecord = RecordChangeUseCase(ctx.graph)(fileNode, blobId, bytes.length);
      await ctx.nodeStore.save(changeRecord);
      await _pushAndSync(fileNode, relativePath);
      return;
    }

    final now = DateTime.now();
    final fileRecord = FileRecord(
      key: fileNodeKey,
      vaultId: ctx.vaultId,
      parentKey: ctx.graph.root.key,
      isSynced: false,
      createdAt: now,
      fileId: fileId,
      path: relativePath,
    );

    final fileNode = FileNode(fileNodeKey);
    ctx.graph.addNode(fileNode);
    ctx.graph.addEdge(ctx.graph.root, fileNode);
    ctx.graph.updateNodeData(fileNodeKey, fileRecord);
    ctx.fileRegistry.register(relativePath, fileId, fileNodeKey);

    final bytes = await ctx.io.readFile('${ctx.vaultPath}/$relativePath');
    final blobId = _sha256(bytes);
    await ctx.blobStore.write(bytes, blobId, vaultId: ctx.vaultId);
    final changeRecord = RecordChangeUseCase(ctx.graph)(fileNode, blobId, bytes.length);
    await ctx.nodeStore.saveAll([fileRecord, changeRecord]);
    await _pushAndSync(fileNode, relativePath);
  }

  Future<void> _pushAndSync(Node fileNode, String path) async {
    try {
      await ctx.pushUseCase.call([fileNode]);
      emit(SyncFilePushed(path));
      await _markSynced(ctx, _collectSynced(ctx.graph, fileNode));
    } catch (e) {
      emit(SyncError('Push failed for $path: $e'));
    }
  }
}

class HandleFileModified {
  const HandleFileModified(this.ctx, this.emit);

  final FileHandlerContext ctx;
  final void Function(SyncEngineEvent) emit;

  Future<void> call(String relativePath) async {
    emit(SyncFileModified(relativePath));
    final fileId = ctx.fileRegistry.fileIdByPath(relativePath);
    if (fileId == null) return;

    final nodeKey = ctx.fileRegistry.nodeKeyByFileId(fileId);
    if (nodeKey == null) return;
    final fileNode = ctx.graph.getNodeByKey(nodeKey);
    if (fileNode == null) return;

    final leaf = ctx.graph.findLeaf(fileNode);
    final leafRecord = ctx.graph.getNodeData(leaf.key);
    if (leafRecord is DeleteRecord) return;
    if (!await ctx.io.fileExists('${ctx.vaultPath}/$relativePath')) return;

    final bytes = await ctx.io.readFile('${ctx.vaultPath}/$relativePath');
    final currentBlobId = _sha256(bytes);

    final lastBlobId = leafRecord is ChangeRecord ? leafRecord.blobId : null;
    if (currentBlobId == lastBlobId) return;

    await ctx.blobStore.write(bytes, currentBlobId, vaultId: ctx.vaultId);
    final changeRecord = RecordChangeUseCase(ctx.graph)(fileNode, currentBlobId, bytes.length);
    await ctx.nodeStore.save(changeRecord);

    try {
      await ctx.pushUseCase.call([fileNode]);
      emit(SyncFilePushed(relativePath));
      await _markSynced(ctx, _collectSynced(ctx.graph, fileNode));
    } catch (e) {
      emit(SyncError('Push failed for $relativePath: $e'));
    }
  }
}

class HandleFileMoved {
  const HandleFileMoved(this.ctx, this.emit);

  final FileHandlerContext ctx;
  final void Function(SyncEngineEvent) emit;

  Future<void> call(String fromPath, String toPath) async {
    emit(SyncFileMoved(fromPath: fromPath, toPath: toPath));
    final fileId = ctx.fileRegistry.fileIdByPath(fromPath);
    if (fileId == null) return;

    final nodeKey = ctx.fileRegistry.nodeKeyByFileId(fileId);
    if (nodeKey == null) return;
    final fileNode = ctx.graph.getNodeByKey(nodeKey);
    if (fileNode == null) return;

    final moveRecord = RecordMoveUseCase(ctx.graph)(fileNode, fromPath, toPath);
    ctx.fileRegistry.updatePath(fromPath, toPath);
    await ctx.nodeStore.save(moveRecord);

    try {
      await ctx.pushUseCase.call([fileNode]);
      emit(SyncFilePushed(toPath));
      await _markSynced(ctx, _collectSynced(ctx.graph, fileNode));
    } catch (e) {
      emit(SyncError('Push failed for move $fromPath→$toPath: $e'));
    }
  }
}

class HandleFileDeleted {
  const HandleFileDeleted(this.ctx, this.emit);

  final FileHandlerContext ctx;
  final void Function(SyncEngineEvent) emit;

  Future<void> call(String relativePath) async {
    emit(SyncFileDeleted(relativePath));
    final fileId = ctx.fileRegistry.fileIdByPath(relativePath);
    if (fileId == null) return;

    final nodeKey = ctx.fileRegistry.nodeKeyByFileId(fileId);
    if (nodeKey == null) return;
    final fileNode = ctx.graph.getNodeByKey(nodeKey);
    if (fileNode == null) return;

    final leaf = ctx.graph.findLeaf(fileNode);
    if (ctx.graph.getNodeData(leaf.key) is DeleteRecord) return;

    final deleteRecord = RecordDeleteUseCase(ctx.graph)(fileNode);
    ctx.fileRegistry.remove(relativePath);
    await ctx.nodeStore.save(deleteRecord);

    try {
      await ctx.pushUseCase.call([fileNode]);
      emit(SyncFilePushed(relativePath));
      await _markSynced(ctx, _collectSynced(ctx.graph, fileNode));
    } catch (e) {
      emit(SyncError('Push failed for delete $relativePath: $e'));
    }
  }
}

// ---------------------------------------------------------------------------
// FileEventHandler
// ---------------------------------------------------------------------------

class FileEventHandler {
  FileEventHandler({
    required this.vaultPath,
    required this.io,
    required this.changeProvider,
  });

  final String vaultPath;
  final IPlatformIO io;
  final IChangeProvider changeProvider;

  FileHandlerContext? _ctx;

  final _eventsController = StreamController<SyncEngineEvent>.broadcast();
  StreamSubscription<FileChangeEvent>? _changeSub;

  Stream<SyncEngineEvent> get events => _eventsController.stream;

  void updateContext(FileHandlerContext ctx) => _ctx = ctx;

  void start() {
    _changeSub?.cancel();
    _changeSub = changeProvider.changes.listen(_onChangeEvent);
  }

  Future<void> stop() async {
    await _changeSub?.cancel();
    _changeSub = null;
  }

  Future<void> dispose() async {
    await stop();
    await _eventsController.close();
  }

  void _emit(SyncEngineEvent event) {
    if (!_eventsController.isClosed) _eventsController.add(event);
  }

  void _onChangeEvent(FileChangeEvent event) async {
    final ctx = _ctx;
    if (ctx == null) return;

    switch (event) {
      case FileCreatedEvent(:final relativePath):
        if (ctx.fileRegistry.fileIdByPath(relativePath) != null) return;
        final fullPath = '$vaultPath/$relativePath';
        if (await io.dirExists(fullPath)) {
          _handleDirectoryCreated(relativePath, ctx);
        } else {
          await HandleFileCreated(ctx, _emit).call(relativePath);
        }

      case FileModifiedEvent(:final relativePath):
        if (ctx.fileRegistry.fileIdByPath(relativePath) == null) {
          await HandleFileCreated(ctx, _emit).call(relativePath);
        } else {
          await HandleFileModified(ctx, _emit).call(relativePath);
        }

      case FileMovedEvent(:final fromPath, :final toPath):
        await HandleFileMoved(ctx, _emit).call(fromPath, toPath);

      case FileDeletedEvent(:final relativePath):
        if (ctx.fileRegistry.fileIdByPath(relativePath) != null) {
          await HandleFileDeleted(ctx, _emit).call(relativePath);
        } else {
          _handleDirectoryDeleted(relativePath, ctx);
        }
    }
  }

  void _handleDirectoryCreated(String relDir, FileHandlerContext ctx) {
    Timer(const Duration(milliseconds: 600), () async {
      if (!await io.dirExists('$vaultPath/$relDir')) return;
      for (final absPath in await io.listFiles('$vaultPath/$relDir')) {
        final rel = absPath.substring('$vaultPath/'.length);
        if (ctx.fileRegistry.fileIdByPath(rel) == null) {
          await HandleFileCreated(ctx, _emit).call(rel);
        }
      }
    });
  }

  void _handleDirectoryDeleted(String relPrefix, FileHandlerContext ctx) {
    final prefix = relPrefix.endsWith('/') ? relPrefix : '$relPrefix/';
    final paths = ctx.fileRegistry.pathToFileId.keys
        .where((p) => p.startsWith(prefix))
        .toList();
    for (final path in paths) {
      HandleFileDeleted(ctx, _emit).call(path);
    }
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

List<NodeRecord> _collectSynced(IGraph<NodeRecord> graph, Node fileNode) {
  final result = <NodeRecord>[];
  var current = graph.findLeaf(fileNode);
  while (true) {
    final record = graph.getNodeData(current.key);
    if (record == null) break;
    if (record.isSynced) result.add(record);
    final parent = graph.getNodeParent(current);
    if (parent == null) break;
    current = parent;
  }
  return result;
}

Future<void> _markSynced(FileHandlerContext ctx, List<NodeRecord> nodes) async {
  for (final node in nodes) {
    if (node.isSynced) {
      await ctx.nodeStore.markSynced(node.key, vaultId: ctx.vaultId);
    }
  }
}

String _sha256(Uint8List bytes) => sha256.convert(bytes).toString();

String _deterministicFileId(String relativePath, String vaultId) =>
    const Uuid().v5(vaultId, relativePath);
