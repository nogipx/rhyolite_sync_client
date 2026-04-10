part of 'sync_bloc.dart';

sealed class SyncBlocEvent {}

/// Trigger a manual pull (e.g. called from SyncEngine facade).
class SyncTriggerPull extends SyncBlocEvent {}

/// Trigger a vault reset (re-upload everything to server).
class SyncTriggerReset extends SyncBlocEvent {}

/// Trigger a full repair cycle: prune non-canonical branches, run GC,
/// and push the canonical state back to the server.
class SyncTriggerRepair extends SyncBlocEvent {}

// ---------------------------------------------------------------------------
// Internal events
// ---------------------------------------------------------------------------

class _ConnectionOnline extends SyncBlocEvent {
  _ConnectionOnline(this.payload);
  final Map<String, dynamic> payload;
}

class _ConnectionOffline extends SyncBlocEvent {}

class _VaultReady extends SyncBlocEvent {
  _VaultReady(this.payload);
  final Map<String, dynamic> payload;
}

class _FileChanged extends SyncBlocEvent {
  _FileChanged(this.fileId);
  final String fileId;
}

class _OrphanedNodes extends SyncBlocEvent {
  _OrphanedNodes(this.records);
  final List<NodeRecord> records;
}

class _ServerNotifyEvent extends SyncBlocEvent {
  _ServerNotifyEvent(this.payload);
  final Map<String, dynamic> payload;
}

class _FatalError extends SyncBlocEvent {
  _FatalError(this.reason);
  final SyncFailureReason reason;
}

class _LockBusy extends SyncBlocEvent {
  _LockBusy({required this.vaultId, this.lockToken});
  final String vaultId;
  final String? lockToken;
}

class _LockLost extends SyncBlocEvent {
  _LockLost(this.vaultId);
  final String vaultId;
}

class _RetrySync extends SyncBlocEvent {
  _RetrySync();
}
