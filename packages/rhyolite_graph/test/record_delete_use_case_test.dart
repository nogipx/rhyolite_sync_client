import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('RecordDeleteUseCase', () {
    test('returns DeleteRecord with correct fields', () {
      final r = buildStandardGraph();
      final result = RecordDeleteUseCase(r.graph)(r.fileNode);

      expect(result.isSynced, isFalse);
      expect(result.parentKey, equals(r.c4.key));
    });

    test('delete after delete attaches correctly', () {
      final r = buildStandardGraph();
      final useCase = RecordDeleteUseCase(r.graph);

      final first = useCase(r.fileNode);
      r.graph.apply([first]);
      final second = useCase(r.fileNode);

      expect(second.parentKey, equals(first.key));
    });
  });
}
