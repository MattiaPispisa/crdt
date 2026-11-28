import 'dart:io' as io;

import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart' as yaml;

import 'fs.dart';
import 'logs.dart';
import 'process.dart';
import 'workspace.dart';

/// Propagates the cross-package "references" block (Apps + Packages lists)
/// into every published package README and every app README, then cuts a
/// documentation release for each published package (build-number `+1` bump
/// + a CHANGELOG stanza).
///
/// The published packages and the apps are read from the workspace: a
/// package is published when `melos publish` would publish it, an app is a
/// folder of `apps/` with a README, described by the text between its
/// `<!-- app-description -->` and `<!-- /app-description -->` markers.
///
/// Run from the repo root: `dart run scripts/update_references.dart`
/// (or `melos run update_references`).
Future<void> main() {
  return step(
    action: () {
      final repository = repositoryUrl();
      final published = _sorted(packages().where((p) => p.isPublished));
      final apps = _apps(repository);

      logger
          .info('Updating package READMEs and cutting documentation releases');
      for (final package in published) {
        _updateReadme(
          io.File(path.join(package.dir.path, 'README.md')),
          _buildBlock(apps, published, excludePackage: package.name),
        );
        _cutDocumentationRelease(package, repository);
      }

      logger.info('Updating app READMEs');
      for (final app in apps) {
        _updateReadme(
          app.readme,
          _buildBlock(apps, published, excludeApp: app.name),
        );
      }

      logger.info('Done ✅');
    },
    error: 'Unable to update the references',
  );
}

/// The packages listed first, in this order.
const _first = ['crdt_lf', 'crdt_socket_sync', 'crdt_lf_flutter'];

/// [packages] with [_first] on top, then the packages of `packages/core`,
/// then the others, each group by path.
List<Package> _sorted(Iterable<Package> packages) {
  final names = {for (final package in packages) package.name};
  final missing = _first.where((name) => !names.contains(name));
  if (missing.isNotEmpty) {
    throw ScriptException('Not a published package: ${missing.join(', ')}');
  }

  int rank(Package package) {
    final index = _first.indexOf(package.name);
    if (index != -1) return index;
    return _first.length +
        (package.repoPath.startsWith('packages/core/') ? 0 : 1);
  }

  return packages.toList()
    ..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.repoPath.compareTo(b.repoPath);
    });
}

/// An app entry rendered under the `## Apps` heading.
class _App {
  const _App({
    required this.name,
    required this.url,
    required this.description,
    required this.readme,
  });

  final String name;
  final String url;
  final String description;
  final io.File readme;
}

/// Every folder of `apps/` with a README, sorted by name.
List<_App> _apps(String repository) {
  final dirs = appsDir()
      .listSync()
      .whereType<io.Directory>()
      .where((dir) => !isSkipped(dir))
      .where((dir) => io.File(path.join(dir.path, 'README.md')).existsSync())
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  return [
    for (final dir in dirs) _app(dir, repository),
  ];
}

_App _app(io.Directory dir, String repository) {
  final name = path.basename(dir.path);
  final readme = io.File(path.join(dir.path, 'README.md'));
  final match = _description.firstMatch(readme.readAsStringSync());
  if (match == null) {
    throw ScriptException(
      'No <!-- app-description --> in ${relativeToRoot(readme.path)}',
    );
  }
  return _App(
    name: name,
    url: '$repository/tree/main/apps/$name',
    description: _oneLine(match[1]!, repository: repository, app: name),
    readme: readme,
  );
}

final _description = RegExp(
  r'<!--\s*app-description\s*-->(.*?)<!--\s*/app-description\s*-->',
  dotAll: true,
);
final _link = RegExp(r'\[([^\]]*)\]\(([^)\s]+)\)');

/// [markdown] on one line, with its relative links made absolute: the
/// description is copied into the READMEs of other folders.
String _oneLine(
  String markdown, {
  required String repository,
  required String app,
}) {
  final text = markdown
      .trim()
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join(' ');
  return text.replaceAllMapped(_link, (match) {
    final target = match[2]!;
    if (Uri.parse(target).hasScheme) return match[0]!;
    final url = target.startsWith('#')
        ? '$repository/tree/main/apps/$app$target'
        : '$repository/tree/main/'
            '${path.posix.normalize(path.posix.join('apps/$app', target))}';
    return '[${match[1]}]($url)';
  });
}

