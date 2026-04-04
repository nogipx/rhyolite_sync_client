import 'dart:async';

import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:rpc_dart/logger.dart';
import 'package:rpc_notify/rpc_notify.dart';

import '../changes/i_change_provider.dart';
import '../local/local_blob_storage_adapter.dart';
import '../local/local_blob_store.dart';
import '../local/local_node_store.dart';
import '../platform/i_platform_io.dart';
import '../remote/remote_blob_storage.dart';
import '../remote/remote_graph_server.dart';
import 'conflict_resolver.dart';
import 'connection_manager.dart';
import 'disk_applier.dart';
import 'file_event_handler.dart';
import 'file_registry.dart';
import 'graph_builder.dart';
import 'local_gc_use_case.dart';
import 'startup_reconciler.dart';
import 'sync_engine_event.dart';
import 'vault_config.dart';

final _logger = RpcLogger('rhyolite.sync_engine');

class SyncEngine {
  SyncEngine({
    required this.vaultPath,
    required this.serverUrl,
    required this.config,
    this.cipher,
    required this.nodeStore,
    required this.blobStore,
    required this.io,
    required this.changeProvider,
  });

  final String vaultPath;
  String serverUrl;
  VaultConfig config;
  IVaultCipher? cipher;

  /// PASERK k4.local-pw — only needed on first run to create the initial VaultRecord.
  /// After that, VaultRecord is pulled from the server.
  final LocalNodeStore nodeStore;
  final LocalBlobStore blobStore;
  final IPlatformIO io;
  final IChangeProvider changeProvider;

  late Graph<NodeRecord> _graph;
  late FileRegistry _fileRegistry;
  late PushUseCase _pushUseCase;
  late PullUseCase _pullUseCase;
  late DiskApplier _diskApplier;
  late ConflictResolver _conflictResolver;
  late RemoteGraphServer _remoteServer;
  late ConnectionManager _connectionManager;

  RemoteBlobStorage? _remoteBlobStorage;

  bool _isStopped = false;
  bool _isPulling = false;
  bool _started = false;

  bool get _isConnected => _started && _connectionManager.isConnected;

  NotifySubscriber? _notifySubscriber;
  StreamSubscription<NotifyEvent>? _notifySub;
  StreamSubscription<ConnectionEvent>? _connectionSub;
  StreamSubscription<SyncEngineEvent>? _fileEventSub;
  Timer? _pullDebounce;
  late FileEventHandler _fileEventHandler;

  final _eventsController = StreamController<SyncEngineEvent>.broadcast();

  Stream<SyncEngineEvent> get events => _eventsController.stream;

  IGraph<NodeRecord> get graph => _graph;

  Future<void> start() async {
    _isStopped = false;
    _log('Starting SyncEngine for vault: ${config.vaultId}');

    // Phase 1: Offline-safe — always runs, no network required.

    // 1. Reconstruct graph from local SQLite.
    final records = await nodeStore.loadAll(vaultId: config.vaultId);
    _graph = GraphBuilder()(records) ?? await _createFreshGraph();
    _fileRegistry = FileRegistry()..rebuild(_graph);

    // 2. Startup reconciliation — detect changes made while engine was stopped.
    final newRecords = await StartupReconciler(
      graph: _graph,
      fileRegistry: _fileRegistry,
      localBlobStore: blobStore,
      vaultId: config.vaultId,
      io: io,
    ).call(vaultPath);
    await nodeStore.saveAll(newRecords);
    _log('Startup reconciliation: ${newRecords.length} new record(s)');

    _diskApplier = DiskApplier(
      vaultPath: vaultPath,
      fileRegistry: _fileRegistry,
      localBlobStore: blobStore,
      remoteBlobStorage: null,
      vaultId: config.vaultId,
      io: io,
      changeProvider: changeProvider,
    );

    // 3. Start filesystem watcher — tracks changes even while offline.
    _fileEventHandler = FileEventHandler(
      vaultPath: vaultPath,
      io: io,
      changeProvider: changeProvider,
    );
    _fileEventSub = _fileEventHandler.events.listen(_emit);
    _fileEventHandler.start();

    _log('SyncEngine started (offline)');
    _emit(SyncStarted());

    // Phase 2: Online — runs in background, retries on network errors,
    // stops on auth/subscription errors until resume() is called.
    _connectionManager = ConnectionManager(
      serverUrl: serverUrl,
      vaultId: config.vaultId,
      tokenProvider: config.tokenProvider,
      cipher: cipher,
    );
    _started = true;
    _connectionSub = _connectionManager.events.listen(_onConnectionEvent);
    _connectionManager.connect();
  }

