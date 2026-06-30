import 'dart:io';

import 'package:path/path.dart';

import 'fs.dart';
import 'logs.dart';
import 'process.dart';
import 'yaml.dart';

/// Copies the shared workspace assets into the Flutter example so it can
/// reference them as bundled assets (see its `pubspec.yaml`).
///
/// Run as the `melos bootstrap` post hook, mirroring what `docs_bs` does for
/// the documentation site.
void main() {
  logger
    ..info('Bootstrapping flutter_example...')
    ..info('Copy assets');
  try {
    assetsDir().copySync(
      to: flutterExampleDir(subParts: ['assets']),
      logger: logger,
    );
  } catch (error) {
    logger.error(
      'Unable to copy assets',
      error: error,
    );
    badExit();
  }

  logger.info('generating flutter example code...');
  try {
    _generateFlutterExampleCode();
  } catch (error) {
    logger.error(
      'Unable to detect dependencies',
      error: error,
    );
    badExit();
  }

  logger.info('flutter_example ready ✅');
}

void _generateFlutterExampleCode() {
  final reader = YamlReader(crdtLfExamplePubspecLock())..initSync();
  final version = reader.version('crdt_lf');

  final generatedFile = File(
    joinAll(
      [crdtLfDir().path, 'flutter_example', 'lib', 'generated.dart'],
    ),
  );

  final generatedCode = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln()
    ..writeln("String libraryVersion = '$version';");

  generatedFile.writeAsStringSync(generatedCode.toString());
}
