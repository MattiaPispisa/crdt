// Turns every brick in `bricks/` into a Dart file in `lib/src/bundles/`.
//
// Run it from the package root after changing a brick:
//
//   dart run tool/generate_bundles.dart
//
// It does what `mason bundle --type dart` does, through `package:mason`, so
// the mason CLI does not need to be installed.
import 'dart:convert';
import 'dart:io';

import 'package:mason/mason.dart';
import 'package:path/path.dart' as p;

void main() {
  final bricks = Directory('bricks')
      .listSync()
      .whereType<Directory>()
      .where((dir) => File(p.join(dir.path, 'brick.yaml')).existsSync())
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final output = Directory(p.join('lib', 'src', 'bundles'));
  if (output.existsSync()) {
    output.deleteSync(recursive: true);
  }
  output.createSync(recursive: true);

  final names = <String>[];
  for (final brick in bricks) {
    final bundle = createBundle(brick);
    names.add(bundle.name);
    // `$` would start an interpolation inside the Dart string literals.
    final json = const JsonEncoder.withIndent('  ')
        .convert(bundle.toJson())
        .replaceAll(r'$', r'\$');
    File(p.join(output.path, '${bundle.name}_bundle.dart')).writeAsStringSync(
      '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
      '// Run `dart run tool/generate_bundles.dart` instead.\n'
      '// ignore_for_file: type=lint\n'
      '\n'
      "import 'package:mason/mason.dart';\n"
      '\n'
      'final ${bundle.name.camelCase}Bundle = '
      'MasonBundle.fromJson(<String, dynamic>$json);\n',
    );
    stdout.writeln('bundled ${bundle.name}');
  }

  File(p.join(output.path, 'bundles.dart')).writeAsStringSync(
    '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
    '// Run `dart run tool/generate_bundles.dart` instead.\n'
    '// ignore_for_file: type=lint\n'
    '\n'
    "import 'package:mason/mason.dart';\n"
    '\n'
    '${names.map((n) => "import '${n}_bundle.dart';").join('\n')}\n'
    '\n'
    '/// Every brick of the CLI, by name.\n'
    'final bundles = <String, MasonBundle>{\n'
    '${names.map((n) => "  '$n': ${n.camelCase}Bundle,").join('\n')}\n'
    '};\n',
  );
}
