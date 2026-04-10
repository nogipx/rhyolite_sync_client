part of 'vault_bloc.dart';

sealed class VaultBlocEvent {}

/// Initialize vault: load graph from SQLite, reconcile disk, start watcher.
class VaultStart extends VaultBlocEvent {
  VaultStart({
    required this.vaultPath,
    required this.config,
    required this.nodeStore,
    required this.blobStore,
    required this.io,
    required this.changeProvider,
    this.statCache,
  });

  final String vaultPath;
  final VaultConfig config;
  final LocalNodeStore nodeStore;
  final LocalBlobStore blobStore;
  final IPlatformIO io;
  final IChangeProvider changeProvider;
  final FileStatCache? statCache;
}

/// Stop file watcher and release resources.
class VaultStop extends VaultBlocEvent {}

/// Wipe local state and re-reconcile from disk (triggered by server reset).
class VaultReset extends VaultBlocEvent {
  VaultReset({this.newEpoch});
  final int? newEpoch;
}

/// Internal: raw [SyncEngineEvent] from [FileEventHandler].
class _FileWatcherEvent extends VaultBlocEvent {
  _FileWatcherEvent(this.engineEvent);
  final Object engineEvent;
}

