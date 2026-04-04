import 'dart:async';

import 'package:rhyolite_client_account/rhyolite_client_account.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:rpc_dart_websocket/rpc_dart_websocket.dart';
import 'package:rpc_notify/rpc_notify.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../contract/blob_contract.dart';
import '../contract/sync_contract.dart';
import '../remote/remote_blob_storage.dart';
import '../remote/remote_graph_server.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

sealed class ConnectionEvent {}

class ConnectionAttempting extends ConnectionEvent {
  ConnectionAttempting({required this.attempt});
  final int attempt;
}

class ConnectionEstablished extends ConnectionEvent {
  ConnectionEstablished({
    required this.server,
    required this.blobs,
    required this.notify,
  });
  final RemoteGraphServer server;
  final RemoteBlobStorage blobs;
  final NotifySubscriber notify;
}

class ConnectionLost extends ConnectionEvent {}

class ConnectionSessionExpired extends ConnectionEvent {}

class ConnectionSubscriptionExpired extends ConnectionEvent {}

// ---------------------------------------------------------------------------
// Manager
// ---------------------------------------------------------------------------

class ConnectionManager {
  ConnectionManager({
    required this.serverUrl,
    required this.vaultId,
    this.tokenProvider,
    required this.cipher,
  });

  final String serverUrl;
  final String vaultId;
  final IBearerTokenProvider? tokenProvider;
  final IVaultCipher? cipher;

  static const _reconnectDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  final _controller = StreamController<ConnectionEvent>.broadcast();

  Stream<ConnectionEvent> get events => _controller.stream;

  bool get isConnected => _isConnected;

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isStopped = false;

  late WebSocketChannel _channel;

  void connect() {
    _isStopped = false;
    _connectWithBackoff();
  }

  /// Forces a disconnect and triggers the backoff reconnect loop.
  /// Use when a higher-level caller detects a server-side failure.
  void forceReconnect() => _onTransportClosed();

  Future<void> stopOnline() async {
    _isConnected = false;
    try {
      await _channel.sink.close();
    } catch (_) {}
  }

  Future<void> dispose() async {
    _isStopped = true;
    await stopOnline();
    await _controller.close();
  }

  Future<void> _connectWithBackoff() async {
    if (_isConnecting) return;
    _isConnecting = true;
    var attempt = 0;
    while (!_isStopped && !_isConnected) {
      if (attempt > 0) {
        final delay =
            _reconnectDelays[attempt.clamp(0, _reconnectDelays.length - 1)];
        _emit(ConnectionAttempting(attempt: attempt));
        await Future.delayed(delay);
      }
      if (_isStopped) break;
      try {
        final (server, blobs, notify) = await _connectAndBuild();
        _isConnected = true;
        _watchChannelClose();
        _emit(
          ConnectionEstablished(server: server, blobs: blobs, notify: notify),
        );
      } catch (e) {
        if (_isSessionExpired(e)) {
          await stopOnline();
          _emit(ConnectionSessionExpired());
          break;
        }
        if (_isSubscriptionExpired(e)) {
          await stopOnline();
          _emit(ConnectionSubscriptionExpired());
          break;
        }
        attempt++;
      }
    }
    _isConnecting = false;
  }

  Future<(RemoteGraphServer, RemoteBlobStorage, NotifySubscriber)>
  _connectAndBuild() async {
    _channel = WebSocketChannel.connect(_toWsUri(serverUrl));
    await _channel.ready;

    final endpoint = RpcCallerEndpoint(
      transport: RpcWebSocketCallerTransport(_channel),
    );
    if (tokenProvider != null) {
      endpoint.addInterceptor(BearerTokenInterceptor(tokenProvider!));
    }

    final server = RemoteGraphServer(
      caller: SyncContractCaller(endpoint),
      vaultId: vaultId,
      cipher: cipher,
    );
    final blobs = RemoteBlobStorage(
      caller: BlobContractCaller(endpoint),
      vaultId: vaultId,
      cipher: cipher,
    );
    final notify = NotifySubscriber.endpoint(endpoint);

    // Verify subscription is active before declaring the connection established.
    // If payment_required is thrown here, _connectWithBackoff will catch it and
    // emit ConnectionSubscriptionExpired instead of retrying indefinitely.
    await server.getVaultEpoch();

    return (server, blobs, notify);
  }

  void _watchChannelClose() {
    _channel.sink.done
        .then((_) {
          if (!_isStopped) _onTransportClosed();
        })
        .catchError((Object _) {
          if (!_isStopped) _onTransportClosed();
        });
  }

  void _onTransportClosed() {
    if (!_isConnected) return;
    _isConnected = false;
    try {
      _channel.sink.close();
    } catch (_) {}
    _emit(ConnectionLost());
    _connectWithBackoff();
  }

  Uri _toWsUri(String url) {
    final uri = Uri.parse(url);
    final scheme = (uri.scheme == 'https' || uri.scheme == 'wss') ? 'wss' : 'ws';
    return uri.replace(scheme: scheme);
  }

  bool _isSessionExpired(Object e) =>
      e.toString().toLowerCase().contains('unauthenticated');

  bool _isSubscriptionExpired(Object e) =>
      e.toString().toLowerCase().contains('payment_required');

  void _emit(ConnectionEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }
}
