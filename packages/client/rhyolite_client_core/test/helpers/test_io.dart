import 'dart:io';
import 'dart:typed_data';

import 'package:rhyolite_client_core/src/platform/i_platform_io.dart';

/// dart:io-backed IPlatformIO for use in tests only.
class TestIO implements IPlatformIO {
  @override
  Future<Uint8List> readFile(String path) => File(path).readAsBytes();

  @override
  Future<bool> fileExists(String path) async => File(path).existsSync();

  @override
  Future<bool> dirExists(String path) async => Directory(path).existsSync();

  @override
  Future<List<String>> listFiles(String dirPath) async {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return [];
    return dir
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .map((f) => f.path)
        .toList();
  }

  @override
  Future<void> writeFile(String path, Uint8List bytes) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<void> moveFile(String from, String to) async {
    await File(to).parent.create(recursive: true);
    try {
      await File(from).rename(to);
    } catch (_) {}
  }

  @override
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  @override
  Future<FileStatInfo?> statFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) return null;
    final stat = file.statSync();
    return FileStatInfo(
      mtimeMs: stat.modified.millisecondsSinceEpoch,
      sizeBytes: stat.size,
    );
  }

  @override
  Future<void> deleteEmptyDirsUpTo(String dirPath, String stopAt) async {
    var current = dirPath;
    while (current != stopAt && current.startsWith(stopAt)) {
      final dir = Directory(current);
      if (!dir.existsSync()) {
        current = dir.parent.path;
        continue;
      }
      if (dir.listSync().isEmpty) {
        dir.deleteSync();
        current = dir.parent.path;
      } else {
        break;
      }
    }
  }
}
