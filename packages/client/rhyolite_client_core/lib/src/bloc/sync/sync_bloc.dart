import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:rpc_dart/logger.dart';
import 'package:rpc_notify/rpc_notify.dart';

import '../../changes/i_change_provider.dart';
import '../../engine/conflict_resolver.dart';
import '../../engine/disk_applier.dart';
import '../../engine/file_registry.dart';
import '../../engine/local_gc_use_case.dart';
import '../../engine/vault_config.dart';
import '../../local/local_blob_storage_adapter.dart';
import '../../local/local_blob_store.dart';
import '../../local/local_node_store.dart';
import '../../platform/i_platform_io.dart';
import '../connection/connection_bloc.dart';
import '../vault/vault_bloc.dart';

part 'sync_event.dart';
part 'sync_state.dart';

final _logger = RpcLogger('rhyolite.sync_bloc');

/// Bus topics published by [SyncBloc].
abstract final class SyncTopics {
  /// Published when the server signals a vault reset.
  /// Payload: `{newEpoch: int?}`.
  static const vaultReset = 'vault:reset';
}

// ---------------------------------------------------------------------------
// Vault and server contexts (unpacked from bus payloads)
// ---------------------------------------------------------------------------

class _VaultCtx {
  _VaultCtx({
    required this.graph,
    required this.fileRegistry,
    required this.config,
    required this.vaultPath,
    required this.nodeStore,
    required this.blobStore,
    required this.io,
    required this.changeProvider,
  });

  final Graph<NodeRecord> graph;
  final FileRegistry fileRegistry;
  final VaultConfig config;
  final String vaultPath;
  final LocalNodeStore nodeStore;
  final LocalBlobStore blobStore;
  final IPlatformIO io;
  final IChangeProvider changeProvider;
}

class _ServerCtx {
  _ServerCtx({required this.server, required this.blobs, required this.notify});

  final IGraphServer server;
  final IBlobStorage blobs;
  final NotifySubscriber notify;
}

// ---------------------------------------------------------------------------
// SyncBloc
// ---------------------------------------------------------------------------

class SyncBloc extends Bloc<SyncBlocEvent, SyncBlocState> {
  SyncBloc({required this.bus}) : super(SyncIdle()) {
    on<SyncTriggerPull>(_onTriggerPull);
    on<SyncTriggerReset>(_onTriggerReset);
    on<SyncTriggerRepair>(_onTriggerRepair);
    on<_ConnectionOnline>(_onConnectionOnline);
    on<_ConnectionOffline>(_onConnectionOffline);
    on<_VaultReady>(_onVaultReady);
    on<_FileChanged>(_onFileChanged);
    on<_OrphanedNodes>(_onOrphanedNodes);
    on<_ServerNotifyEvent>(_onServerNotify);
    on<_FatalError>((e, emit) => emit(SyncFailed(e.reason)));
    on<_LockBusy>(_onLockBusy);
    on<_LockLost>(_onLockLost);
    on<_RetrySync>(_onRetrySync);

    _busConnectionSub = bus.subscriber
        .subscribe(ConnectionTopics.online)
        .listen((e) => add(_ConnectionOnline(e.payload)));
    _busConnectionSub = bus.subscriber
        .subscribe(ConnectionTopics.offline)
        .listen((_) => add(_ConnectionOffline()));
    _busConnectionSub = bus.subscriber
        .subscribe(ConnectionTopics.expired)
        .listen((_) => add(_ConnectionOffline()));
    _busVaultSub = bus.subscriber
        .subscribe(VaultTopics.ready)
        .listen((e) => add(_VaultReady(e.payload)));
    _busFileSub = bus.subscriber
        .subscribe(VaultTopics.fileChanged)
        .listen((e) => add(_FileChanged(e.payload['fileId'] as String)));
    _busOrphanSub = bus.subscriber
        .subscribe(VaultTopics.orphanedNodes)
        .listen((e) => add(_OrphanedNodes(e.payload['records'] as List<NodeRecord>)));
  }

