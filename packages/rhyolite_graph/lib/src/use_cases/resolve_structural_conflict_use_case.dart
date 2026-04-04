import 'package:rhyolite_graph/rhyolite_graph.dart';

class ResolveStructuralConflictUseCase {
  const ResolveStructuralConflictUseCase();

  ResolveResult call(NodeRecord local, NodeRecord remote, ConflictType type) => switch (type) {
        ConflictType.deletionIdempotent => const AcceptLocal(),
        ConflictType.contentEdit => throw ArgumentError(
            'contentEdit must be resolved by ResolveContentConflictUseCase',
          ),
        _ => _lww(local, remote),
      };

  ResolveResult _lww(NodeRecord local, NodeRecord remote) =>
      local.createdAt.isAfter(remote.createdAt) ? const AcceptLocal() : const AcceptRemote();
}