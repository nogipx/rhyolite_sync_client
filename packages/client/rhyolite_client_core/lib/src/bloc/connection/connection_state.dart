part of 'connection_bloc.dart';

sealed class ConnectionBlocState {}

/// Initial state — no connection attempt started.
class ConnectionIdle extends ConnectionBlocState {}

/// Connecting with exponential backoff.
class ConnectionConnecting extends ConnectionBlocState {
  ConnectionConnecting({required this.attempt});
  final int attempt;
}

/// WebSocket established, server/blobs/notify are ready.
class ConnectionOnline extends ConnectionBlocState {
  ConnectionOnline({
    required this.server,
    required this.blobs,
    required this.notify,
  });

  final IGraphServer server;
  final IBlobStorage blobs;
  final NotifySubscriber notify;
}

/// Transport closed — reconnecting automatically.
class ConnectionOffline extends ConnectionBlocState {}

/// Auth token rejected — must re-authenticate before resuming.
class ConnectionSessionExpired extends ConnectionBlocState {}

/// Subscription expired — must renew before resuming.
class ConnectionSubscriptionExpired extends ConnectionBlocState {}
