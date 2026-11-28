import 'dart:io' as io;

import 'package:path/path.dart' as path;

import 'fs.dart';
import 'logs.dart';
import 'process.dart';
import 'workspace.dart';

Future<void> main(List<String> args) async {
  final ci = args.contains('--ci');

  logger
    ..info('Bootstrapping Docs${ci ? ' (CI)' : ''}...')
    ..info('Copy assets');
  await step(
    action: () => assetsDir().copySync(to: docsDir(['static']), logger: logger),
    error: 'Unable to copy assets',
  );

  logger.info('Copy contributing guide');
  await step(
    action: () => _copyContributing(to: docsDir(['docs'])),
    error: 'Unable to copy the contributing guide',
  );

  logger.info('Copy benchmark results');
  await step(
    action: () =>
        _copyBenchmarkResults(to: docsDir(['docs', 'benchmarks', '_results'])),
    error: 'Unable to copy the benchmark results',
  );

  logger.info('Install Docs');
  await step(
    action: () => run('npm', [if (ci) 'ci' else 'i'], workingDir: docsDir()),
    error: 'Unable to install docs',
  );

  logger.info('Bootstrapped Done ✅');
}

/// Copies the root `CONTRIBUTING.md` into [to] as `contributing.md`.
///
/// The guide is written for GitHub, so the copy is adapted to Docusaurus:
/// the front matter is prepended, the inline table of contents is dropped
/// (the site renders its own) and the repository-relative links are made
/// absolute.
void _copyContributing({required io.Directory to}) {
  if (!to.existsSync()) {
    to.createSync(recursive: true);
  }

  final source = io.File(path.join(rootPath, 'CONTRIBUTING.md'));

  const frontMatter = '---\n'
      'sidebar_position: 99\n'
      'title: Contributing\n'
      '---\n'
      '\n';

  final content = _absoluteRepositoryLinks(
    _dropInlineToc(source.readAsStringSync()),
  );
  io.File(path.join(to.path, 'contributing.md'))
      .writeAsStringSync('$frontMatter$content');
  logger.info('Copied CONTRIBUTING.md');
}

/// Copies the `benchmarks/results.md` of every package into [to], as
/// `<package folder>.md`.
///
/// The benchmark pages of the site import these files, so they show the
/// results committed in the repository.
void _copyBenchmarkResults({required io.Directory to}) {
  if (to.existsSync()) {
    to.deleteSync(recursive: true);
  }
  to.createSync(recursive: true);

  for (final package in packages()) {
    final results = io.File(
      path.join(package.dir.path, 'benchmarks', 'results.md'),
    );
    if (!results.existsSync()) {
      continue;
    }
    final name = path.basename(package.dir.path);
    results.copySync(path.join(to.path, '$name.md'));
    logger.info('Copied the benchmark results of $name');
  }
}

/// Rewrites the repository-relative links (`./README.md`, `./melos.yaml`, ...)
/// as absolute GitHub URLs, so they still resolve outside the repository.
///
/// Handles both the inline (`](./file)`) and the reference (`]: ./file`) link
/// syntax.
String _absoluteRepositoryLinks(String content) {
  final blob = '${repositoryUrl()}/blob/main/';
  return content.replaceAll('](./', ']($blob').replaceAll(']: ./', ']: $blob');
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
