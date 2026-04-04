import 'dart:typed_data';

import 'package:rhyolite_graph/rhyolite_graph.dart';

import '../changes/i_change_provider.dart';
import '../local/local_blob_store.dart';
import '../platform/i_platform_io.dart';
import 'file_registry.dart';

class DiskApplier {
  const DiskApplier({
    required this.vaultPath,
    required this.fileRegistry,
    required this.localBlobStore,
    required this.remoteBlobStorage,
    required this.vaultId,
    required this.io,
    required this.changeProvider,
  });

  final String vaultPath;
  final FileRegistry fileRegistry;
  final LocalBlobStore localBlobStore;
  final IBlobStorage? remoteBlobStorage;
  final String vaultId;
  final IPlatformIO io;
  final IChangeProvider changeProvider;

  Future<void> call(List<NodeRecord> remoteNodes) async {
    final sorted = [...remoteNodes]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (final record in sorted) {
      switch (record) {
        case VaultRecord():
          break;

        case FileRecord():
          if (record.path.isEmpty) continue;
          fileRegistry.register(record.path, record.fileId, record.key);

        case ChangeRecord():
          final path = fileRegistry.pathByFileId(record.fileId);
          if (path == null || path.isEmpty) continue;
          final fullPath = '$vaultPath/$path';

          changeProvider.suppress(path);
          try {
            final Uint8List bytes;
            final cached = await localBlobStore.read(record.blobId, vaultId: vaultId);
            if (cached != null) {
              bytes = cached;
            } else if (remoteBlobStorage != null) {
              final map = await remoteBlobStorage!.download([record.blobId]);
              bytes = map[record.blobId]!;
              await localBlobStore.write(bytes, record.blobId, vaultId: vaultId);
            } else {
              continue;
            }
            await io.writeFile(fullPath, bytes);
          } finally {
            changeProvider.unsuppress(path);
          }

        case MoveRecord():
          if (record.fromPath.isEmpty || record.toPath.isEmpty) continue;
          final fromFull = '$vaultPath/${record.fromPath}';
          final toFull = '$vaultPath/${record.toPath}';
          changeProvider.suppress(record.fromPath);
          changeProvider.suppress(record.toPath);
          try {
            await io.moveFile(fromFull, toFull);
            fileRegistry.updatePath(record.fromPath, record.toPath);
            final fromDir = fromFull.substring(0, fromFull.lastIndexOf('/'));
            await io.deleteEmptyDirsUpTo(fromDir, vaultPath);
          } finally {
            changeProvider.unsuppress(record.fromPath);
            changeProvider.unsuppress(record.toPath);
          }

        case DeleteRecord():
          final path = fileRegistry.pathByFileId(record.fileId);
          if (path == null || path.isEmpty) continue;
          changeProvider.suppress(path);
          try {
            final fullPath = '$vaultPath/$path';
            await io.deleteFile(fullPath);
            fileRegistry.remove(path);
            final dir = fullPath.substring(0, fullPath.lastIndexOf('/'));
            await io.deleteEmptyDirsUpTo(dir, vaultPath);
          } finally {
            changeProvider.unsuppress(path);
          }
      }
    }
  }
}
