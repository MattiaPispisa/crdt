import 'dart:io' as io;

import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:yaml/yaml.dart' as yaml;

import 'fs.dart';

/// A package of the workspace: a folder with a `pubspec.yaml`.
class Package {
  Package(this.dir, this.pubspec);

  final io.Directory dir;
  final Pubspec pubspec;

  String get name => pubspec.name;

  io.File get pubspecFile => io.File(path.join(dir.path, 'pubspec.yaml'));

  /// The rule of `melos publish`: a `version`, and a `publish_to` other than
  /// `none`.
  bool get isPublished =>
      pubspec.version != null && pubspec.publishTo != 'none';

  /// The path from the repository root, with `/` on every platform.
  String get repoPath =>
      path.posix.joinAll(path.split(relativeToRoot(dir.path)));
}

/// Every package under `packages/`, sorted by path.
///
/// The walk stops at a package, so the apps inside a package (`example/`,
/// `flutter_example/`) are left out.
List<Package> packages() {
  final result = <Package>[];

  void walk(io.Directory dir) {
    final pubspec = io.File(path.join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      result.add(Package(dir, Pubspec.parse(pubspec.readAsStringSync())));
      return;
    }
    dir
        .listSync()
        .whereType<io.Directory>()
        .where((dir) => !isSkipped(dir))
        .forEach(walk);
  }

  walk(packagesDir());
  return result..sort((a, b) => a.dir.path.compareTo(b.dir.path));
}

/// The `repository` URL of `melos.yaml`.
String repositoryUrl() {
  final melos = io.File(path.join(rootPath, 'melos.yaml'));
  final map = yaml.loadYaml(melos.readAsStringSync()) as yaml.YamlMap;
  return map['repository'] as String;
}
