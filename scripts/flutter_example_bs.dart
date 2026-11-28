import 'dart:io' as io;

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart' as yaml;

import 'fs.dart';
import 'logs.dart';
import 'process.dart';
import 'web_icons.dart';

/// Bootstraps the Flutter example apps: copies the shared workspace assets
/// into the crdt_lf example and generates the `generated.dart` version files
/// the examples display.
///
/// Run as the `melos bootstrap` post hook, mirroring what `docs_bs` does for
/// the documentation site.
Future<void> main() async {
  final crdtLfExample = crdtLfDir(['flutter_example']);
  final clientExample =
      packagesDir(['core', 'crdt_socket_sync', 'client_example']);
  final greyhoundClient = appsDir(['greyhound_markdown', 'client']);

  // crdt_lf flutter_example bundles the shared workspace assets (logo, ...).
  logger
    ..info('Bootstrapping examples...')
    ..info('Copy assets');
  await step(
    action: () {
      for (final app in [crdtLfExample, greyhoundClient]) {
        assetsDir().copySync(
          to: io.Directory(path.join(app.path, 'assets')),
          logger: logger,
        );
      }
    },
    error: 'Unable to copy assets',
  );

  // The web build serves its icons from `web/`, outside the Flutter asset
  // bundle, so they are rendered from the shared logo instead of copied.
  logger.info('Generating greyhound_markdown web icons...');
  await step(
    action: () => generateWebIcons(
      source: io.File(
        path.join(assetsDir(['images']).path, 'greyhound_markdown_logo.png'),
      ),
      webDir: io.Directory(path.join(greyhoundClient.path, 'web')),
      // The plate under the maskable icons — the only ones that cannot be
      // transparent. ColorScheme.fromSeed(seedColor: Colors.teal).surface, so
      // the launcher shows the app's own light surface.
      background: 0xF4FBF8,
      logger: logger,
    ),
    error: 'Unable to generate web icons',
  );

  logger.info('Generating example version files...');
  await step(
    action: () {
      _generateVersions(
        app: crdtLfExample,
        packages: const {'crdt_lf', 'crdt_lf_flutter'},
      );
      _generateVersions(
        app: clientExample,
        packages: const {'crdt_socket_sync', 'crdt_lf', 'crdt_lf_flutter'},
      );
    },
    error: 'Unable to generate version files',
  );

  logger.info('examples ready ✅');
}

/// Writes the `lib/generated.dart` of [app], exposing the version of each of
/// [packages] as a top-level `<package>_version` string, read from the
/// `pubspec.lock` of [app].
void _generateVersions({
  required io.Directory app,
  required Set<String> packages,
}) {
  final lock = io.File(path.join(app.path, 'pubspec.lock'));
  final locked = (yaml.loadYaml(lock.readAsStringSync())
      as yaml.YamlMap)['packages'] as yaml.YamlMap;

  final code = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln(
      '// ignore_for_file: constant_identifier_names, '
      'non_constant_identifier_names',
    )
    ..writeln();
  for (final package in packages) {
    final version = (locked[package] as yaml.YamlMap)['version'] as String;
    code.writeln("String ${package}_version = '$version';");
  }

  io.File(path.join(app.path, 'lib', 'generated.dart'))
      .writeAsStringSync(code.toString());
}