  final DirectNotifyServiceEnvironment bus;

  _VaultCtx? _vault;
  _ServerCtx? _server;

  PushUseCase? _pushUseCase;
  PullUseCase? _pullUseCase;
  DiskApplier? _diskApplier;
  ConflictResolver? _conflictResolver;

  StreamSubscription<NotifyEvent>? _notifySub;
  StreamSubscription<NotifyEvent>? _busConnectionSub;
  StreamSubscription<NotifyEvent>? _busVaultSub;
  StreamSubscription<NotifyEvent>? _busFileSub;
  StreamSubscription<NotifyEvent>? _busOrphanSub;

  Timer? _pullDebounce;
  Timer? _lockRenewTimer;
  Timer? _busyRetryTimer;
  Duration _busyRetryDelay = const Duration(seconds: 5);

  bool get _isReady => _vault != null && _server != null;
  bool get _isPulling => state is SyncActive && (state as SyncActive).isPulling;

  // ---------------------------------------------------------------------------
  // Bus event handlers
  // ---------------------------------------------------------------------------

  Future<void> _onConnectionOnline(
    _ConnectionOnline event,
    Emitter<SyncBlocState> emit,
  ) async {
    _server = _ServerCtx(
      server: event.payload['server'] as IGraphServer,
      blobs: event.payload['blobs'] as IBlobStorage,
      notify: event.payload['notify'] as NotifySubscriber,
    );
    if (_vault != null) {
      _rebuildUseCases();
      emit(SyncActive());
      await _onConnected(emit);
    }
  }

  Future<void> _onConnectionOffline(
    _ConnectionOffline event,
    Emitter<SyncBlocState> emit,
  ) async {
    _stopLockRenewal();
    _stopBusyRetry();
    await _releaseLock();
    _pullDebounce?.cancel();
    _pullDebounce = null;
    await _notifySub?.cancel();
    _notifySub = null;
    await _server?.notify.dispose();
    _server = null;
    _clearUseCases();
    emit(SyncOffline());
  }

  Future<void> _onVaultReady(
    _VaultReady event,
    Emitter<SyncBlocState> emit,
  ) async {
    _vault = _VaultCtx(
      graph: event.payload['graph'] as Graph<NodeRecord>,
      fileRegistry: event.payload['fileRegistry'] as FileRegistry,
      config: event.payload['config'] as VaultConfig,
      vaultPath: event.payload['vaultPath'] as String,
      nodeStore: event.payload['nodeStore'] as LocalNodeStore,
      blobStore: event.payload['blobStore'] as LocalBlobStore,
      io: event.payload['io'] as IPlatformIO,
      changeProvider: event.payload['changeProvider'] as IChangeProvider,
    );
    if (_server != null) {
      _rebuildUseCases();
      emit(SyncActive());
      await _onConnected(emit);
    }
  }

  Future<void> _onFileChanged(
    _FileChanged event,
    Emitter<SyncBlocState> emit,
  ) async {
    if (!_isReady) return;
    final v = _vault!;
    final nodeKey = v.fileRegistry.nodeKeyByFileId(event.fileId);
    final fileNode = nodeKey != null
        ? v.graph.getNodeByKey(nodeKey)
        : v.graph.getNodeByKey(event.fileId);
    if (fileNode == null) return;
    await _pushFile(fileNode);
  }

  Future<void> _onOrphanedNodes(
    _OrphanedNodes event,
    Emitter<SyncBlocState> emit,
  ) async {
    if (!_isReady) return;
    final s = _server!;
    try {
      final keys = event.records.map((r) => r.key).toList();
      await s.server.deleteNodes(keys);
    } catch (e) {
      _log('Orphan delete error: $e');
    }
  }

  Future<void> _onTriggerPull(
    SyncTriggerPull event,
    Emitter<SyncBlocState> emit,
  ) async {
    if (!_isReady) return;
    await _doPull(emit);
  }

