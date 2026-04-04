import 'dart:io';

// ignore: implementation_imports
import 'package:obsidian_dart/src/compose/build_common.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final packageDir = Directory.current.path;
  final outDir =
      Platform.environment['OBSIDIAN_VAULT'] ??
      '${Platform.environment['HOME']}/.obsidian-dev';
  final release = Platform.environment['RELEASE'] == '1';
  final dev = !release;
  final useFvm = Platform.environment['USE_FVM'] != '0';

  // Parse extra --dart-define=KEY=VALUE from CLI args.
  final extraDefines = <String, String>{};
  for (final arg in args) {
    if (arg.startsWith('--dart-define=')) {
      final kv = arg.substring('--dart-define='.length);
      final sep = kv.indexOf('=');
      if (sep > 0) extraDefines[kv.substring(0, sep)] = kv.substring(sep + 1);
    }
  }

  await buildPlugin(
    packageDir: packageDir,
    pluginId: 'rhyolite-sync',
    entry: 'bin/plugin.dart',
    outDir: outDir,
    pluginClass: 'RhyolitePlugin',
    release: release,
    useFvm: useFvm,
    defines: {'rhyolite.dev': '$dev', ...extraDefines},
  );

  final manifestSrc = File(p.join(packageDir, 'manifest.json'));
  final manifestDst = File(p.join(outDir, 'rhyolite-sync', 'manifest.json'));
  await manifestSrc.copy(manifestDst.path);
  print('Copied manifest.json → ${manifestDst.path}');

  final wasmSrc = File(
    p.join(packageDir, 'sqlite3mc.wasm'),
  );
  final wasmDst = File(p.join(outDir, 'rhyolite-sync', 'sqlite3mc.wasm'));
  await wasmSrc.copy(wasmDst.path);
  print('Copied sqlite3mc.wasm → ${wasmDst.path}');

  print('Build complete → $outDir/rhyolite-sync/');
}
