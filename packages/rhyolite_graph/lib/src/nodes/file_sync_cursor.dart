class FileSyncCursor {
  const FileSyncCursor({
    required this.fileId,
    this.lastSyncedKey,
  });

  final String fileId;
  final String? lastSyncedKey;
}
