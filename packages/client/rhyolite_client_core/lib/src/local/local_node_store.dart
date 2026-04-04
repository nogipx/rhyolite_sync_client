import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:rpc_data/rpc_data.dart';

class LocalNodeStore {
  LocalNodeStore(this._repo);

  final IDataRepository _repo;

  String _collection(String vaultId) => 'nodes_$vaultId';
  String _metaCollection() => 'vault_meta_local';
  String _epochKey(String vaultId) => 'epoch_$vaultId';

  Future<void> save(NodeRecord node) async {
    final collection = _collection(node.vaultId);
    final existing = await _repo.get(
      GetRecordRequest(collection: collection, id: node.key),
    );
    if (existing != null) return;
    await _repo.create(
      CreateRecordRequest(
        collection: collection,
        id: node.key,
        payload: node.toLocalJson(),
      ),
    );
  }

  Future<void> saveAll(List<NodeRecord> nodes) async {
    for (final node in nodes) {
      await save(node);
    }
  }

  Future<NodeRecord?> load(String key, {required String vaultId}) async {
    final record = await _repo.get(
      GetRecordRequest(collection: _collection(vaultId), id: key),
    );
    if (record == null) return null;
    return NodeRecord.fromLocalJson(record.payload);
  }

  Future<List<NodeRecord>> loadAll({required String vaultId}) async {
    final response = await _repo.list(
      ListRecordsRequest(
        collection: _collection(vaultId),
        options: const QueryOptions(limit: 10000),
      ),
    );
    return response.records
        .map((r) => NodeRecord.fromLocalJson(r.payload))
        .toList();
  }

  Future<int> loadResetEpoch({required String vaultId}) async {
    final record = await _repo.get(
      GetRecordRequest(collection: _metaCollection(), id: _epochKey(vaultId)),
    );
    return (record?.payload['epoch'] as int?) ?? 0;
  }

  Future<void> saveResetEpoch(int epoch, {required String vaultId}) async {
    final meta = _metaCollection();
    final key = _epochKey(vaultId);
    final existing = await _repo.get(GetRecordRequest(collection: meta, id: key));
    if (existing == null) {
      await _repo.create(
        CreateRecordRequest(collection: meta, id: key, payload: {'epoch': epoch}),
      );
    } else {
      await _repo.update(
        UpdateRecordRequest(
          collection: meta,
          id: key,
          expectedVersion: existing.version,
          payload: {'epoch': epoch},
        ),
      );
    }
  }

  Future<void> deleteKeys(List<String> keys, {required String vaultId}) async {
    final collection = _collection(vaultId);
    for (final key in keys) {
      await _repo.delete(DeleteRecordRequest(collection: collection, id: key));
    }
  }

  Future<void> deleteAll({required String vaultId}) async {
    await _repo.deleteCollection(
      DeleteCollectionRequest(collection: _collection(vaultId)),
    );
  }

  Future<void> markSynced(String key, {required String vaultId}) async {
    final record = await _repo.get(
      GetRecordRequest(collection: _collection(vaultId), id: key),
    );
    if (record == null) return;
    final node = NodeRecord.fromLocalJson(record.payload);
    await _repo.update(
      UpdateRecordRequest(
        collection: _collection(vaultId),
        id: key,
        expectedVersion: record.version,
        payload: node.withSynced().toLocalJson(),
      ),
    );
  }
}
