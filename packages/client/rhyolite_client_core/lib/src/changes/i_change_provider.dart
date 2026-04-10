abstract interface class IChangeProvider {
  Stream<FileChangeEvent> get changes;

  /// Suppresses events for [path] until [unsuppress] is called.
  /// Use before writing a file to disk to avoid echo-back sync loops.
  void suppress(String path);

  /// Removes suppression for [path].
  void unsuppress(String path);
}

sealed class FileChangeEvent {
  const FileChangeEvent();
}

class FileCreatedEvent extends FileChangeEvent {
  const FileCreatedEvent({required this.relativePath});

  final String relativePath;
}

class FileModifiedEvent extends FileChangeEvent {
  const FileModifiedEvent({required this.relativePath});

  final String relativePath;
}

class FileMovedEvent extends FileChangeEvent {
  const FileMovedEvent({required this.fromPath, required this.toPath});

  final String fromPath;
  final String toPath;
}

class FileDeletedEvent extends FileChangeEvent {
  const FileDeletedEvent({required this.relativePath});

  final String relativePath;
}
