import 'dart:io' as io;

import 'package:path/path.dart' as path;

import 'fs.dart';
import 'logs.dart';
import 'process.dart';

const _extension = ['core', 'crdt_lf_devtools_extension'];

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
void main() async {
  final source = packagesDir(subParts: _extension);
  final destination = crdtLfDir(subParts: ['extension', 'devtools', 'build']);

  logger.info('Building the DevTools extension...');
  final build = await runStreamed(
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
  );
  if (build.exitCode != 0) {
    logger.error('DevTools extension build failed (${build.exitCode})');
    badExit();
  }

  if (destination.existsSync()) {
    destination.deleteSync(recursive: true);
  }
  packagesDir(subParts: [..._extension, 'build', 'web'])
      .copySync(to: destination);
  _prune(destination);
  logger.info('Copied the build to ${destination.path}');

  final validate = await runStreamed(
    'dart',
    ['run', 'devtools_extensions', 'validate', '--package=../crdt_lf'],
    workingDir: source,
  );
  if (validate.exitCode != 0) {
    logger.error('DevTools extension is not valid (${validate.exitCode})');
    badExit();
  }

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
