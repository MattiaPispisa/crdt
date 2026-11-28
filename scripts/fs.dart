import 'dart:io' as io;

import 'package:en_logger/en_logger.dart';
import 'package:path/path.dart' as path;

/// Folders that a walk of the repository never enters, besides the hidden
/// ones.
const _skipped = {'build', 'node_modules'};

/// The repository root: every script runs from there.
String get rootPath => io.Directory.current.path;

/// [file] relative to [rootPath].
String relativeToRoot(String file) => path.relative(file, from: rootPath);

io.Directory rootDir([List<String> parts = const []]) {
  return io.Directory(path.joinAll([rootPath, ...parts]));
}

io.Directory assetsDir([List<String> parts = const []]) {
  return rootDir(['assets', ...parts]);
}

io.Directory docsDir([List<String> parts = const []]) {
  return rootDir(['docs', ...parts]);
}

io.Directory packagesDir([List<String> parts = const []]) {
  return rootDir(['packages', ...parts]);
}

io.Directory appsDir([List<String> parts = const []]) {
  return rootDir(['apps', ...parts]);
}

io.Directory crdtLfDir([List<String> parts = const []]) {
  return packagesDir(['core', 'crdt_lf', ...parts]);
}

/// Every file under [dir] that [test] accepts, outside the hidden and the
/// [_skipped] folders.
Iterable<io.File> files(io.Directory dir, bool Function(io.File) test) sync* {
  for (final entity in dir.listSync(followLinks: false)) {
    if (entity is io.Directory) {
      if (!isSkipped(entity)) {
        yield* files(entity, test);
      }
    } else if (entity is io.File && test(entity)) {
      yield entity;
    }
  }
}

/// Whether a walk of the repository leaves [dir] out.
bool isSkipped(io.Directory dir) {
  final name = path.basename(dir.path);
  return name.startsWith('.') || _skipped.contains(name);
}

extension DirectoryHelper on io.Directory {
  void copySync({
    required io.Directory to,
    EnLogger? logger,
  }) {
    if (!to.existsSync()) {
      to.createSync(recursive: true);
    }

    for (final entity in listSync(recursive: true, followLinks: false)) {
      final relativePath = path.relative(entity.path, from: this.path);
      final toPath = path.joinAll([to.path, relativePath]);

      if (entity is io.Directory) {
        io.Directory(toPath).createSync(recursive: true);
        logger?.info('Created ${to.path}');
      } else if (entity is io.File) {
        final parentDir = io.Directory(path.dirname(toPath));
        if (!parentDir.existsSync()) {
          parentDir.createSync();
        }
        entity.copySync(toPath);
        logger?.info(
          'Copied ${path.basename(entity.path)}'
          ' to ${path.dirname(to.path)}',
        );
      }
    }
  }
}
