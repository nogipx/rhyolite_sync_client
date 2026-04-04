import 'package:rhyolite_graph/rhyolite_graph.dart';

class DetectConflictUseCase {
  const DetectConflictUseCase();

  ConflictType? call(NodeRecord local, NodeRecord remote) => switch ((local, remote)) {
        (ChangeRecord(), ChangeRecord()) => ConflictType.contentEdit,
        (ChangeRecord(), DeleteRecord()) => ConflictType.editDelete,
        (DeleteRecord(), ChangeRecord()) => ConflictType.deleteEdit,
        (MoveRecord(), MoveRecord()) => ConflictType.pathConflict,
        (MoveRecord(), DeleteRecord()) || (DeleteRecord(), MoveRecord()) => ConflictType.moveDelete,
        (DeleteRecord(), DeleteRecord()) => ConflictType.deletionIdempotent,
        _ => null,
      };
}