  Future<void> _onTriggerReset(
    SyncTriggerReset event,
    Emitter<SyncBlocState> emit,
  ) async {
    if (!_isReady) return;
    await _server!.server.resetVault();
  }

  Future<void> _onTriggerRepair(
    SyncTriggerRepair event,
    Emitter<SyncBlocState> emit,
  ) async {
    if (!_isReady) return;
    await _runWithLock(() async {
      await _runRepairCycle(emit);
    }, emit: emit);
  }

  Future<void> _onServerNotify(
    _ServerNotifyEvent event,
    Emitter<SyncBlocState> emit,
  ) async {
    final current = state;
    final ownsLock = current is SyncActive && current.hasLock;
    if (event.payload['reset'] == true) {
      final epoch = await _fetchEpochSafe();
      bus.publisher.publish(SyncTopics.vaultReset, {'newEpoch': epoch});
      return;
    }

    if (ownsLock) {
      // Self-echo while we own the lock is not actionable. Ignore it so our
      // own push does not immediately trigger a pull against the same branch.
      return;
    }

    if (event.payload['lockReleased'] == true) {
      if (state is SyncBusy) {
        _busyRetryTimer?.cancel();
        _busyRetryTimer = null;
        add(_RetrySync());
      }
    } else {
      _schedulePull();
    }
  }

  Future<void> _onLockBusy(_LockBusy event, Emitter<SyncBlocState> emit) async {
    _stopLockRenewal();
    _scheduleBusyRetry(emit, vaultId: event.vaultId, lockToken: event.lockToken);
  }

  Future<void> _onLockLost(_LockLost event, Emitter<SyncBlocState> emit) async {
    _stopLockRenewal();
    _scheduleBusyRetry(emit, vaultId: event.vaultId);
  }

  Future<void> _onRetrySync(_RetrySync event, Emitter<SyncBlocState> emit) async {
    if (!_isReady || state is! SyncBusy) return;
    _stopBusyRetry();
    emit(SyncActive());
    await _onConnected(emit);
  }

  // ---------------------------------------------------------------------------
  // Sync logic
  // ---------------------------------------------------------------------------

  Future<void> _onConnected(Emitter<SyncBlocState> emit) async {
    await _runWithLock(() async {
      await _onConnectedInternal();
    }, emit: emit);
  }

