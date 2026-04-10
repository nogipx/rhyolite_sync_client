import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:rhyolite_client_core/rhyolite_client_core.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:rpc_notify/rpc_notify.dart';

import '../../engine/connection_manager.dart' as cm;
import '../../remote/rate_limited_blob_storage.dart';
import '../../remote/rate_limited_graph_server.dart';

part 'connection_event.dart';
part 'connection_state.dart';

/// Bus topics published by [ConnectionBloc].
abstract final class ConnectionTopics {
  static const online = 'connection:online';
  static const offline = 'connection:offline';
  static const expired = 'connection:expired';
}

class ConnectionBloc extends Bloc<ConnectionBlocEvent, ConnectionBlocState> {
  /// [bus] — shared in-process notification environment.
  /// All blocs receive the same instance so they share one transport.
  ConnectionBloc({required this.bus}) : super(ConnectionIdle()) {
    on<ConnectionStart>(_onStart);
    on<ConnectionStop>(_onStop);
    on<ConnectionResume>(_onResume);
    on<ConnectionForceReconnect>(_onForceReconnect);
    on<_ManagerEvent>(_onManagerEvent);
  }

  final DirectNotifyServiceEnvironment bus;

  cm.ConnectionManager? _manager;
  StreamSubscription<cm.ConnectionEvent>? _managerSub;
  RateLimiter? _rateLimiter;

  // ---------------------------------------------------------------------------
  // Event handlers
  // ---------------------------------------------------------------------------

  Future<void> _onStart(
    ConnectionStart event,
    Emitter<ConnectionBlocState> emit,
  ) async {
    await _disposeManager();
    _rateLimiter = event.rateLimiter;

    _manager = cm.ConnectionManager(
      serverUrl: event.serverUrl,
      vaultId: event.config.vaultId,
      tokenProvider: event.config.tokenProvider,
      cipher: event.cipher,
    );

    _managerSub = _manager!.events.listen((e) => add(_ManagerEvent(e)));

    _manager!.connect();
  }

  Future<void> _onStop(
    ConnectionStop event,
    Emitter<ConnectionBlocState> emit,
  ) async {
    await _disposeManager();
    emit(ConnectionIdle());
  }

  void _onResume(ConnectionResume event, Emitter<ConnectionBlocState> emit) {
    if (state is ConnectionSessionExpired ||
        state is ConnectionSubscriptionExpired) {
      _manager?.connect();
    }
  }

  void _onForceReconnect(
    ConnectionForceReconnect event,
    Emitter<ConnectionBlocState> emit,
  ) {
    _manager?.forceReconnect();
  }

  Future<void> _onManagerEvent(
    _ManagerEvent event,
    Emitter<ConnectionBlocState> emit,
  ) async {
    switch (event.event) {
      case cm.ConnectionAttempting(:final attempt):
        emit(ConnectionConnecting(attempt: attempt));

      case cm.ConnectionEstablished(:final server, :final blobs, :final notify):
        final wrappedServer = _rateLimiter != null
            ? RateLimitedGraphServer(server, _rateLimiter!)
            : server as IGraphServer;
        final wrappedBlobs = _rateLimiter != null
            ? RateLimitedBlobStorage(blobs, _rateLimiter!)
            : blobs as IBlobStorage;
        final newState = ConnectionOnline(
          server: wrappedServer,
          blobs: wrappedBlobs,
          notify: notify,
        );
        emit(newState);
        bus.publisher.publish(ConnectionTopics.online, {
          'server': wrappedServer,
          'blobs': wrappedBlobs,
          'notify': notify,
        });

      case cm.ConnectionLost():
        emit(ConnectionOffline());
        bus.publisher.publish(ConnectionTopics.offline, {});

      case cm.ConnectionSessionExpired():
        emit(ConnectionSessionExpired());
        bus.publisher.publish(ConnectionTopics.expired, {'reason': 'session'});

      case cm.ConnectionSubscriptionExpired():
        emit(ConnectionSubscriptionExpired());
        bus.publisher.publish(ConnectionTopics.expired, {
          'reason': 'subscription',
        });
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> _disposeManager() async {
    await _managerSub?.cancel();
    _managerSub = null;
    await _manager?.dispose();
    _manager = null;
  }

  @override
  Future<void> close() async {
    await _disposeManager();
    return super.close();
  }
}