  /// Retry online phase after resolving auth or subscription issues.
  /// Call this after the user has re-authenticated or renewed their subscription.
  void resume() {
    if (_isStopped || _isConnected) return;
    _log('Resuming connection...');
    _connectionManager.connect();
  }

  Future<void> triggerPull() => _doPull(_pullUseCase);

  /// Wipes server vault data and resets all clients to a clean state.
  /// After the server clears the vault, it notifies all connected clients
  /// (including the initiator) via the vault notification topic.
  /// Each client wipes local state and re-uploads from disk.
  Future<void> triggerReset() async {
    if (!_isConnected) return;
    _log('Triggering vault reset...');
    await _remoteServer.resetVault();
  }

  /// Fully stops the engine including the file watcher.
  Future<void> stop() async {
    _isStopped = true;
    _emit(SyncStopped());
    if (_started) {
      await _stopOnlinePhase();
      await _connectionSub?.cancel();
      _connectionSub = null;
      await _connectionManager.dispose();
      _started = false;
    }
    await _fileEventSub?.cancel();
    _fileEventSub = null;
    await _fileEventHandler.stop();
    _log('SyncEngine stopped');
  }

  void _schedulePull() {
    _pullDebounce?.cancel();
    _pullDebounce = Timer(
      const Duration(milliseconds: 500),
      () => _doPull(_pullUseCase),
    );
  }

  /// Stops only the online phase (notify subscription + debounce).
  /// WebSocket lifecycle is owned by ConnectionManager.
  Future<void> _stopOnlinePhase() async {
    _pullDebounce?.cancel();
    _pullDebounce = null;
    await _notifySub?.cancel();
    _notifySub = null;
    await _notifySubscriber?.dispose();
    _notifySubscriber = null;
    if (_started) await _connectionManager.stopOnline();
  }

  Future<void> dispose() async {
    await stop();
    await _eventsController.close();
  }

  void _onConnectionEvent(ConnectionEvent event) {
    switch (event) {
      case ConnectionAttempting(:final attempt):
        _log('Connect attempt $attempt...');
        _emit(SyncConnecting(attempt: attempt));

      case ConnectionEstablished(:final server, :final blobs, :final notify):
        _remoteServer = server;
        _remoteBlobStorage = blobs;
        _notifySubscriber = notify;
        _rebuildUseCases();
        _emit(SyncConnected());
        _log('Connected successfully');
        _onConnected();

      case ConnectionLost():
        _pullDebounce?.cancel();
        _pullDebounce = null;
        _notifySub?.cancel();
        _notifySub = null;
        _notifySubscriber?.dispose();
        _notifySubscriber = null;
        _log('Transport closed, reconnecting...');
        _emit(SyncDisconnected());

      case ConnectionSessionExpired():
        _log('Session expired — stopping online phase');
        _stopOnlinePhase();
        _emit(SyncSessionExpired());

      case ConnectionSubscriptionExpired():
        _log('Subscription expired — stopping online phase');
        _stopOnlinePhase();
        _emit(SyncSubscriptionExpired());
    }
  }

  Future<Graph<NodeRecord>> _createFreshGraph() async {
    final vaultRecord = VaultRecord(
      key: config.vaultId,
      vaultId: config.vaultId,
      isSynced: false,
      createdAt: DateTime.now(),
      name: config.vaultName,
    );
    final graph = Graph<NodeRecord>(root: VaultNode(config.vaultId));
    graph.updateNodeData(config.vaultId, vaultRecord);
    await nodeStore.save(vaultRecord);
    return graph;
  }