  Future<void> _onConnectedInternal() async {
    final v = _vault!;
    final s = _server!;

    // Check reset epoch first.
    try {
      final serverEpoch = await s.server.getVaultEpoch();
      final localEpoch = await v.nodeStore.loadResetEpoch(
        vaultId: v.config.vaultId,
      );
      if (serverEpoch > localEpoch) {
        _log('Reset epoch mismatch — triggering reset');
        bus.publisher.publish(SyncTopics.vaultReset, {'newEpoch': serverEpoch});
        return;
      }
    } catch (e) {
      final r = _fatalReason(e);
      if (r != null) {
        add(_FatalError(r));
        return;
      }
      _log('Could not fetch vault epoch: $e');
    }

    if (!_isReady) return;

    // Vault-wide discovery.
    var discovered = <NodeRecord>[];
    var newRecords = <NodeRecord>[];
    try {
      final results = await s.server.pull([FileSyncCursor(fileId: '')]);
      discovered = results.expand((r) => r.nodes).toList();
      newRecords = discovered
          .where((r) => v.graph.getNodeByKey(r.key) == null)
          .toList();

      if (newRecords.isNotEmpty) {
        _log('Discovery: ${newRecords.length} new record(s)');
        final toApply = <NodeRecord>[];
        for (final r in newRecords) {
          if (r is! ChangeRecord) {
            toApply.add(r);
            continue;
          }
          final path = v.fileRegistry.pathByFileId(r.fileId);
          if (path == null || !await v.io.fileExists('${v.vaultPath}/$path')) {
            toApply.add(r);
          }
        }
        v.graph.apply(toApply);
        await v.nodeStore.saveAll(toApply);

        for (final r in newRecords) {
          if (r is! DeleteRecord) continue;
          final path = v.fileRegistry.pathByFileId(r.fileId);
          if (path == null) continue;
          try {
            await v.io.deleteFile('${v.vaultPath}/$path');
          } catch (_) {}
          v.fileRegistry.remove(path);
        }

        v.fileRegistry.rebuild(v.graph);
        _rebuildDiskApplier();

        final toWrite = <NodeRecord>[];
        for (final r in toApply) {
          if (r is! ChangeRecord) continue;
          final path = v.fileRegistry.pathByFileId(r.fileId);
          if (path != null && !await v.io.fileExists('${v.vaultPath}/$path')) {
            toWrite.add(r);
          }
        }
        if (toWrite.isNotEmpty) await _diskApplier!.call(toWrite);
      }
    } catch (e) {
      final r = _fatalReason(e);
      if (r != null) {
        add(_FatalError(r));
        return;
      }
      _log('Discovery error: $e');
    }

    if (!_isReady) return;

    // Server recovery — mark synced records missing from server as unsynced.
    final serverKeys = discovered.map((r) => r.key).toSet();
    final recoveryRecords = <NodeRecord>[];
    for (final node in v.graph.nodes.values) {
      final record = v.graph.getNodeData(node.key);
      if (record == null || record is VaultRecord) continue;
      if (!serverKeys.contains(record.key) && record.isSynced) {
        final unsynced = record.withUnsynced();
        v.graph.updateNodeData(record.key, unsynced);
        recoveryRecords.add(unsynced);
      }
    }
    if (recoveryRecords.isNotEmpty) {
      await v.nodeStore.saveAll(recoveryRecords);
      _log('Server recovery: ${recoveryRecords.length} record(s) re-queued');
    }

    // Per-file pull + push.
    final allFileNodes = _collectAllFileNodes();
    final filesToPull = _filterFilesForPull(allFileNodes, newRecords);
    if (!await _syncPerFileNodes(filesToPull)) return;

    final synced = await _pushUseCase!.call(allFileNodes);
    v.graph.markSynced(synced);
    await _markSyncedInStore(synced);
    await _runLocalGC();

    // Subscribe to server notifications.
    _notifySub = s.notify
        .subscribe('vault:${v.config.vaultId}')
        .listen((e) => add(_ServerNotifyEvent(e.payload)));

    _log('Sync complete');
  }

  Future<void> _doPull(Emitter<SyncBlocState> emit) async {
    if (!_isReady || _isPulling) return;
    emit((state as SyncActive).copyWith(isPulling: true));
    try {
      await _doPullInternal(emit);
    } finally {
      if (state is SyncActive) {
        emit((state as SyncActive).copyWith(isPulling: false));
      }
    }
  }

  Future<void> _doPullInternal(Emitter<SyncBlocState> emit) async {
    await _runWithLock(() async {
      await _doPullInternalUnlocked();
    }, emit: emit);
  }

  Future<void> _doPullInternalUnlocked() async {
    final v = _vault!;
    final s = _server!;

    var newRecords = <NodeRecord>[];
    try {
      final results = await s.server.pull([FileSyncCursor(fileId: '')]);
      final discovered = results.expand((r) => r.nodes).toList();
      newRecords = discovered
          .where((r) => v.graph.getNodeByKey(r.key) == null)
          .where((r) => r.parentKey != null || r is VaultRecord || r is FileRecord)
          .toList();

      if (newRecords.isNotEmpty) {
        _log('Pull: ${newRecords.length} new record(s)');
        v.graph.apply(newRecords);
        await v.nodeStore.saveAll(newRecords);

        for (final r in newRecords) {
          if (r is! ChangeRecord) continue;
          if (v.fileRegistry.pathByFileId(r.fileId) != null) continue;
          final fileRecord = v.graph.getNodeData(r.fileId);
          if (fileRecord is FileRecord) {
            v.fileRegistry.register(
              fileRecord.path,
              fileRecord.fileId,
              r.fileId,
            );
          }
        }

        final recreatedFileIds = newRecords
            .whereType<ChangeRecord>()
            .map((r) => r.fileId)
            .toSet();
        final diskRecords = newRecords
            .where(
              (r) => r is! DeleteRecord || !recreatedFileIds.contains(r.fileId),
            )
            .toList();
        await _diskApplier!.call(diskRecords);
        v.fileRegistry.rebuild(v.graph);
      }
    } catch (e) {
      final r = _fatalReason(e);
      if (r != null) {
        add(_FatalError(r));
        return;
      }
      _log('Pull error: $e');
      return;
    }

    final allFileNodes = _collectAllFileNodes();
    final filesToPull = _filterFilesForPull(allFileNodes, newRecords);
    if (!await _syncPerFileNodes(filesToPull)) return;

    await _runLocalGC();
  }

