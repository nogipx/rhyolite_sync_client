import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_client_core/rhyolite_client_core.dart';
import 'package:rhyolite_client_core/src/bloc/sync/sync_bloc.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:rpc_notify/rpc_notify.dart';

import '../../engine/file_event_handler.dart';

part 'vault_event.dart';
part 'vault_state.dart';

/// Bus topics published by [VaultBloc].
abstract final class VaultTopics {
  /// Vault is ready. Payload carries the full vault context needed by SyncBloc:
  /// `{graph, fileRegistry, config, vaultPath, nodeStore, blobStore, io}`.
  static const ready = 'vault:ready';

  /// A file was locally created/modified/moved/deleted and graph was updated.
  /// Payload: `{fileId: String}`.
  static const fileChanged = 'vault:file_changed';

  /// Orphaned branch roots after conflict pruning.
  /// Payload: `{records: List<NodeRecord>}`.
  static const orphanedNodes = 'vault:orphaned_nodes';
}

class VaultBloc extends Bloc<VaultBlocEvent, VaultBlocState> {
  VaultBloc({required this.bus}) : super(VaultIdle()) {
    on<VaultStart>(_onStart);
    on<VaultStop>(_onStop);
    on<VaultReset>(_onReset);
    on<_FileWatcherEvent>(_onFileWatcherEvent);
    _subscribeToResetTopic();
  }

  final DirectNotifyServiceEnvironment bus;

  FileEventHandler? _fileEventHandler;
  StreamSubscription<SyncEngineEvent>? _fileEventSub;
  StreamSubscription<NotifyEvent>? _resetSub;

  void _subscribeToResetTopic() {
    _resetSub?.cancel();
    _resetSub = bus.subscriber
        .subscribe(SyncTopics.vaultReset)
        .listen(
          (e) => add(VaultReset(newEpoch: e.payload['newEpoch'] as int?)),
        );
  }

  // ---------------------------------------------------------------------------
  // Event handlers
  // ---------------------------------------------------------------------------

  Future<void> _onStart(VaultStart event, Emitter<VaultBlocState> emit) async {
    emit(VaultLoading());
    await _disposeWatcher();

    final graph = await _loadGraph(event);
    final fileRegistry = FileRegistry()..rebuild(graph);

    final result = await StartupReconciler(
      graph: graph,
      fileRegistry: fileRegistry,
      localBlobStore: event.blobStore,
      vaultId: event.config.vaultId,
      io: event.io,
      statCache: event.statCache,
    ).call(event.vaultPath);
    await event.nodeStore.saveAll(result.newRecords);
    if (result.orphanedRecords.isNotEmpty) {
      bus.publisher.publish(VaultTopics.orphanedNodes, {'records': result.orphanedRecords});
    }

    final ready = VaultReady(
      graph: graph,
      fileRegistry: fileRegistry,
      config: event.config,
      vaultPath: event.vaultPath,
      nodeStore: event.nodeStore,
      blobStore: event.blobStore,
      io: event.io,
      changeProvider: event.changeProvider,
    );
    emit(ready);
    await _publishReady(ready);

    _startWatcher(event);
  }

  Future<void> _onStop(VaultStop event, Emitter<VaultBlocState> emit) async {
    await _disposeWatcher();
    emit(VaultIdle());
  }

