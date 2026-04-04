import 'dart:typed_data';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final now = DateTime(2024);

  ChangeRecord makeChange({required String key, required String blobId, required DateTime at}) =>
      ChangeRecord(key: key, vaultId: 'v1', isSynced: false, createdAt: at, fileId: 'f1', blobId: blobId, sizeBytes: 10);

  group('ResolveContentConflictUseCase', () {
    final baseBlob = Uint8List.fromList([1, 2, 3]);
    final localBlob = Uint8List.fromList([1, 2, 3, 4]);
    final remoteBlob = Uint8List.fromList([1, 2, 3, 5]);
    final mergedBlob = Uint8List.fromList([1, 2, 3, 4, 5]);

    final storage = MockBlobStorage({
      'base': baseBlob,
      'local': localBlob,
      'remote': remoteBlob,
    });

    final base = makeChange(key: 'base', blobId: 'base', at: now);
    final local = makeChange(key: 'local', blobId: 'local', at: now.add(Duration(seconds: 2)));
    final remote = makeChange(key: 'remote', blobId: 'remote', at: now.add(Duration(seconds: 1)));

    test('merge succeeds → MergedContent with merged bytes', () async {
      final useCase = ResolveContentConflictUseCase(
        blobStorage: storage,
        merger: MockContentMerger(mergeResult: mergedBlob),
      );

      final result = await useCase(local, remote, base, ResolveStrategy.lww);
      expect(result, isA<MergedContent>());
      expect((result as MergedContent).bytes, equals(mergedBlob));
    });

    test('merge fails + LWW: local newer → AcceptLocal', () async {
      final useCase = ResolveContentConflictUseCase(
        blobStorage: storage,
        merger: MockContentMerger(mergeResult: null),
      );

      final result = await useCase(local, remote, base, ResolveStrategy.lww);
      expect(result, isA<AcceptLocal>());
    });

    test('merge fails + LWW: remote newer → AcceptRemote', () async {
      final useCase = ResolveContentConflictUseCase(
        blobStorage: storage,
        merger: MockContentMerger(mergeResult: null),
      );

      final olderLocal = makeChange(key: 'local', blobId: 'local', at: now.add(Duration(seconds: 1)));
      final newerRemote = makeChange(key: 'remote', blobId: 'remote', at: now.add(Duration(seconds: 2)));

      final result = await useCase(olderLocal, newerRemote, base, ResolveStrategy.lww);
      expect(result, isA<AcceptRemote>());
    });

    test('merge fails + conflictCopy → AcceptBoth', () async {
      final useCase = ResolveContentConflictUseCase(
        blobStorage: storage,
        merger: MockContentMerger(mergeResult: null),
      );

      final result = await useCase(local, remote, base, ResolveStrategy.conflictCopy);
      expect(result, isA<AcceptBoth>());
    });
  });
}
