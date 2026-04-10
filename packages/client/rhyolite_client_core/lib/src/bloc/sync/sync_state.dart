part of 'sync_bloc.dart';

sealed class SyncBlocState {}

/// Waiting for vault or connection — no sync activity.
class SyncIdle extends SyncBlocState {}

/// Both vault and connection are available; sync is running or standing by.
class SyncActive extends SyncBlocState {
  SyncActive({this.lastSyncAt, this.isPulling = false, this.lockToken});
  final DateTime? lastSyncAt;
  final bool isPulling;
  final String? lockToken;

  bool get hasLock => lockToken != null;

  SyncActive copyWith({
    DateTime? lastSyncAt,
    bool? isPulling,
    String? lockToken,
    bool clearLockToken = false,
  }) => SyncActive(
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    isPulling: isPulling ?? this.isPulling,
    lockToken: clearLockToken ? null : (lockToken ?? this.lockToken),
  );
}

/// Connection lost; vault changes are recorded locally.
class SyncOffline extends SyncBlocState {}

/// Another client currently holds the vault lock.
class SyncBusy extends SyncBlocState {
  SyncBusy({this.vaultId, this.lockToken, this.retryAfter});

  final String? vaultId;
  final String? lockToken;
  final Duration? retryAfter;
}

/// Fatal error — requires user intervention (session/subscription expired).
class SyncFailed extends SyncBlocState {
  SyncFailed(this.reason);
  final SyncFailureReason reason;
}

enum SyncFailureReason { sessionExpired, subscriptionExpired }
