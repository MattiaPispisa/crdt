import 'dart:io' as io;
import 'package:en_logger/en_logger.dart';
import 'package:path/path.dart' as path;

io.Directory assetsDir({List<String> subParts = const []}) {
  return io.Directory(
    path.joinAll(
      [io.Directory.current.path, 'assets', ...subParts],
    ),
  );
}

io.Directory docsDir({List<String> subParts = const []}) {
  return io.Directory(
    path.joinAll(
      [io.Directory.current.path, 'docs', ...subParts],
    ),
  );
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
