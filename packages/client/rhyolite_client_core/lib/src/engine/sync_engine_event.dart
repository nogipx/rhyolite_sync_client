sealed class SyncEngineEvent {
  SyncEngineEvent() : timestamp = DateTime.now();

  final DateTime timestamp;
}

class SyncStarted extends SyncEngineEvent {
  SyncStarted();
}

class SyncStopped extends SyncEngineEvent {
  SyncStopped();
}

class SyncLogMessage extends SyncEngineEvent {
  SyncLogMessage(this.message);

  final String message;
}

class SyncFileCreated extends SyncEngineEvent {
  SyncFileCreated(this.path);

  final String path;
}

class SyncFileModified extends SyncEngineEvent {
  SyncFileModified(this.path);

  final String path;
}

class SyncFileMoved extends SyncEngineEvent {
  SyncFileMoved({required this.fromPath, required this.toPath});

  final String fromPath;
  final String toPath;
}

class SyncFileDeleted extends SyncEngineEvent {
  SyncFileDeleted(this.path);

  final String path;
}

class SyncFilePushed extends SyncEngineEvent {
  SyncFilePushed(this.path);

  final String path;
}

class SyncFilePulled extends SyncEngineEvent {
  SyncFilePulled({required this.fileId, required this.nodeCount});

  final String fileId;
  final int nodeCount;
}

class SyncError extends SyncEngineEvent {
  SyncError(this.message);

  final String message;
}

class SyncConnecting extends SyncEngineEvent {
  SyncConnecting({required this.attempt});

  final int attempt;
}

class SyncConnected extends SyncEngineEvent {
  SyncConnected();
}

class SyncDisconnected extends SyncEngineEvent {
  SyncDisconnected();
}

/// Emitted when the server signals a vault reset.
/// The engine wipes local state and re-uploads from disk.
class SyncVaultReset extends SyncEngineEvent {
  SyncVaultReset();
}

/// Emitted when the server rejects the session because the refresh token has
/// expired. The engine stops itself after emitting this event. The host
/// application should clear the stored session and prompt the user to sign in.
class SyncSessionExpired extends SyncEngineEvent {
  SyncSessionExpired();
}

/// Emitted when the server rejects the request because the user has no active
/// subscription. The engine stops itself after emitting this event. The host
/// application should prompt the user to renew their subscription.
class SyncSubscriptionExpired extends SyncEngineEvent {
  SyncSubscriptionExpired();
}
