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
  return packagesDir(subParts: ['core', 'crdt_lf', ...subParts]);
}

io.Directory crdtLfSocketSyncDir({List<String> subParts = const []}) {
  return packagesDir(subParts: ['core', 'crdt_socket_sync', ...subParts]);
}

io.Directory packagesDir({List<String> subParts = const []}) {
  return [io.Directory.current.path, 'packages', ...subParts].toDir();
}

io.Directory appsDir({List<String> subParts = const []}) {
  return [io.Directory.current.path, 'apps', ...subParts].toDir();
}

/// Every package root under `packages/`, at any nesting depth.
///
/// A package root is a directory containing a `pubspec.yaml`. The walk does
/// not descend into a matched package's subdirectories, so `example/`,
/// `flutter_example/`, `client_example/` (which have their own
/// `pubspec.yaml`) are never returned.
List<io.Directory> packageDirs() {
  final result = <io.Directory>[];

  void walk(io.Directory dir) {
    if (io.File(path.join(dir.path, 'pubspec.yaml')).existsSync()) {
      result.add(dir);
      return;
    }
    for (final entity in dir.listSync().whereType<io.Directory>()) {
      walk(entity);
    }
  }

  for (final entity in packagesDir().listSync().whereType<io.Directory>()) {
    walk(entity);
  }

  return result..sort((a, b) => a.path.compareTo(b.path));
}

/// The folder under `packages/` holding the packages that support the
/// repository itself: benchmark harnesses, shared test suites, shared example
/// code. They are never published and never documented.
const internalPackagesFolder = '_internal';

/// Whether [package] lives under `packages/_internal/`.
///
/// Pass this to [copyPackageReadmes] as `exclude` to keep the internal
/// packages out of the docs site.
bool isInternalPackage(io.Directory package) {
  final relative = path.relative(package.path, from: packagesDir().path);
  return path.split(relative).first == internalPackagesFolder;
}

/// Copies each `packages/<name>/README.md` into [to] as `<name>.md`.
///
/// Used to surface every package's entry-point README inside the docs site.
/// A package for which [exclude] answers true is skipped.
void copyPackageReadmes({
  required io.Directory to,
  bool Function(io.Directory package)? exclude,
  EnLogger? logger,
}) {
  if (!to.existsSync()) {
    to.createSync(recursive: true);
  }

  for (final package in packageDirs()) {
    if (exclude?.call(package) ?? false) {
      logger?.info('Skipped ${path.basename(package.path)}');
      continue;
    }
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
/// Drops what only makes sense outside the docs site: the inline table of
/// contents (see [_dropInlineToc]) and the callouts pointing back at the docs
/// (see [_dropDocsSiteCallouts]).
String _parseReadme(String content) {
  return _dropDocsSiteCallouts(_dropInlineToc(content));
}

/// The docs site's own pages.
const _docsSiteUrl = 'https://mattiapispisa.it/crdt/docs/';

/// Drops the blockquote callouts that send the reader to the docs site.
///
/// A README is also read on GitHub and on pub.dev, where mermaid has no
/// renderer, so it carries notes like "Diagrams render best in the live
/// documentation". On the docs site the reader is already there, so the note
/// is noise.
///
/// Removes every contiguous `>` block holding a link to [_docsSiteUrl], and
/// the blank line the block leaves behind.
String _dropDocsSiteCallouts(String content) {
  final lines = content.split('\n');
  final result = <String>[];
  bool isQuote(String line) => line.trimLeft().startsWith('>');

  var i = 0;
  while (i < lines.length) {
    if (!isQuote(lines[i])) {
      result.add(lines[i]);
      i += 1;
      continue;
    }

    var end = i;
    while (end < lines.length && isQuote(lines[end])) {
      end += 1;
    }

    final block = lines.sublist(i, end);
    if (block.any((line) => line.contains(_docsSiteUrl))) {
      // Keep one blank line where the block was, not two.
      if (end < lines.length && lines[end].trim().isEmpty) {
        end += 1;
      } else if (result.isNotEmpty && result.last.trim().isEmpty) {
        result.removeLast();
      }
    } else {
      result.addAll(block);
    }
    i = end;
  }

  return result.join('\n');
}

/// Removes the leading auto-generated table of contents — the first contiguous
/// block of list items linking to in-page anchors (e.g. `- [Title](#title)`).
///
/// Those links target the page H1, which Docusaurus renders as the doc title
/// without that anchor, producing broken-anchor warnings; Docusaurus also shows
/// its own TOC, so the inline one is redundant.
String _dropInlineToc(String content) {
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
