import 'package:rpc_data/rpc_data.dart';

/// Persisted cache of {mtime_ms, size_bytes, blob_id} per file path.
///
/// Used by [StartupReconciler] to skip reading files whose mtime and size
/// have not changed since the last run.
class FileStatCache {
  FileStatCache(this._repo, this._vaultId);

  final IDataRepository _repo;
  final String _vaultId;

  String get _collection => 'file_stat_cache_$_vaultId';

  Future<CachedFileStat?> get(String relativePath) async {
    final record = await _repo.get(
      GetRecordRequest(collection: _collection, id: relativePath),
    );
    if (record == null) return null;
    return CachedFileStat.fromJson(record.payload);
  }

  Future<void> save(String relativePath, CachedFileStat entry) async {
    final existing = await _repo.get(
      GetRecordRequest(collection: _collection, id: relativePath),
    );
    if (existing == null) {
      await _repo.create(
        CreateRecordRequest(
          collection: _collection,
          id: relativePath,
          payload: entry.toJson(),
        ),
      );
    } else {
      await _repo.update(
        UpdateRecordRequest(
          collection: _collection,
          id: relativePath,
          expectedVersion: existing.version,
          payload: entry.toJson(),
        ),
      );
    }
  }

  Future<void> remove(String relativePath) async {
    await _repo.delete(
      DeleteRecordRequest(collection: _collection, id: relativePath),
    );
  }

  Future<void> clear() async {
    await _repo.deleteCollection(
      DeleteCollectionRequest(collection: _collection),
    );
  }
}

class CachedFileStat {
  const CachedFileStat({
    required this.mtimeMs,
    required this.sizeBytes,
    required this.blobId,
  });

  final int mtimeMs;
  final int sizeBytes;
  final String blobId;

  bool matches(int mtimeMs, int sizeBytes) =>
      this.mtimeMs == mtimeMs && this.sizeBytes == sizeBytes;

  Map<String, Object> toJson() => {
        'mtime_ms': mtimeMs,
        'size_bytes': sizeBytes,
        'blob_id': blobId,
      };

  factory CachedFileStat.fromJson(Map<String, Object?> json) => CachedFileStat(
        mtimeMs: json['mtime_ms'] as int,
        sizeBytes: json['size_bytes'] as int,
        blobId: json['blob_id'] as String,
      );
}
