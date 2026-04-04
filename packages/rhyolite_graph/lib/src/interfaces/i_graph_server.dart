import 'package:rhyolite_graph/rhyolite_graph.dart';

abstract interface class IGraphServer {
  Future<List<FilePullResult>> pull(List<FileSyncCursor> cursors);
  Future<void> push(List<NodeRecord> nodes);
  Future<String> acquireLock(String vaultId);
  Future<void> releaseLock(String vaultId, String lockToken);
  Future<int> getVaultEpoch();
  Future<void> resetVault();
}