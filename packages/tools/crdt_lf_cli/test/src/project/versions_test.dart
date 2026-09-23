import 'dart:io';

import 'package:crdt_lf_cli/src/project/versions.dart';
import 'package:mason/mason.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The folders of the repository packages, from the package root.
const _packageDirs = {
  'crdt_lf': '../../core/crdt_lf',
  'crdt_lf_drift': '../../adapters/persistence/crdt_lf_drift',
  'crdt_lf_hive': '../../adapters/persistence/crdt_lf_hive',
  'crdt_lf_persistence': '../../core/crdt_lf_persistence',
  'crdt_lf_sqlite': '../../adapters/persistence/crdt_lf_sqlite',
  'crdt_socket_sync': '../../core/crdt_socket_sync',
};

void main() {
  test('every repository package has a version', () {
    expect(_packageDirs.keys.toSet(), repositoryPackages);
    expect(packageVersions.keys, containsAll(repositoryPackages));
  });

  // A release that the constraint does not allow would leave new projects
  // on the old version.
  test('each constraint allows the version in the repository', () {
    for (final package in repositoryPackages) {
      final pubspec = File(p.join(_packageDirs[package]!, 'pubspec.yaml'))
          .readAsLinesSync();
      final line = pubspec.firstWhere((line) => line.startsWith('version:'));
      final version = Version.parse(line.substring('version:'.length).trim());
      final constraint = VersionConstraint.parse(packageVersions[package]!);

      expect(constraint.allows(version), isTrue, reason: '$package $version');
    }
  });
}
