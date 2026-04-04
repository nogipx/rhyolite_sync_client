import 'dart:typed_data';

sealed class ResolveResult {
  const ResolveResult();
}

/// Keep the local version
class AcceptLocal extends ResolveResult {
  const AcceptLocal();
}

/// Keep the remote version
class AcceptRemote extends ResolveResult {
  const AcceptRemote();
}

/// Successfully merged — caller creates new ChangeRecord from bytes
class MergedContent extends ResolveResult {
  final Uint8List bytes;
  const MergedContent(this.bytes);
}

/// Keep both versions — caller creates conflict copy
class AcceptBoth extends ResolveResult {
  const AcceptBoth();
}