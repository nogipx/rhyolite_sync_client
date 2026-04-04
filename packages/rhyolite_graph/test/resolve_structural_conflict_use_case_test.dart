import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2024);
  final useCase = ResolveStructuralConflictUseCase();

  DeleteRecord delete({required DateTime at}) => DeleteRecord(key: 'x', vaultId: 'v1', isSynced: false, createdAt: at, fileId: 'f1');
  MoveRecord move({required DateTime at}) => MoveRecord(key: 'x', vaultId: 'v1', isSynced: false, createdAt: at, fileId: 'f1', fromPath: '/a', toPath: '/b');
  ChangeRecord change({required DateTime at}) => ChangeRecord(key: 'x', vaultId: 'v1', isSynced: false, createdAt: at, fileId: 'f1', blobId: 'b', sizeBytes: 1);

  group('ResolveStructuralConflictUseCase', () {
    test('deletionIdempotent → AcceptLocal', () {
      final result = useCase(delete(at: now), delete(at: now), ConflictType.deletionIdempotent);
      expect(result, isA<AcceptLocal>());
    });

    test('LWW: local newer → AcceptLocal', () {
      final result = useCase(
        move(at: now.add(Duration(seconds: 1))),
        delete(at: now),
        ConflictType.moveDelete,
      );
      expect(result, isA<AcceptLocal>());
    });

    test('LWW: remote newer → AcceptRemote', () {
      final result = useCase(
        delete(at: now),
        move(at: now.add(Duration(seconds: 1))),
        ConflictType.moveDelete,
      );
      expect(result, isA<AcceptRemote>());
    });

    test('editDelete: local newer → AcceptLocal', () {
      final result = useCase(
        change(at: now.add(Duration(seconds: 1))),
        delete(at: now),
        ConflictType.editDelete,
      );
      expect(result, isA<AcceptLocal>());
    });

    test('contentEdit throws ArgumentError', () {
      expect(
        () => useCase(change(at: now), change(at: now), ConflictType.contentEdit),
        throwsArgumentError,
      );
    });
  });
}
