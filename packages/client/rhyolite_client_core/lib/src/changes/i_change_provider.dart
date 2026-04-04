import 'file_change_event.dart';

abstract interface class IChangeProvider {
  Stream<FileChangeEvent> get changes;

  /// Suppresses events for [path] until [unsuppress] is called.
  /// Use before writing a file to disk to avoid echo-back sync loops.
  void suppress(String path);

  /// Removes suppression for [path].
  void unsuppress(String path);
}
