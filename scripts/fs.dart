import 'dart:io' as io;
import 'package:en_logger/en_logger.dart';
import 'package:path/path.dart' as path;

io.Directory assetsDir({List<String> subParts = const []}) {
  return [io.Directory.current.path, 'assets', ...subParts].toDir();
}

io.Directory docsDir({List<String> subParts = const []}) {
  return [io.Directory.current.path, 'docs', ...subParts].toDir();
}

io.Directory greyhoundMarkdownDir({List<String> subParts = const []}) {
  return [
    io.Directory.current.path,
    'apps',
    'greyhound_markdown',
    'client',
    ...subParts,
  ].toDir();
}

/// The shared Greyhound Markdown artwork, source of the app's web icons.
io.File greyhoundLogo() {
  return io.File(
    path.join(
      assetsDir(subParts: ['images']).path,
      'greyhound_markdown_logo.png',
    ),
  );
}

io.Directory crdtLfFlutterExampleDir({List<String> subParts = const []}) {
  return crdtLfDir(subParts: ['flutter_example', ...subParts]);
}

io.Directory clientExampleDir({List<String> subParts = const []}) {
  return crdtLfSocketSyncDir(subParts: ['client_example', ...subParts]);
}

io.File crdtLfExamplePubspecLock() {
  return pubspecLockOf(crdtLfFlutterExampleDir());
}

io.File clientExamplePubspecLock() {
  return pubspecLockOf(clientExampleDir());
}

/// The `pubspec.lock` file inside [dir].
io.File pubspecLockOf(io.Directory dir) {
  return io.File(path.join(dir.path, 'pubspec.lock'));
}

io.Directory crdtLfDir({List<String> subParts = const []}) {
  return packagesDir(subParts: ['crdt_lf', ...subParts]);
}

io.Directory crdtLfSocketSyncDir({List<String> subParts = const []}) {
  return packagesDir(subParts: ['crdt_socket_sync', ...subParts]);
}

io.Directory packagesDir({List<String> subParts = const []}) {
  return [io.Directory.current.path, 'packages', ...subParts].toDir();
}

io.Directory appsDir({List<String> subParts = const []}) {
  return [io.Directory.current.path, 'apps', ...subParts].toDir();
}

/// Copies each `packages/<name>/README.md` into [to] as `<name>.md`.
///
/// Used to surface every package's entry-point README inside the docs site.
void copyPackageReadmes({
  required io.Directory to,
  EnLogger? logger,
}) {
  if (!to.existsSync()) {
    to.createSync(recursive: true);
  }

  final packages = packagesDir().listSync().whereType<io.Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final package in packages) {
    final readme = io.File(path.join(package.path, 'README.md'));
    if (!readme.existsSync()) {
      continue;
    }
    final name = path.basename(package.path);
    final content = _parseReadme(readme.readAsStringSync());
    io.File(path.join(to.path, '$name.md')).writeAsStringSync(content);
    logger?.info('Copied $name/README.md');
  }
}

/// Copies the root `CONTRIBUTING.md` into [to] as `contributing.md`.
///
/// The guide is written for GitHub, so the copy is adapted to Docusaurus:
/// the front matter is prepended, the inline table of contents is dropped
/// (the site renders its own) and the repository-relative links are made
/// absolute.
void copyContributing({
  required io.Directory to,
  EnLogger? logger,
}) {
  if (!to.existsSync()) {
    to.createSync(recursive: true);
  }

  final source = io.File(
    path.join(io.Directory.current.path, 'CONTRIBUTING.md'),
  );

  const frontMatter = '---\n'
      'sidebar_position: 99\n'
      'title: Contributing\n'
      '---\n'
      '\n';

  final content = _absoluteRepositoryLinks(
    _parseReadme(source.readAsStringSync()),
  );
  io.File(path.join(to.path, 'contributing.md'))
      .writeAsStringSync('$frontMatter$content');
  logger?.info('Copied CONTRIBUTING.md');
}

/// Rewrites the repository-relative links (`./README.md`, `./melos.yaml`, ...)
/// as absolute GitHub URLs, so they still resolve outside the repository.
///
/// Handles both the inline (`](./file)`) and the reference (`]: ./file`) link
/// syntax.
String _absoluteRepositoryLinks(String content) {
  const blob = 'https://github.com/MattiaPispisa/crdt/blob/main/';
  return content.replaceAll('](./', ']($blob').replaceAll(']: ./', ']: $blob');
}

/// Prepares a README for Docusaurus.
///
/// Removes the leading auto-generated table of contents — the first contiguous
/// block of list items linking to in-page anchors (e.g. `- [Title](#title)`).
/// Those links target the page H1, which Docusaurus renders as the doc title
/// without that anchor, producing broken-anchor warnings; Docusaurus also shows
/// its own TOC, so the inline one is redundant.
String _parseReadme(String content) {
  final lines = content.split('\n');
  final tocItem = RegExp(r'^\s*[-*] \[.+\]\(#.+\)\s*$');

  var start = -1;
  var end = -1;
  for (var i = 0; i < lines.length; i++) {
    if (tocItem.hasMatch(lines[i])) {
      if (start == -1) {
        start = i;
      }
      end = i;
    } else if (start != -1) {
      break;
    }
  }

  if (start == -1) {
    return content;
  }

  // Also drop a blank line right before and after the block, if any.
  var from = start;
  var to = end + 1;
  if (from > 0 && lines[from - 1].trim().isEmpty) {
    from -= 1;
  }
  if (to < lines.length && lines[to].trim().isEmpty) {
    to += 1;
  }
  lines.removeRange(from, to);
  return lines.join('\n');
}

extension _IterableHelper on Iterable<String> {
  io.Directory toDir() => io.Directory(path.joinAll(this));
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