  void _rebuildUseCases() {
    _pushUseCase = PushUseCase(
      graph: _graph,
      server: _remoteServer,
      localBlobs: LocalBlobStorageAdapter(blobStore, config.vaultId),
      remoteBlobs: _remoteBlobStorage!,
    );
    _pullUseCase = PullUseCase(graph: _graph, server: _remoteServer);
    _diskApplier = DiskApplier(
      vaultPath: vaultPath,
      fileRegistry: _fileRegistry,
      localBlobStore: blobStore,
      remoteBlobStorage: _remoteBlobStorage!,
      vaultId: config.vaultId,
      io: io,
      changeProvider: changeProvider,
    );
    _conflictResolver = ConflictResolver(
      graph: _graph,
      fileRegistry: _fileRegistry,
      localBlobStore: blobStore,
      remoteBlobStorage: _remoteBlobStorage!,
      vaultPath: vaultPath,
      vaultId: config.vaultId,
      strategy: config.conflictStrategy,
      io: io,
    );
    _fileEventHandler.updateContext(
      FileHandlerContext(
        graph: _graph,
        fileRegistry: _fileRegistry,
        pushUseCase: _pushUseCase,
        nodeStore: nodeStore,
        blobStore: blobStore,
        vaultPath: vaultPath,
        vaultId: config.vaultId,
        io: io,
      ),
    );
  }

  /// Online phase: runs once after each successful connection.
  /// Performs discovery, server recovery, per-file pull/push and starts timer.
  Future<void> _onConnected() async {
    // Check reset epoch first — if server was reset while we were offline,
    // wipe local state and re-upload instead of merging stale history.
    try {
      final serverEpoch = await _remoteServer.getVaultEpoch();
      final localEpoch = await nodeStore.loadResetEpoch(
        vaultId: config.vaultId,
      );
      if (serverEpoch > localEpoch) {
        _log(
          'Reset epoch mismatch (server=$serverEpoch, local=$localEpoch) — resetting',
        );
        await _doReset(newEpoch: serverEpoch);
        return;
      }
    } catch (e) {
      if (_isSessionExpired(e)) {
        await _stopOnlinePhase();
        _emit(SyncSessionExpired());
        return;
      }
      if (_isSubscriptionExpired(e)) {
        await _stopOnlinePhase();
        _emit(SyncSubscriptionExpired());
        return;
      }
      _log('Could not fetch vault epoch: $e');
    }

    if (!_isConnected) return;

    _conflictResolver = ConflictResolver(
      graph: _graph,
      fileRegistry: _fileRegistry,
      localBlobStore: blobStore,
      remoteBlobStorage: _remoteBlobStorage!,
      vaultPath: vaultPath,
      vaultId: config.vaultId,
      strategy: config.conflictStrategy,
      io: io,
    );

    // Vault-wide discovery — populate graph with server state.
    // ChangeRecords for files already on disk are skipped here;
    // per-file pull below will handle conflicts properly.
    var discovered = <NodeRecord>[];
    try {
      final discoveryResults = await _remoteServer.pull([
        FileSyncCursor(fileId: ''),
      ]);
      discovered = discoveryResults.expand((r) => r.nodes).toList();
      if (discovered.isNotEmpty) {
        _log('Discovery: ${discovered.length} remote record(s)');
        final truly = discovered
            .where((r) => _graph.getNodeByKey(r.key) == null)
            .toList();
        if (truly.isNotEmpty) {
          final toApply = <NodeRecord>[];
          for (final r in truly) {
            if (r is! ChangeRecord) {
              toApply.add(r);
              continue;
            }
            final path = _fileRegistry.pathByFileId(r.fileId);
            if (path == null || !await io.fileExists('$vaultPath/$path')) {
              toApply.add(r);
            }
          }
          ApplyRemoteNodesUseCase(_graph)(toApply);
          await nodeStore.saveAll(toApply);

          for (final r in truly) {
            if (r is! DeleteRecord) continue;
            final path = _fileRegistry.pathByFileId(r.fileId);
            if (path == null) continue;
            changeProvider.suppress(path);
            try {
              await io.deleteFile('$vaultPath/$path');
            } finally {
              changeProvider.unsuppress(path);
              _fileRegistry.remove(path);
            }
          }

          _fileRegistry.rebuild(_graph);
          _diskApplier = DiskApplier(
            vaultPath: vaultPath,
            fileRegistry: _fileRegistry,
            localBlobStore: blobStore,
            remoteBlobStorage: _remoteBlobStorage!,
            vaultId: config.vaultId,
            io: io,
            changeProvider: changeProvider,
          );

          final toWrite = <NodeRecord>[];
          for (final r in toApply) {
            if (r is! ChangeRecord) continue;
            final path = _fileRegistry.pathByFileId(r.fileId);
            if (path != null && !await io.fileExists('$vaultPath/$path')) {
              toWrite.add(r);
            }
          }
          if (toWrite.isNotEmpty) {
            await _diskApplier.call(toWrite);
          }
        }
      }
    } catch (e) {
      if (_isSessionExpired(e)) {
        await _stopOnlinePhase();
        _emit(SyncSessionExpired());
        return;
      }
      if (_isSubscriptionExpired(e)) {
        await _stopOnlinePhase();
        _emit(SyncSubscriptionExpired());
        return;
      }
      _log('Discovery error: $e');
    }

    if (!_isConnected) return;

    // Server recovery — re-push records missing from server.
    final serverKeys = discovered.map((r) => r.key).toSet();
    final recoveryRecords = <NodeRecord>[];
    for (final node in _graph.nodes.values) {
      final record = _graph.getNodeData(node.key);
      if (record == null || record is VaultRecord) continue;
      if (!serverKeys.contains(record.key) && record.isSynced) {
        final unsynced = record.withUnsynced();
        _graph.updateNodeData(record.key, unsynced);
        recoveryRecords.add(unsynced);
      }
    }
    if (recoveryRecords.isNotEmpty) {
      await nodeStore.saveAll(recoveryRecords);
      _log(
        'Server recovery: ${recoveryRecords.length} record(s) marked for re-push',
      );
    }

    // Per-file pull + push (including unsynced offline changes).
    final allFileNodes = _collectAllFileNodes();
    if (!await _syncPerFileNodes(allFileNodes)) return;
    await _pushUseCase.call(allFileNodes);
    await _markSyncedInStore([
      for (final fn in allFileNodes) ..._collectSyncedNodes(fn),
    ]);
    await _runLocalGC();

    // Subscribe to vault notifications — pull on changes, reset on vault wipe.
    _notifySub = _notifySubscriber!.subscribe('vault:${config.vaultId}').listen(
      (event) {
        if (event.payload['reset'] == true) {
          _doReset();
        } else {
          _schedulePull();
        }
      },
    );
  }

