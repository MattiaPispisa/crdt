import 'dart:io' as io;

import 'package:path/path.dart' as path;

import 'fs.dart';
import 'logs.dart';
import 'process.dart';

/// Renderer files of `canvaskit/` that no build of the extension loads.
///
/// The WebAssembly build loads `skwasm`, the JavaScript fallback loads
/// `canvaskit` (plain, or `chromium/` on a Chromium browser).
const _unusedRenderers = [
  'skwasm_heavy.js',
  'skwasm_heavy.wasm',
  'wimp.js',
  'wimp.wasm',
  'webparagraph',
];

/// Builds the DevTools extension to WebAssembly, with the JavaScript build as
/// fallback, and copies it into `crdt_lf/extension/devtools/build`.
///
/// The renderer is served from the build, so the extension opens offline.
Future<void> main() async {
  final source = packagesDir(['core', 'crdt_lf_devtools_extension']);
  final destination = crdtLfDir(['extension', 'devtools', 'build']);

  logger.info('Building the DevTools extension...');
  await step(
    action: () => run(
      'flutter',
      [
        'build',
        'web',
        '--wasm',
        '--release',
        '--no-tree-shake-icons',
        '--no-web-resources-cdn',
      ],
      workingDir: source,
    ),
    error: 'DevTools extension build failed',
  );

  await step(
    action: () {
      if (destination.existsSync()) {
        destination.deleteSync(recursive: true);
      }
      io.Directory(path.join(source.path, 'build', 'web'))
          .copySync(to: destination);
      _prune(destination);
    },
    error: 'Unable to copy the DevTools extension build',
  );
  logger.info('Copied the build to ${destination.path}');

  await step(
    action: () => run(
      'dart',
      [
        'run',
        'devtools_extensions',
        'validate',
        '--package=${path.relative(crdtLfDir().path, from: source.path)}',
      ],
      workingDir: source,
    ),
    error: 'DevTools extension is not valid',
  );

  logger.info('DevTools extension build done ✅');
}

/// Deletes what the extension never loads: the build ships inside `crdt_lf`.
void _prune(io.Directory build) {
  final canvaskit = path.join(build.path, 'canvaskit');
  for (final name in _unusedRenderers) {
    final target = path.join(canvaskit, name);
    if (io.FileSystemEntity.isDirectorySync(target)) {
      io.Directory(target).deleteSync(recursive: true);
    } else if (io.File(target).existsSync()) {
      io.File(target).deleteSync();
    }
  }

  for (final entity in build.listSync(recursive: true)) {
    if (entity is io.File && entity.path.endsWith('.symbols')) {
      entity.deleteSync();
    }
  }
}
