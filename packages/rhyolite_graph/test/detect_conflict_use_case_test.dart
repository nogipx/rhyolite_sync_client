import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2024);
  final useCase = DetectConflictUseCase();

  NodeRecord change() => ChangeRecord(key: 'x', vaultId: 'v1', isSynced: false, createdAt: now, fileId: 'f1', blobId: 'b', sizeBytes: 1);
  NodeRecord delete() => DeleteRecord(key: 'x', vaultId: 'v1', isSynced: false, createdAt: now, fileId: 'f1');
  NodeRecord move() => MoveRecord(key: 'x', vaultId: 'v1', isSynced: false, createdAt: now, fileId: 'f1', fromPath: '/a', toPath: '/b');

  group('DetectConflictUseCase', () {
    test('ChangeRecord vs ChangeRecord → contentEdit', () {
      expect(useCase(change(), change()), equals(ConflictType.contentEdit));
    });

    test('ChangeRecord vs DeleteRecord → editDelete', () {
      expect(useCase(change(), delete()), equals(ConflictType.editDelete));
    });

    test('DeleteRecord vs ChangeRecord → deleteEdit', () {
      expect(useCase(delete(), change()), equals(ConflictType.deleteEdit));
    });

    test('MoveRecord vs MoveRecord → pathConflict', () {
      expect(useCase(move(), move()), equals(ConflictType.pathConflict));
    });

    test('MoveRecord vs DeleteRecord → moveDelete', () {
      expect(useCase(move(), delete()), equals(ConflictType.moveDelete));
    });

    test('DeleteRecord vs MoveRecord → moveDelete', () {
      expect(useCase(delete(), move()), equals(ConflictType.moveDelete));
    });

    test('DeleteRecord vs DeleteRecord → deletionIdempotent', () {
      expect(useCase(delete(), delete()), equals(ConflictType.deletionIdempotent));
    });

    test('returns null for non-conflicting combination', () {
      final vault = VaultRecord(key: 'x', isSynced: false, createdAt: now, vaultId: 'v', name: 'T');
      expect(useCase(vault, change()), isNull);
    });
  });
}