  /// Called when the server signals a vault reset (via notification or epoch check).
  /// [newEpoch] — if provided, saves it locally after reset completes.
  /// When called from notification handler, fetches epoch from server.
  Future<void> _doReset({int? newEpoch}) async {
    _log('Vault reset — wiping local state and re-uploading...');
    _emit(SyncVaultReset());
    _pullDebounce?.cancel();
    _pullDebounce = null;

    // Wipe local SQLite node store.
    await nodeStore.deleteAll(vaultId: config.vaultId);

    // Rebuild graph from scratch (VaultRecord only).
    _graph = await _createFreshGraph();
    _fileRegistry = FileRegistry();

    // Re-run startup reconciliation to pick up files from disk.
    final newRecords = await StartupReconciler(
      graph: _graph,
      fileRegistry: _fileRegistry,
      localBlobStore: blobStore,
      vaultId: config.vaultId,
      io: io,
    ).call(vaultPath);
    await nodeStore.saveAll(newRecords);
    _log('Reset reconciliation: ${newRecords.length} record(s) from disk');

    // Re-build use cases with fresh graph (also updates FileEventHandler context).
    _rebuildUseCases();

    // Push everything to the now-empty server.
    final allFileNodes = _fileRegistry.fileIdToNodeKey.keys
        .map((fileId) => _fileRegistry.nodeKeyByFileId(fileId))
        .whereType<String>()
        .map((key) => _graph.getNodeByKey(key))
        .whereType<Node>()
        .toList();

    if (allFileNodes.isNotEmpty) {
      await _pushUseCase.call(allFileNodes);
      final synced = <NodeRecord>[];
      for (final fn in allFileNodes) {
        synced.addAll(_collectSyncedNodes(fn));
      }
      await _markSyncedInStore(synced);
    }

    // Persist the epoch so we don't re-reset on the next connect.
    final epoch = newEpoch ?? await _fetchEpochSafe();
    await nodeStore.saveResetEpoch(epoch, vaultId: config.vaultId);

    _log(
      'Reset complete — re-uploaded ${allFileNodes.length} file(s), epoch=$epoch',
    );

    // Re-subscribe to vault notifications if we have an active connection.
    if (_isConnected && _notifySubscriber != null && _notifySub == null) {
      _notifySub = _notifySubscriber!
          .subscribe('vault:${config.vaultId}')
          .listen((event) {
            if (event.payload['reset'] == true) {
              _doReset();
            } else {
              _schedulePull();
            }
          });
    }
  }