  Future<void> _runWithLock(
    Future<void> Function() body, {
    Emitter<SyncBlocState>? emit,
  }) async {
    final current = state;
    if (current is SyncActive && current.hasLock) {
      await body();
      return;
    }

    final v = _vault;
    final s = _server;
    if (v == null || s == null) {
      await body();
      return;
    }

    try {
      final token = await s.server.acquireLock(v.config.vaultId);
      final currentState = state;
      if (emit != null && currentState is SyncActive) {
        emit(currentState.copyWith(lockToken: token));
      }
      _startLockRenewal(token);
      await body();
    } catch (e) {
      if (_isLockBusyError(e)) {
        if (emit != null) {
          add(_LockBusy(vaultId: v.config.vaultId));
        }
        return;
      }
      rethrow;
    } finally {
      await _releaseLock(emit: emit);
    }
  }

  Future<void> _releaseLock({Emitter<SyncBlocState>? emit}) async {
    _stopLockRenewal();
    final v = _vault;
    final s = _server;
    final current = state;
    final stateToken = current is SyncActive ? current.lockToken : null;
    final tokenToRelease = stateToken;
    if (tokenToRelease == null || v == null || s == null) return;

    try {
      await s.server.releaseLock(v.config.vaultId, tokenToRelease);
      if (emit != null && current is SyncActive) {
        emit(current.copyWith(clearLockToken: true));
      }
    } catch (e) {
      _log('Release lock error: $e');
    }
  }

