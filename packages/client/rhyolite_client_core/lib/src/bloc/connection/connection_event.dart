part of 'connection_bloc.dart';

sealed class ConnectionBlocEvent {}

/// Start connecting with the given parameters.
class ConnectionStart extends ConnectionBlocEvent {
  ConnectionStart({
    required this.config,
    required this.serverUrl,
    this.cipher,
    this.rateLimiter,
  });

  final VaultConfig config;
  final String serverUrl;
  final IVaultCipher? cipher;
  final RateLimiter? rateLimiter;
}

/// Disconnect and stop reconnecting.
class ConnectionStop extends ConnectionBlocEvent {}

/// Resume connecting after session/subscription expiry.
class ConnectionResume extends ConnectionBlocEvent {}

/// Force a reconnect (e.g. after server-side failure detected by SyncBloc).
class ConnectionForceReconnect extends ConnectionBlocEvent {}

/// Internal: wraps a raw [cm.ConnectionEvent] from [cm.ConnectionManager].
class _ManagerEvent extends ConnectionBlocEvent {
  _ManagerEvent(this.event);
  final cm.ConnectionEvent event;
}