  Future<int> _fetchEpochSafe() async {
    try {
      return await _remoteServer.getVaultEpoch();
    } catch (_) {
      return 0;
    }
  }

  Future<void> _doPull(PullUseCase pullUseCase) async {
    if (!_isConnected) return;
    if (_isPulling) return;
    _isPulling = true;
    try {
      await _doPullInternal(pullUseCase);
    } finally {
      _isPulling = false;
    }
  }

  Future<void> _doPullInternal(PullUseCase pullUseCase) async {
    try {
      final discoveryResults = await _remoteServer.pull([
        FileSyncCursor(fileId: ''),
      ]);
      final discovered = discoveryResults.expand((r) => r.nodes).toList();
      final newRecords = discovered
          .where((r) => _graph.getNodeByKey(r.key) == null)
          .toList();
      if (newRecords.isNotEmpty) {
        _log('Pull: discovered ${newRecords.length} new remote record(s)');
        ApplyRemoteNodesUseCase(_graph)(newRecords);
        await nodeStore.saveAll(newRecords);
        // Re-register paths for files that were deleted then recreated.
        // FileRecord.key == fileId, so the FileRecord is found directly by key.
        for (final r in newRecords) {
          if (r is! ChangeRecord) continue;
          if (_fileRegistry.pathByFileId(r.fileId) != null) continue;
          final fileRecord = _graph.getNodeData(r.fileId);
          if (fileRecord is FileRecord) {
            _fileRegistry.register(
              fileRecord.path,
              fileRecord.fileId,
              r.fileId,
            );
          }
        }
        // Exclude DeleteRecords superseded by a ChangeRecord in the same batch
        // (delete+recreate arrives together — skip the delete so diskApplier can write the recreated file).
        final recreatedFileIds = newRecords
            .whereType<ChangeRecord>()
            .map((r) => r.fileId)
            .toSet();
        final diskRecords = newRecords
            .where(
              (r) => r is! DeleteRecord || !recreatedFileIds.contains(r.fileId),
            )
            .toList();
        await _diskApplier.call(diskRecords);
        _fileRegistry.rebuild(_graph);
      }
    } catch (e) {
      if (_isSessionExpired(e)) {
        await _stopOnlinePhase();
        _emit(SyncSessionExpired());
        return;
      }
      if (_isSubscriptionExpired(e)) {
        await _stopOnlinePhase();
        _emit(SyncSubscriptionExpired());
        return;
      }
      if (_isServerUnavailable(e)) {
        _log('Pull vault-wide error (server unavailable): $e');
        _connectionManager.forceReconnect();
        return;
      }
      _log('Pull vault-wide error: $e');
    }

    final allFileNodes = _collectAllFileNodes();
    if (!await _syncPerFileNodes(allFileNodes)) return;
    await _runLocalGC();
  }

  List<Node> _collectAllFileNodes() => _fileRegistry.fileIdToNodeKey.keys
      .map((fileId) => _fileRegistry.nodeKeyByFileId(fileId))
      .whereType<String>()
      .map((key) => _graph.getNodeByKey(key))
      .whereType<Node>()
      .toList();

