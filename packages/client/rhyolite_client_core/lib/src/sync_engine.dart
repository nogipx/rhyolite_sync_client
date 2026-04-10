import 'dart:async';

import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:rpc_notify/rpc_notify.dart';

import 'bloc/connection/connection_bloc.dart';
import 'bloc/sync/sync_bloc.dart';
import 'bloc/vault/vault_bloc.dart';
import 'changes/i_change_provider.dart';
import 'engine/rate_limiter.dart';
import 'engine/sync_engine_event.dart';
import 'engine/vault_config.dart';
import 'local/file_stat_cache.dart';
import 'local/local_blob_store.dart';
import 'local/local_node_store.dart';
import 'platform/i_platform_io.dart';

/// Facade over [ConnectionBloc], [VaultBloc], and [SyncBloc].
/// Preserves the public API expected by the Obsidian plugin.
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
    this.statCache,
    this.rateLimiter,
  });

  final String vaultPath;
  String serverUrl;
  VaultConfig config;
  IVaultCipher? cipher;

  final LocalNodeStore nodeStore;
  final LocalBlobStore blobStore;
  final IPlatformIO io;
  final IChangeProvider changeProvider;
  final FileStatCache? statCache;
  final RateLimiter? rateLimiter;

  DirectNotifyServiceEnvironment? _bus;
  ConnectionBloc? _connectionBloc;
  VaultBloc? _vaultBloc;
  SyncBloc? _syncBloc;

  final _eventsController = StreamController<SyncEngineEvent>.broadcast();
  StreamSubscription? _connectionSub;
  StreamSubscription? _syncSub;

  Stream<SyncEngineEvent> get events => _eventsController.stream;

  IGraph<NodeRecord> get graph {
    final s = _vaultBloc?.state;
    if (s is VaultReady) return s.graph;
    // Return an empty graph when vault is not yet loaded.
    return Graph<NodeRecord>(root: VaultNode(''));
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> start() async {
    await stop();

    _bus = DirectNotifyServiceEnvironment();
    _connectionBloc = ConnectionBloc(bus: _bus!);
    _vaultBloc = VaultBloc(bus: _bus!);
    _syncBloc = SyncBloc(bus: _bus!);

    _connectionSub = _connectionBloc!.stream.listen(_onConnectionState);
    _syncSub = _syncBloc!.stream.listen(_onSyncState);

    _vaultBloc!.add(
      VaultStart(
        vaultPath: vaultPath,
        config: config,
        nodeStore: nodeStore,
        blobStore: blobStore,
        io: io,
        changeProvider: changeProvider,
        statCache: statCache,
      ),
    );

    _connectionBloc!.add(
      ConnectionStart(
        config: config,
        serverUrl: serverUrl,
        cipher: cipher,
        rateLimiter: rateLimiter,
      ),
    );
  }

  Future<void> stop() async {
    _connectionBloc?.add(ConnectionStop());
    _vaultBloc?.add(VaultStop());

    await _connectionSub?.cancel();
    await _syncSub?.cancel();
    _connectionSub = null;
    _syncSub = null;

    await _connectionBloc?.close();
    await _vaultBloc?.close();
    await _syncBloc?.close();
    _connectionBloc = null;
    _vaultBloc = null;
    _syncBloc = null;
    _bus = null;
  }

  Future<void> triggerPull() async {
    _syncBloc?.add(SyncTriggerPull());
  }

  Future<void> triggerReset() async {
    _syncBloc?.add(SyncTriggerReset());
  }

  Future<void> triggerRepair() async {
    _syncBloc?.add(SyncTriggerRepair());
  }

  Future<void> dispose() async {
    await stop();
    await _eventsController.close();
  }

  // ---------------------------------------------------------------------------
  // State → SyncEngineEvent mapping
  // ---------------------------------------------------------------------------

  void _onConnectionState(ConnectionBlocState state) {
    switch (state) {
      case ConnectionConnecting(:final attempt):
        _emit(SyncConnecting(attempt: attempt));
      case ConnectionOnline():
        _emit(SyncConnected());
      case ConnectionOffline():
        _emit(SyncDisconnected());
      case ConnectionSessionExpired():
        _emit(SyncSessionExpired());
      case ConnectionSubscriptionExpired():
        _emit(SyncSubscriptionExpired());
      case ConnectionIdle():
        break;
    }
  }

  void _onSyncState(SyncBlocState state) {
    switch (state) {
      case SyncFailed(:final reason):
        switch (reason) {
          case SyncFailureReason.sessionExpired:
            _emit(SyncSessionExpired());
          case SyncFailureReason.subscriptionExpired:
            _emit(SyncSubscriptionExpired());
        }
      case SyncActive():
      case SyncBusy():
      case SyncOffline():
      case SyncIdle():
        break;
    }
  }

  void _emit(SyncEngineEvent event) {
    if (!_eventsController.isClosed) _eventsController.add(event);
  }
}
