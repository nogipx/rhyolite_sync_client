import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('RecordMoveUseCase', () {
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
