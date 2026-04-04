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
