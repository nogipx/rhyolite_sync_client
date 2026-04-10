import 'dart:typed_data';
import 'package:rhyolite_graph/rhyolite_graph.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('PushUseCase', () {
    test('does nothing when no unsynced nodes', () async {
      final r = buildStandardGraph();
      r.graph.markSynced([
        (r.graph.getNodeData('c3') as ChangeRecord).withSynced(),
        (r.graph.getNodeData('c4') as ChangeRecord).withSynced(),
      ]);

      final server = MockGraphServer();
      final synced = await PushUseCase(
        graph: r.graph,
        server: server,
        localBlobs: MockBlobStorage(),
        remoteBlobs: MockBlobStorage(),
      )([r.fileNode]);

      expect(server.pushedNodes, isNull);
      expect(synced, isEmpty);
    });

    test('pushes unsynced nodes to server in correct order', () async {
      final r = buildStandardGraph();
      final localBlobs = MockBlobStorage({
        'blob3': Uint8List.fromList([1, 2, 3]),
        'blob4': Uint8List.fromList([4, 5, 6]),
      });
      final server = MockGraphServer();

      await PushUseCase(
        graph: r.graph,
        server: server,
        localBlobs: localBlobs,
        remoteBlobs: MockBlobStorage(),
      )([r.fileNode]);

      expect(server.pushedNodes?.map((n) => n.key), equals(['c3', 'c4']));
    });

    test('uploads blobs for ChangeRecords to remote storage', () async {
      final r = buildStandardGraph();
      final localBlobs = MockBlobStorage({
        'blob3': Uint8List.fromList([1, 2, 3]),
        'blob4': Uint8List.fromList([4, 5, 6]),
      });
      final remoteBlobs = MockBlobStorage();

      await PushUseCase(
        graph: r.graph,
        server: MockGraphServer(),
        localBlobs: localBlobs,
        remoteBlobs: remoteBlobs,
      )([r.fileNode]);

      expect(remoteBlobs.store.length, equals(2));
    });

    test('returns synced versions of pushed records', () async {
      final r = buildStandardGraph();
      final localBlobs = MockBlobStorage({
        'blob3': Uint8List.fromList([1]),
        'blob4': Uint8List.fromList([2]),
      });

      final synced = await PushUseCase(
        graph: r.graph,
        server: MockGraphServer(),
        localBlobs: localBlobs,
        remoteBlobs: MockBlobStorage(),
      )([r.fileNode]);

      expect(synced.length, equals(2));
      expect(synced.every((r) => r.isSynced), isTrue);
      expect(synced.map((r) => r.key), containsAll(['c3', 'c4']));
    });

    test('graph is not mutated by push', () async {
      final r = buildStandardGraph();
      final localBlobs = MockBlobStorage({
        'blob3': Uint8List.fromList([1]),
        'blob4': Uint8List.fromList([2]),
      });

      await PushUseCase(
        graph: r.graph,
        server: MockGraphServer(),
        localBlobs: localBlobs,
        remoteBlobs: MockBlobStorage(),
      )([r.fileNode]);

      expect((r.graph.getNodeData('c3') as ChangeRecord).isSynced, isFalse);
      expect((r.graph.getNodeData('c4') as ChangeRecord).isSynced, isFalse);
    });
  });
}