  /// Pulls and syncs per-file nodes. Returns false if a fatal error occurred
  /// (session/subscription expired or server unavailable) and caller should abort.
  Future<bool> _syncPerFileNodes(List<Node> allFileNodes) async {
    final localLeafByKey = {
      for (final n in allFileNodes) n.key: _graph.findLeaf(n),
    };
    try {
      final pullResults = await _pullUseCase.call(allFileNodes);
      for (final result in pullResults) {
        final nodeKey = _fileRegistry.nodeKeyByFileId(result.fileId);
        if (nodeKey == null) continue;
        final fileNode = _graph.getNodeByKey(nodeKey);
        if (fileNode == null) continue;
        final localLeaf = localLeafByKey[fileNode.key];
        if (localLeaf == null) continue;

        _emit(
          SyncFilePulled(fileId: result.fileId, nodeCount: result.nodes.length),
        );
        final resolution = await _conflictResolver.call(
          fileNode,
          localLeaf,
          result.nodes,
        );
        await _diskApplier.call(resolution.recordsForDisk);
        await nodeStore.saveAll([
          ...result.nodes,
          ...resolution.newLocalRecords,
        ]);
        if (resolution.newLocalRecords.isNotEmpty) {
          final extraNodes = resolution.newLocalRecords
              .whereType<FileRecord>()
              .map((r) => _graph.getNodeByKey(r.key))
              .whereType<Node>()
              .toList();
          await _pushUseCase.call([fileNode, ...extraNodes]);
          await _markSyncedInStore(_collectSyncedNodes(fileNode));
        }
      }
    } catch (e) {
      if (_isSessionExpired(e)) {
        await _stopOnlinePhase();
        _emit(SyncSessionExpired());
        return false;
      }
      if (_isSubscriptionExpired(e)) {
        await _stopOnlinePhase();
        _emit(SyncSubscriptionExpired());
        return false;
      }
      if (_isServerUnavailable(e)) {
        _log('Per-file sync error (server unavailable): $e');
        _connectionManager.forceReconnect();
        return false;
      }
      _log('Per-file sync error: $e');
      _emit(SyncError('Pull failed: $e'));
      return false;
    }
    return true;
  }

  Future<void> _runLocalGC() async {
    try {
      await LocalGCUseCase(
        graph: _graph,
        fileRegistry: _fileRegistry,
        nodeStore: nodeStore,
        blobStore: blobStore,
        vaultId: config.vaultId,
      ).call();
    } catch (e) {
      _log('Local GC error: $e');
    }
  }

  List<NodeRecord> _collectSyncedNodes(Node fileNode) {
    final result = <NodeRecord>[];
    var current = _graph.findLeaf(fileNode);
    while (true) {
      final record = _graph.getNodeData(current.key);
      if (record == null) break;
      if (record.isSynced) result.add(record);
      final parent = _graph.getNodeParent(current);
      if (parent == null) break;
      current = parent;
    }
    return result;
  }

  Future<void> _markSyncedInStore(List<NodeRecord> nodes) async {
    for (final node in nodes) {
      if (node.isSynced) {
        await nodeStore.markSynced(node.key, vaultId: config.vaultId);
      }
    }
  }

  /// Returns true if [error] indicates that the server rejected the request
  /// due to an authentication failure (expired or invalid token).
  bool _isSessionExpired(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('unauthenticated');
  }

  bool _isSubscriptionExpired(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('payment_required');
  }

  /// Returns true if [error] indicates a transient server-side infrastructure
  /// failure (e.g. Supabase down), as opposed to a protocol-level error.
  bool _isServerUnavailable(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('socketexception') ||
        msg.contains('connection refused') ||
        msg.contains('connection reset') ||
        msg.contains('os error');
  }

  void _log(String msg) {
    _logger.info(msg);
    _emit(SyncLogMessage(msg));
  }

  void _emit(SyncEngineEvent event) {
    if (!_eventsController.isClosed) {
      _eventsController.add(event);
    }
  }
}
