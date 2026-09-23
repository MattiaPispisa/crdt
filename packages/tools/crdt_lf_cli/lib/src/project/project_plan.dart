import 'package:crdt_lf_cli/src/project/project_options.dart';
import 'package:crdt_lf_cli/src/project/versions.dart';

/// One brick to generate, in one directory, with its variables.
class BrickRun {
  /// Creates a run of [brick] into [directory].
  const BrickRun({
    required this.brick,
    required this.directory,
    required this.vars,
  });

  /// The name of the brick, as in its `brick.yaml`.
  final String brick;

  /// Where the brick writes, relative to the project root; `.` is the root.
  final String directory;

  /// The variables the brick renders with.
  final Map<String, Object?> vars;

  @override
  String toString() => 'BrickRun($brick -> $directory)';
}

/// The bricks that make the project [options] describes, in order.
///
/// Each brick owns its own files, so the order only matters for the reader.
/// The package bricks come before the bricks that fill a file inside them.
List<BrickRun> planProject(ProjectOptions options) {
  final name = options.name;
  final shared = '${name}_shared';
  final server = '${name}_server';

  return [
    BrickRun(
      brick: 'workspace',
      directory: '.',
      vars: {
        'name': name,
        'members': _yamlList([shared, if (options.hasServer) server]),
        'has_server': options.hasServer,
      },
    ),
    BrickRun(
      brick: 'shared',
      directory: shared,
      vars: {
        'name': name,
        'dependencies': _dependencies(['crdt_lf']),
        'dev_dependencies': _dependencies(['lints']),
      },
    ),
    BrickRun(
      brick: _handlerBrick(options.handler),
      directory: shared,
      vars: {'name': name},
    ),
    if (options.hasServer) ...[
      BrickRun(
        brick: 'server_plain',
        directory: server,
        vars: {
          'name': name,
          'dependencies': _dependencies([
            'crdt_lf',
            'crdt_lf_persistence',
            'crdt_socket_sync',
            ..._storagePackages(options.serverStorage),
          ]),
          'dev_dependencies': _dependencies(['lints', 'test']),
          'storage_implemented': options.serverStorage.isImplemented,
        },
      ),
      BrickRun(
        brick: _storageBrick(options.serverStorage),
        directory: server,
        vars: {'name': name},
      ),
    ],
  ];
}

String _handlerBrick(HandlerKind handler) {
  return switch (handler) {
    HandlerKind.none => 'handler_none',
    HandlerKind.fugueText => 'handler_fugue_text',
  };
}

String _storageBrick(StorageKind storage) {
  return switch (storage) {
    StorageKind.none => throw ArgumentError.value(storage, 'storage'),
    StorageKind.infrastructure => 'storage_infrastructure',
    StorageKind.hive => 'storage_hive',
    StorageKind.drift => 'storage_drift',
    StorageKind.sqlite => 'storage_sqlite',
  };
}

/// The packages the `lib/src/storage.dart` of [storage] imports.
List<String> _storagePackages(StorageKind storage) {
  return switch (storage) {
    StorageKind.none => const [],
    StorageKind.infrastructure => const ['crdt_lf_persistence'],
    StorageKind.hive => const ['crdt_lf_hive', 'hive'],
    StorageKind.drift => const ['crdt_lf_drift', 'path'],
    StorageKind.sqlite => const ['crdt_lf_sqlite', 'path'],
  };
}

/// The pubspec lines of [packages]: sorted, once each, with the version of
/// [packageVersions].
String _dependencies(List<String> packages) {
  final sorted = packages.toSet().toList()..sort();
  return [
    for (final package in sorted)
      '  $package: "${packageVersions[package]!}"',
  ].join('\n');
}

/// [items] as the lines of a YAML list.
String _yamlList(List<String> items) {
  return [for (final item in items) '  - $item'].join('\n');
}
