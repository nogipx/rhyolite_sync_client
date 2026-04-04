enum ConflictType {
  /// ChangeRecord vs ChangeRecord
  contentEdit,

  /// ChangeRecord vs DeleteRecord
  editDelete,

  /// DeleteRecord vs ChangeRecord
  deleteEdit,

  /// MoveRecord vs MoveRecord
  pathConflict,

  /// MoveRecord vs DeleteRecord or DeleteRecord vs MoveRecord
  moveDelete,

  /// DeleteRecord vs DeleteRecord — idempotent, no real conflict
  deletionIdempotent,
}