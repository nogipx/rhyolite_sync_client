import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('RecordChangeUseCase', () {
    test('adds ChangeNode to graph after current leaf', () {
      final r = buildStandardGraph();
      final useCase = RecordChangeUseCase(r.graph);

      useCase(r.fileNode, 'blob5', 50);

      final leaf = r.graph.findLeaf(r.fileNode);
      expect(r.graph.getNodeData(leaf.key), isA<ChangeRecord>());
      expect(r.graph.getNodeParent(leaf), equals(r.c4));
    });

    test('returns ChangeRecord with correct fields', () {
      final r = buildStandardGraph();
      final result = RecordChangeUseCase(r.graph)(r.fileNode, 'blob5', 50);

      expect(result.blobId, equals('blob5'));
      expect(result.sizeBytes, equals(50));
      expect(result.isSynced, isFalse);
      expect(result.parentKey, equals(r.c4.key));
    });

    test('key is deterministic: same parent + blobId → same key', () {
      final r = buildStandardGraph();
      final r2 = buildStandardGraph();

      final first = RecordChangeUseCase(r.graph)(r.fileNode, 'blob5', 10);
      final second = RecordChangeUseCase(r2.graph)(r2.fileNode, 'blob5', 10);

      expect(first.key, equals(second.key));
    });

    test('key differs for different blobId', () {
      final r = buildStandardGraph();
      final useCase = RecordChangeUseCase(r.graph);

      final first = useCase(r.fileNode, 'blob5', 10);
      final second = useCase(r.fileNode, 'blob6', 20);

      expect(first.key, isNot(equals(second.key)));
    });

    test('chained calls attach each node after previous', () {
      final r = buildStandardGraph();
      final useCase = RecordChangeUseCase(r.graph);

      final first = useCase(r.fileNode, 'blob5', 10);
      final second = useCase(r.fileNode, 'blob6', 20);

      expect(second.parentKey, equals(first.key));
    });
  });
}
