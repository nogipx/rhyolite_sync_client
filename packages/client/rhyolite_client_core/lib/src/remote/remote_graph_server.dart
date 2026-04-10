import 'package:rhyolite_graph/rhyolite_graph.dart';

import '../contract/sync_contract.dart';
import '../crypto/node_encryption.dart';

class RemoteGraphServer implements IGraphServer {
  RemoteGraphServer({
    required SyncContractCaller caller,
    required this.vaultId,
    IVaultCipher? cipher,
  }) : _caller = caller, _cipher = cipher;

  final SyncContractCaller _caller;
  final String vaultId;
  final IVaultCipher? _cipher;

  @override
  Future<List<FilePullResult>> pull(List<FileSyncCursor> cursors) async {
    final response = await _caller.pull(
      PullRequest(vaultId: vaultId, cursors: cursors),
    );
    final cipher = _cipher;
    if (cipher == null) return response.results;
    return Future.wait(
      response.results.map((r) async => FilePullResult(
            fileId: r.fileId,
            nodes: await Future.wait(r.nodes.map((n) => decryptNode(n, cipher))),
          )),
    );
  }

  @override
  Future<void> push(List<NodeRecord> nodes) async {
    final cipher = _cipher;
    if (cipher == null) {
      await _caller.push(PushRequest(vaultId: vaultId, nodes: nodes));
      return;
    }
    final encrypted = await Future.wait(nodes.map((n) => encryptNode(n, cipher)));
    await _caller.push(PushRequest(vaultId: vaultId, nodes: encrypted));
  }

  @override
  Future<void> deleteNodes(List<String> keys) async {
    await _caller.deleteNodes(DeleteNodesRequest(vaultId: vaultId, keys: keys));
  }

  @override
  Future<String> acquireLock(String vaultId) async {
    final response = await _caller.acquireLock(
      AcquireLockRequest(vaultId: vaultId),
    );
    return response.lockToken;
  }

  @override
  Future<void> releaseLock(String vaultId, String lockToken) async {
    await _caller.releaseLock(
      ReleaseLockRequest(vaultId: vaultId, lockToken: lockToken),
    );
  }

  @override
  Future<void> renewLock(String vaultId, String lockToken) async {
    await _caller.renewLock(
      RenewLockRequest(vaultId: vaultId, lockToken: lockToken),
    );
  }

  @override
  Future<int> getVaultEpoch() async {
    final response = await _caller.getVaultEpoch(
      GetVaultEpochRequest(vaultId: vaultId),
    );
    return response.epoch;
  }

  @override
  Future<void> resetVault() async {
    await _caller.resetVault(ResetVaultRequest(vaultId: vaultId));
  }
}
