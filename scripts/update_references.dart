import 'dart:io' as io;

import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';

import 'fs.dart';
import 'logs.dart';
import 'process.dart';
import 'yaml.dart';

/// Propagates the cross-package "references" block (Apps + Packages lists)
/// into every published package README and the greyhound app README, then
/// cuts a documentation release for each published package (build-number
/// `+1` bump + a CHANGELOG stanza).
///
/// Run from the repo root: `dart run scripts/update_references.dart`
/// (or `melos run update_references`).
void main() {
  logger.info('Building pub-name → directory map');
  final pubNameToDir = _pubNameToDir();

  logger.info('Updating package READMEs and cutting documentation releases');
  for (final pubName in _packagePubNames) {
    final dir = pubNameToDir[pubName];
    if (dir == null) {
      logger.error('No package directory found for "$pubName"');
      badExit();
    }
    final packageDir = packagesDir(subParts: [dir]);

    _updateReadme(
      io.File(path.join(packageDir.path, 'README.md')),
      _buildBlock(excludePubName: pubName),
    );

    _cutDocumentationRelease(
      pubName: pubName,
      dir: dir,
      pubspec: io.File(path.join(packageDir.path, 'pubspec.yaml')),
      changelog: io.File(path.join(packageDir.path, 'CHANGELOG.md')),
    );
  }

  logger.info('Updating greyhound_markdown app README');
  final appDir = appsDir(subParts: ['greyhound_markdown']);
  _updateReadme(
    io.File(path.join(appDir.path, 'README.md')),
    // The app is itself the only Apps entry, so exclude it; the section is
    // then empty and dropped, leaving just the Packages list.
    _buildBlock(excludeAppName: 'greyhound_markdown'),
  );

  logger.info('Done ✅');
}

/// An app entry rendered under the `## Apps` heading.
class _AppRef {
  const _AppRef({
    required this.name,
    required this.url,
    required this.description,
  });

  final String name;
  final String url;
  final String description;
}

/// Canonical Apps references, mirrored from the `app_packages_references`
/// snippet in `.vscode/github.code-snippets`.
const _apps = <_AppRef>[
  _AppRef(
    name: 'greyhound_markdown',
    url: 'https://github.com/MattiaPispisa/crdt/tree/main/apps/'
        'greyhound_markdown',
    description: 'Real-time collaborative markdown editor built on crdt_lf',
  ),
];

/// Canonical Packages references (pub.dev names), in snippet order. These are
/// exactly the packages published to pub.dev.
const _packagePubNames = <String>[
  'crdt_lf',
  'crdt_socket_sync',
  'crdt_lf_flutter',
  'hlc_dart',
  'crdt_lf_hive',
  'crdt_lf_drift',
  'crdt_lf_sqlite',
];

/// Maps every package's pub.dev name to its directory under `packages/`.
Map<String, String> _pubNameToDir() {
  final map = <String, String>{};

  for (final dir in packagesDir().listSync().whereType<io.Directory>()) {
    final pubspec = io.File(path.join(dir.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      continue;
    }
    final name = YamlReader(pubspec).stringOrNull('name');
    if (name != null) {
      map[name] = path.basename(dir.path);
    }
  }
  return map;
}

/// Renders the references block, optionally excluding the README's own
/// package ([excludePubName]) or app ([excludeAppName]) so a README never
/// links to itself.
String _buildBlock({String? excludePubName, String? excludeAppName}) {
  final buffer = StringBuffer();

  final apps = _apps.where((a) => a.name != excludeAppName).toList();
  if (apps.isNotEmpty) {
    buffer
      ..writeln('## Apps')
      ..writeln();
    for (final app in apps) {
      buffer.writeln('- [${app.name}](${app.url}) — ${app.description}');
    }
    buffer.writeln();
  }

  buffer
    ..writeln('## Packages')
    ..writeln()
    ..writeln('Other bricks of the crdt "system" are:')
    ..writeln();
  for (final pubName in _packagePubNames.where((p) => p != excludePubName)) {
    buffer.writeln('- [$pubName](https://pub.dev/packages/$pubName)');
  }

  return buffer.toString().trimRight();
}

/// Replaces the references block in [readme] with [block].
///
/// The block spans the first `## Apps`/`## Packages` heading (matched
/// leniently) up to the trailing `[label]:` link-definition footer, or to the
/// end of file when there is no footer. When no block exists, [block] is
/// appended at the end of the file.
void _updateReadme(io.File readme, String block) {
  if (!readme.existsSync()) {
    logger.error('README not found: ${_relative(readme)}');
    badExit();
  }

  final lines = readme.readAsStringSync().split('\n');
  final headingRe = RegExp(r'^\s*##\s+(Apps|Packages)\b');
  final linkDefRe = RegExp(r'^\[[^\]]+\]:');

  final start = lines.indexWhere(headingRe.hasMatch);

  if (start == -1) {
    // No existing block — append at end of file.
    final before = _dropTrailingBlanks(lines);
    readme.writeAsStringSync('${before.join('\n')}\n\n$block\n');
    logger.info('Appended references to ${_relative(readme)}');
    return;
  }

  var footer = -1;
  for (var i = start; i < lines.length; i++) {
    if (linkDefRe.hasMatch(lines[i])) {
      footer = i;
      break;
    }
  }

  final before = _dropTrailingBlanks(lines.sublist(0, start));
  final buffer = StringBuffer()
    ..write(before.join('\n'))
    ..write('\n\n')
    ..write(block);

  if (footer != -1) {
    buffer
      ..write('\n\n')
      ..write(lines.sublist(footer).join('\n'));
  } else {
    buffer.write('\n');
  }

  readme.writeAsStringSync(buffer.toString());
  logger.info('Rewrote references in ${_relative(readme)}');
}

/// Bumps the pubspec build number and prepends a documentation-release
/// CHANGELOG stanza.
void _cutDocumentationRelease({
  required String pubName,
  required String dir,
  required io.File pubspec,
  required io.File changelog,
}) {
  final rawVersion = YamlReader(pubspec).stringOrNull('version');
  if (rawVersion == null) {
    logger.error('No version in ${_relative(pubspec)}');
    badExit();
  }

  final current = Version.parse(rawVersion);
  final next = _bumpBuild(current);

  pubspec.writeAsStringSync(
    pubspec.readAsStringSync().replaceFirst(
          'version: $current',
          'version: $next',
        ),
  );

  final stanza = '## [$next](https://github.com/MattiaPispisa/crdt/tree/'
      '$pubName-v$next/packages/$dir)\n'
      '\n'
      '**Date:** ${_today()}\n'
      '\n'
      'Documentation release: refreshes the CHANGELOG and docs published on '
      'pub.dev. No functional changes since `${_withoutBuild(current)}`.\n'
      '\n';
  changelog.writeAsStringSync(
    stanza + (changelog.existsSync() ? changelog.readAsStringSync() : ''),
  );

  logger.info('$pubName: $current → $next');
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

/// Today's date as `YYYY-MM-DD`.
String _today() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

List<String> _dropTrailingBlanks(List<String> lines) {
  final result = List<String>.of(lines);
  while (result.isNotEmpty && result.last.trim().isEmpty) {
    result.removeLast();
  }
  return result;
}

String _relative(io.File file) =>
    path.relative(file.path, from: io.Directory.current.path);
