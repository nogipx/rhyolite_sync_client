import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('RecordMoveUseCase', () {
    test('adds MoveNode to graph after current leaf', () {
      final r = buildStandardGraph();
      RecordMoveUseCase(r.graph)(r.fileNode, '/old.md', '/new.md');

      final leaf = r.graph.findLeaf(r.fileNode);
      expect(r.graph.getNodeData(leaf.key), isA<MoveRecord>());
      expect(r.graph.getNodeParent(leaf), equals(r.c4));
    });

    test('returns MoveRecord with correct fields', () {
      final r = buildStandardGraph();
      final result = RecordMoveUseCase(r.graph)(r.fileNode, '/old.md', '/new.md');

      expect(result.fromPath, equals('/old.md'));
      expect(result.toPath, equals('/new.md'));
      expect(result.isSynced, isFalse);
      expect(result.parentKey, equals(r.c4.key));
    });
  });
}