  void _startLockRenewal(String token) {
    _lockRenewTimer?.cancel();
    _lockRenewTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final v = _vault;
      final s = _server;
      final current = state;
      if (v == null || s == null || current is! SyncActive || current.lockToken != token) {
        return;
      }
      try {
        await s.server.renewLock(v.config.vaultId, token);
      } catch (e) {
        if (_isLockBusyError(e) || _isInvalidLockError(e)) {
          add(_LockLost(v.config.vaultId));
          return;
        }
        _log('Renew lock error: $e');
      }
    });
  }

  void _stopLockRenewal() {
    _lockRenewTimer?.cancel();
    _lockRenewTimer = null;
  }

  void _scheduleBusyRetry(
    Emitter<SyncBlocState> emit, {
    required String vaultId,
    String? lockToken,
  }) {
    _stopBusyRetry();
    final delay = _busyRetryDelay;
    emit(SyncBusy(vaultId: vaultId, lockToken: lockToken, retryAfter: delay));
    _busyRetryTimer = Timer(delay, () => add(_RetrySync()));
    _busyRetryDelay = Duration(
      seconds: (_busyRetryDelay.inSeconds * 2).clamp(5, 60),
    );
  }

  void _stopBusyRetry() {
    _busyRetryTimer?.cancel();
    _busyRetryTimer = null;
    _busyRetryDelay = const Duration(seconds: 5);
  }

  Future<bool> _syncPerFileNodes(List<Node> fileNodes) async {
    final v = _vault!;
    final localLeafByKey = {
      for (final n in fileNodes) n.key: v.graph.findLeaf(n),
    };
    try {
      final pullResults = await _pullUseCase!.call(fileNodes);
      for (final result in pullResults) {
        final nodeKey = v.fileRegistry.nodeKeyByFileId(result.fileId);
        if (nodeKey == null) continue;
        final fileNode = v.graph.getNodeByKey(nodeKey);
        if (fileNode == null) continue;
        final localLeaf = localLeafByKey[fileNode.key];
        if (localLeaf == null) continue;

        v.graph.apply(result.nodes);
        final resolution = await _conflictResolver!.call(
          fileNode,
          localLeaf,
          result.nodes,
        );
        await _diskApplier!.call(resolution.recordsForDisk);
        await v.nodeStore.saveAll([
          ...result.nodes,
          ...resolution.newLocalRecords,
        ]);

        if (resolution.newLocalRecords.isNotEmpty) {
          final extraNodes = resolution.newLocalRecords
              .whereType<FileRecord>()
              .map((r) => v.graph.getNodeByKey(r.key))
              .whereType<Node>()
              .toList();
          final synced = await _pushUseCase!.call([fileNode, ...extraNodes]);
          v.graph.markSynced(synced);
          await _markSyncedInStore(synced);
        }
      }
    } catch (e) {
      final r = _fatalReason(e);
      if (r != null) {
        add(_FatalError(r));
        return false;
      }
      _log('Per-file sync error: $e');
      return false;
    }
    return true;
  }

  Future<void> _runRepairCycle(Emitter<SyncBlocState> emit) async {
    final v = _vault!;
    final allFileNodes = _collectAllFileNodes();
    final orphanedRecords = <NodeRecord>[];

    for (final fileNode in allFileNodes) {
      orphanedRecords.addAll(PruneLeafBranchesUseCase(v.graph).call(fileNode));
    }

    final gc = GraphGCUseCase(v.graph).call();
    final removedRecords = gc.removedNodes
        .map((n) => v.graph.getNodeData(n.key))
        .whereType<NodeRecord>()
        .toList();
    gc.apply(v.graph);

    if (!gc.isEmpty) {
      await v.nodeStore.deleteKeys(gc.removedNodeKeys, vaultId: v.config.vaultId);
      await v.blobStore.deleteBlobs(gc.removedBlobIds, vaultId: v.config.vaultId);
      bus.publisher.publish(
        VaultTopics.orphanedNodes,
        {
          'records': orphanedRecords.isNotEmpty
              ? [
                  ...orphanedRecords,
                  ...removedRecords,
                ]
              : removedRecords,
        },
      );
    } else if (orphanedRecords.isNotEmpty) {
      bus.publisher.publish(VaultTopics.orphanedNodes, {'records': orphanedRecords});
    }

    v.fileRegistry.rebuild(v.graph);
    _rebuildDiskApplier();

    final synced = await _pushUseCase!.call(allFileNodes);
    v.graph.markSynced(synced);
    await _markSyncedInStore(synced);
    await _runLocalGC();
  }

  Future<void> _pushFile(Node fileNode) async {
    if (_pushUseCase == null || _vault == null) return;
    try {
      final synced = await _pushUseCase!.call([fileNode]);
      _vault!.graph.markSynced(synced);
      await _markSyncedInStore(synced);
    } catch (e) {
      _log('Push error for ${fileNode.key}: $e');
    }
  }

  void _schedulePull() {
    _pullDebounce?.cancel();
    _pullDebounce = Timer(
      const Duration(milliseconds: 500),
      () => add(SyncTriggerPull()),
    );
  }

  // ---------------------------------------------------------------------------
  // Use case management
  // ---------------------------------------------------------------------------

  void _rebuildUseCases() {
    final v = _vault!;
    final s = _server!;
    _pushUseCase = PushUseCase(
      graph: v.graph,
      server: s.server,
      localBlobs: LocalBlobStorageAdapter(v.blobStore, v.config.vaultId),
      remoteBlobs: s.blobs,
    );
    _pullUseCase = PullUseCase(graph: v.graph, server: s.server);
    _rebuildDiskApplier();
    _conflictResolver = ConflictResolver(
      graph: v.graph,
      fileRegistry: v.fileRegistry,
      localBlobStore: v.blobStore,
      remoteBlobStorage: s.blobs,
      vaultPath: v.vaultPath,
      vaultId: v.config.vaultId,
      strategy: v.config.conflictStrategy,
      io: v.io,
    );
  }

  void _rebuildDiskApplier() {
    final v = _vault!;
    final s = _server!;
    _diskApplier = DiskApplier(
      vaultPath: v.vaultPath,
      fileRegistry: v.fileRegistry,
      localBlobStore: v.blobStore,
      remoteBlobStorage: s.blobs,
      vaultId: v.config.vaultId,
      io: v.io,
      changeProvider: v.changeProvider,
    );
  }

  void _clearUseCases() {
    _pushUseCase = null;
    _pullUseCase = null;
    _diskApplier = null;
    _conflictResolver = null;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  List<Node> _collectAllFileNodes() {
    final v = _vault!;
    return v.fileRegistry.fileIdToNodeKey.keys
        .map((id) => v.fileRegistry.nodeKeyByFileId(id))
        .whereType<String>()
        .map((key) => v.graph.getNodeByKey(key))
        .whereType<Node>()
        .toList();
  }

  List<Node> _filterFilesForPull(
    List<Node> allFileNodes,
    List<NodeRecord> remoteRecords,
  ) {
    final v = _vault!;
    final remoteFileIds = _extractFileIds(remoteRecords);
    return allFileNodes.where((node) {
      final fileRecord = v.graph.getNodeData(node.key);
      if (fileRecord is! FileRecord) return false;
      if (remoteFileIds.contains(fileRecord.fileId)) return true;
      final leaf = v.graph.findLeaf(node);
      final leafRecord = v.graph.getNodeData(leaf.key);
      return leafRecord != null && !leafRecord.isSynced;
    }).toList();
  }

  Set<String> _extractFileIds(List<NodeRecord> records) {
    final ids = <String>{};
    for (final r in records) {
      if (r is ChangeRecord) {
        ids.add(r.fileId);
      } else if (r is DeleteRecord) {
        ids.add(r.fileId);
      } else if (r is MoveRecord) {
        ids.add(r.fileId);
      } else if (r is FileRecord) {
        ids.add(r.fileId);
      }
    }
    return ids;
  }

  Future<void> _markSyncedInStore(List<NodeRecord> nodes) async {
    final v = _vault!;
    for (final node in nodes) {
      if (node.isSynced) {
        await v.nodeStore.markSynced(node.key, vaultId: v.config.vaultId);
      }
    }
  }

  Future<void> _runLocalGC() async {
    final v = _vault!;
    try {
      await LocalGCUseCase(
        graph: v.graph,
        nodeStore: v.nodeStore,
        blobStore: v.blobStore,
        vaultId: v.config.vaultId,
      ).call();
    } catch (e) {
      _log('Local GC error: $e');
    }
  }

  Future<int> _fetchEpochSafe() async {
    try {
      return await _server!.server.getVaultEpoch();
    } catch (_) {
      return 0;
    }
  }

  /// Returns the failure reason if [error] is fatal, null otherwise.
  SyncFailureReason? _fatalReason(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('unauthenticated')) {
      return SyncFailureReason.sessionExpired;
    }
    if (msg.contains('payment_required')) {
      return SyncFailureReason.subscriptionExpired;
    }
    return null;
  }

  bool _isLockBusyError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('already locked');
  }

  bool _isInvalidLockError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('invalid lock token');
  }

  void _log(String msg) => _logger.info(msg);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<void> close() async {
    _stopLockRenewal();
    _stopBusyRetry();
    await _releaseLock();
    _pullDebounce?.cancel();
    await _notifySub?.cancel();
    await _server?.notify.dispose();
    await _busConnectionSub?.cancel();
    await _busVaultSub?.cancel();
    await _busFileSub?.cancel();
    await _busOrphanSub?.cancel();
    return super.close();
  }
}
