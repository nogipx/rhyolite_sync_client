import 'package:data_manage/data_manage.dart';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('graph.markSynced', () {
    test('marks existing unsynced nodes as synced', () {
      final r = buildStandardGraph();

      final c3 = r.graph.getNodeData('c3') as ChangeRecord;
      final c4 = r.graph.getNodeData('c4') as ChangeRecord;

      r.graph.markSynced([c3.withSynced(), c4.withSynced()]);

      expect((r.graph.getNodeData('c3') as ChangeRecord).isSynced, isTrue);
      expect((r.graph.getNodeData('c4') as ChangeRecord).isSynced, isTrue);
    });

    test('does not affect already-synced nodes', () {
      final r = buildStandardGraph();

      final c1 = r.graph.getNodeData('c1') as ChangeRecord;
      expect(c1.isSynced, isTrue);

      r.graph.markSynced([c1.withSynced()]);

      expect((r.graph.getNodeData('c1') as ChangeRecord).isSynced, isTrue);
    });

    test('silently skips records whose key is not in graph', () {
      final r = buildStandardGraph();

      final phantom = ChangeRecord(
        key: 'nonexistent',
        vaultId: 'v1',
        parentKey: 'c4',
        isSynced: true,
        createdAt: DateTime(2024),
        fileId: 'f1',
        blobId: 'bx',
        sizeBytes: 0,
      );

      expect(() => r.graph.markSynced([phantom]), returnsNormally);
    });

    test('empty list is a no-op', () {
      final r = buildStandardGraph();

      expect(() => r.graph.markSynced([]), returnsNormally);
      expect((r.graph.getNodeData('c3') as ChangeRecord).isSynced, isFalse);
    });
  });
}