/// Renders the references block, optionally excluding the README's own
/// package ([excludePackage]) or app ([excludeApp]) so a README never links
/// to itself.
String _buildBlock(
  List<_App> apps,
  List<Package> published, {
  String? excludePackage,
  String? excludeApp,
}) {
  final buffer = StringBuffer();

  final listed = apps.where((a) => a.name != excludeApp).toList();
  if (listed.isNotEmpty) {
    buffer
      ..writeln('## Apps')
      ..writeln();
    for (final app in listed) {
      buffer.writeln('- [${app.name}](${app.url}) — ${app.description}');
    }
    buffer.writeln();
  }

  buffer
    ..writeln('## Packages')
    ..writeln()
    ..writeln('Other bricks of the crdt "system" are:')
    ..writeln();
  for (final package in published.where((p) => p.name != excludePackage)) {
    final name = package.name;
    buffer.writeln('- [$name](https://pub.dev/packages/$name)');
  }

  return buffer.toString().trimRight();
}

/// Replaces the references block in [readme] with [block].
///
/// The block spans the first `## Apps`/`## Packages` heading (matched
/// leniently) up to whichever comes first: the next `##` heading that is not
/// itself Apps/Packages (e.g. a `## Migrations` section some READMEs add
/// after the Packages list), the trailing `[label]:` link-definition footer,
/// or the end of file. When no block exists, [block] is appended at the end
/// of the file.
void _updateReadme(io.File readme, String block) {
  if (!readme.existsSync()) {
    throw ScriptException('README not found: ${relativeToRoot(readme.path)}');
  }

  final lines = readme.readAsStringSync().split('\n');
  final headingRe = RegExp(r'^\s*##\s+(Apps|Packages)\b');
  final otherHeadingRe = RegExp(r'^\s*##\s+');
  final linkDefRe = RegExp(r'^\[[^\]]+\]:');

  final start = lines.indexWhere(headingRe.hasMatch);

  if (start == -1) {
    // No existing block — append at end of file.
    final before = _dropTrailingBlanks(lines);
    readme.writeAsStringSync('${before.join('\n')}\n\n$block\n');
    logger.info('Appended references to ${relativeToRoot(readme.path)}');
    return;
  }

  var end = lines.length;
  for (var i = start + 1; i < lines.length; i++) {
    if (linkDefRe.hasMatch(lines[i]) ||
        (otherHeadingRe.hasMatch(lines[i]) && !headingRe.hasMatch(lines[i]))) {
      end = i;
      break;
    }
  }

  final before = _dropTrailingBlanks(lines.sublist(0, start));
  final buffer = StringBuffer()
    ..write(before.join('\n'))
    ..write('\n\n')
    ..write(block);

  if (end < lines.length) {
    buffer
      ..write('\n\n')
      ..write(lines.sublist(end).join('\n'));
  } else {
    buffer.write('\n');
  }

  readme.writeAsStringSync(buffer.toString());
  logger.info('Rewrote references in ${relativeToRoot(readme.path)}');
}

/// Bumps the pubspec build number and prepends a documentation-release
/// CHANGELOG stanza.
void _cutDocumentationRelease(Package package, String repository) {
  final current = package.pubspec.version;
  if (current == null) {
    throw ScriptException(
      'No version in ${relativeToRoot(package.pubspecFile.path)}',
    );
  }
  final next = _bumpBuild(current);

  final pubspec = package.pubspecFile;
  final text = pubspec.readAsStringSync();
  final span = (yaml.loadYaml(text) as yaml.YamlMap).nodes['version']!.span;
  pubspec.writeAsStringSync(
    text.replaceRange(span.start.offset, span.end.offset, '$next'),
  );

  final changelog = io.File(path.join(package.dir.path, 'CHANGELOG.md'));
  final stanza = '## [$next]($repository/tree/'
      '${package.name}-v$next/${package.repoPath})\n'
      '\n'
      '**Date:** ${DateTime.now().toIso8601String().substring(0, 10)}\n'
      '\n'
      '- Documentation release: refreshes the CHANGELOG and docs published on '
      'pub.dev. No functional changes since `${_withoutBuild(current)}`.\n'
      '\n';
  changelog.writeAsStringSync(
    stanza + (changelog.existsSync() ? changelog.readAsStringSync() : ''),
  );

  logger.info('${package.name}: $current → $next');
}

/// Returns [version] with its `+N` build metadata incremented (added as `+1`
/// when absent), preserving major/minor/patch and any pre-release.
Version _bumpBuild(Version version) {
  final build = version.build;
  final current = build.isNotEmpty && build.last is int ? build.last as int : 0;
  return Version(
    version.major,
    version.minor,
    version.patch,
    pre: version.preRelease.isEmpty ? null : version.preRelease.join('.'),
    build: '${current + 1}',
  );
}

/// [version] stripped of its build metadata (e.g. `1.1.0+1` → `1.1.0`).
Version _withoutBuild(Version version) => Version(
      version.major,
      version.minor,
      version.patch,
      pre: version.preRelease.isEmpty ? null : version.preRelease.join('.'),
    );

List<String> _dropTrailingBlanks(List<String> lines) {
  final result = List<String>.of(lines);
  while (result.isNotEmpty && result.last.trim().isEmpty) {
    result.removeLast();
  }
  return result;
}
