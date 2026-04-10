part of 'vault_bloc.dart';

sealed class VaultBlocState {}

/// No vault loaded.
class VaultIdle extends VaultBlocState {}

/// Graph is loading / reconciliation is running.
class VaultLoading extends VaultBlocState {}

/// Vault is ready — graph and registry are live.
/// File watcher is running. Network is not required for this state.
class VaultReady extends VaultBlocState {
  VaultReady({
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
