import 'dart:io';

import 'package:crdt_lf_cli/src/bundles/bundles.dart';
import 'package:mason/mason.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // A brick edited without `dart run tool/generate_bundles.dart` would ship
  // its old content.
  test('the bundles match the bricks', () {
    final bricks = Directory('bricks')
        .listSync()
        .whereType<Directory>()
        .map(createBundle)
        .toList();

    expect(bundles.keys.toSet(), {for (final b in bricks) b.name});
    for (final brick in bricks) {
      expect(
        bundles[brick.name]!.toJson(),
        brick.toJson(),
        reason: '${brick.name} is stale: run tool/generate_bundles.dart',
      );
    }
  });

  test('every brick has a brick.yaml', () {
    for (final dir in Directory('bricks').listSync().whereType<Directory>()) {
      expect(File(p.join(dir.path, 'brick.yaml')).existsSync(), isTrue);
    }
  });
}