  Future<void> _onReset(VaultReset event, Emitter<VaultBlocState> emit) async {
    final current = state;
    if (current is! VaultReady) return;

    emit(VaultLoading());

    await current.nodeStore.deleteAll(vaultId: current.config.vaultId);

    final graph = await _createFreshGraph(current.config, current.nodeStore);
    final fileRegistry = FileRegistry();

    final result = await StartupReconciler(
      graph: graph,
      fileRegistry: fileRegistry,
      localBlobStore: current.blobStore,
      vaultId: current.config.vaultId,
      io: current.io,
    ).call(current.vaultPath);
    await current.nodeStore.saveAll(result.newRecords);
    if (result.orphanedRecords.isNotEmpty) {
      bus.publisher.publish(VaultTopics.orphanedNodes, {'records': result.orphanedRecords});
    }

    if (event.newEpoch != null) {
      await current.nodeStore.saveResetEpoch(
        event.newEpoch!,
        vaultId: current.config.vaultId,
      );
    }

    final ready = VaultReady(
      graph: graph,
      fileRegistry: fileRegistry,
      config: current.config,
      vaultPath: current.vaultPath,
      nodeStore: current.nodeStore,
      blobStore: current.blobStore,
      io: current.io,
      changeProvider: current.changeProvider,
    );
    emit(ready);
    await _publishReady(ready);

    // Restart watcher with fresh graph context.
    _fileEventHandler?.updateContext(
      FileHandlerContext(
        graph: graph,
        fileRegistry: fileRegistry,
        nodeStore: current.nodeStore,
        blobStore: current.blobStore,
        vaultPath: current.vaultPath,
        vaultId: current.config.vaultId,
        io: current.io,
      ),
    );
  }

  Future<void> _onFileWatcherEvent(
    _FileWatcherEvent event,
    Emitter<VaultBlocState> emit,
  ) async {
    final current = state;
    if (current is! VaultReady) return;

    final e = event.engineEvent;
    String? fileId;

    if (e is SyncFileCreated) {
      fileId = current.fileRegistry.fileIdByPath(e.path);
    } else if (e is SyncFileModified) {
      fileId = current.fileRegistry.fileIdByPath(e.path);
    } else if (e is SyncFileMoved) {
      fileId = current.fileRegistry.fileIdByPath(e.toPath);
    } else if (e is SyncFileDeleted) {
      fileId = current.fileRegistry.fileIdByPath(e.path);
    }

    if (fileId != null) {
      bus.publisher.publish(VaultTopics.fileChanged, {'fileId': fileId});
    }

    if (e is SyncOrphanedNodes) {
      bus.publisher.publish(VaultTopics.orphanedNodes, {'records': e.records});
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<void> _publishReady(VaultReady ready) async {
    bus.publisher.publish(VaultTopics.ready, {
      'graph': ready.graph,
      'fileRegistry': ready.fileRegistry,
      'config': ready.config,
      'vaultPath': ready.vaultPath,
      'nodeStore': ready.nodeStore,
      'blobStore': ready.blobStore,
      'io': ready.io,
      'changeProvider': ready.changeProvider,
    });
  }

  Future<Graph<NodeRecord>> _loadGraph(VaultStart event) async {
    final records = await event.nodeStore.loadAll(
      vaultId: event.config.vaultId,
    );
    return GraphBuilder()(records) ??
        await _createFreshGraph(event.config, event.nodeStore);
  }

  Future<Graph<NodeRecord>> _createFreshGraph(
    dynamic config,
    dynamic nodeStore,
  ) async {
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

  void _startWatcher(VaultStart event) {
    _fileEventHandler = FileEventHandler(
      vaultPath: event.vaultPath,
      io: event.io,
      changeProvider: event.changeProvider,
    );

    final current = state;
    if (current is VaultReady) {
      _fileEventHandler!.updateContext(
        FileHandlerContext(
          graph: current.graph,
          fileRegistry: current.fileRegistry,
          nodeStore: event.nodeStore,
          blobStore: event.blobStore,
          vaultPath: event.vaultPath,
          vaultId: event.config.vaultId,
          io: event.io,
        ),
      );
    }

    _fileEventSub = _fileEventHandler!.events.listen(
      (e) => add(_FileWatcherEvent(e)),
    );
    _fileEventHandler!.start();
  }

  Future<void> _disposeWatcher() async {
    await _fileEventSub?.cancel();
    _fileEventSub = null;
    await _fileEventHandler?.dispose();
    _fileEventHandler = null;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<void> close() async {
    await _resetSub?.cancel();
    _resetSub = null;
    await _disposeWatcher();
    return super.close();
  }
}
