import 'dart:async';

import 'package:obsidian_dart/obsidian_dart.dart';
import 'package:rhyolite_client_core/rhyolite_client_core.dart' as core;

class ObsidianChangeProvider implements core.IChangeProvider {
  ObsidianChangeProvider(this._plugin);

  final PluginHandle _plugin;

  StreamController<core.FileChangeEvent>? _controller;
  VaultEvents? _vaultEvents;
  final Set<String> _suppressed = {};

  @override
  void suppress(String path) => _suppressed.add(path);

  @override
  void unsuppress(String path) => _suppressed.remove(path);

  @override
  Stream<core.FileChangeEvent> get changes {
    _controller ??= StreamController<core.FileChangeEvent>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
    return _controller!.stream;
  }

  void _start() {
    final events = VaultEvents(_plugin)..attach();
    _vaultEvents = events;

    events.created.listen((e) {
      if (!_suppressed.contains(e.file.path)) {
        _controller?.add(core.FileCreatedEvent(relativePath: e.file.path));
      }
    });

    events.modified.listen((e) {
      if (!_suppressed.contains(e.file.path)) {
        _controller?.add(core.FileModifiedEvent(relativePath: e.file.path));
      }
    });

    events.deleted.listen((e) {
      if (!_suppressed.contains(e.file.path)) {
        _controller?.add(core.FileDeletedEvent(relativePath: e.file.path));
      }
    });

    events.renamed.listen((e) {
      final oldPath = e.oldPath;
      if (oldPath != null) {
        if (!_suppressed.contains(oldPath) && !_suppressed.contains(e.file.path)) {
          _controller?.add(core.FileMovedEvent(fromPath: oldPath, toPath: e.file.path));
        }
      } else {
        // Obsidian can fire rename without oldPath on some edge cases — treat as create.
        if (!_suppressed.contains(e.file.path)) {
          _controller?.add(core.FileCreatedEvent(relativePath: e.file.path));
        }
      }
    });
  }

  void _stop() {
    _vaultEvents?.dispose();
    _vaultEvents = null;
    _controller = null;
  }
}
