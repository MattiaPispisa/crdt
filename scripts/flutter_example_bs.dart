import 'dart:io';

import 'fs.dart';
import 'logs.dart';
import 'process.dart';
import 'yaml.dart';

/// Bootstraps the Flutter example apps: copies the shared workspace assets
/// into the crdt_lf example and generates the `generated.dart` version files
/// the examples display.
///
/// Run as the `melos bootstrap` post hook, mirroring what `docs_bs` does for
/// the documentation site.
void main() {
  // crdt_lf flutter_example bundles the shared workspace assets (logo, ...).
  logger
    ..info('Bootstrapping examples...')
    ..info('Copy assets');
  try {
    assetsDir().copySync(
      to: crdtLfFlutterExampleDir(subParts: ['assets']),
      logger: logger,
    );
    assetsDir().copySync(
      to: greyhoundMarkdownDir(subParts: ['assets']),
      logger: logger,
    );
  } catch (error) {
    logger.error(
      'Unable to copy assets',
      error: error,
    );
    badExit();
  }

  logger.info('Generating example version files...');
  try {
    // crdt_lf example shows the crdt_lf version.
    _generateVersions(
      pubspecLock: crdtLfExamplePubspecLock(),
      output: File(
        crdtLfFlutterExampleDir(subParts: ['lib', 'generated.dart']).path,
      ),
      packages: const {'crdt_lf', 'crdt_lf_flutter'},
    );
    // crdt_socket_sync client_example shows both the socket and crdt_lf
    // versions.
    _generateVersions(
      pubspecLock: clientExamplePubspecLock(),
      output: File(
        clientExampleDir(subParts: ['lib', 'generated.dart']).path,
      ),
      packages: const {'crdt_socket_sync', 'crdt_lf', 'crdt_lf_flutter'},
    );
  } catch (error) {
    logger.error(
      'Unable to generate version files',
      error: error,
    );
    badExit();
  }

  logger.info('examples ready ✅');
}

/// Writes a `generated.dart` at [output] exposing each package version as a
/// top-level `<package>_version` string, read from [pubspecLock].
///
/// [packages] is the set of package names to emit
/// (e.g. `{'crdt_socket_sync', 'crdt_lf'}`).
void _generateVersions({
  required File pubspecLock,
  required File output,
  required Set<String> packages,
}) {
  final reader = YamlReader(pubspecLock)..initSync();

  final code = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln(
      '// ignore_for_file: constant_identifier_names, '
      'non_constant_identifier_names',
    )
    ..writeln();
  for (final package in packages) {
    code.writeln("String ${package}_version = '${reader.version(package)}';");
  }

  output.writeAsStringSync(code.toString());
}
