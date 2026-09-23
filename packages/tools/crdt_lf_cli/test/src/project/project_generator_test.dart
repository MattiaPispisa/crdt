import 'dart:io';

import 'package:crdt_lf_cli/src/project/project_generator.dart';
import 'package:crdt_lf_cli/src/project/project_options.dart';
import 'package:crdt_lf_cli/src/project/versions.dart';
import 'package:mason/mason.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The repository packages a generated project can reach, by folder.
const _localPackages = {
  'crdt_lf': 'core/crdt_lf',
  'crdt_lf_drift': 'adapters/persistence/crdt_lf_drift',
  'crdt_lf_hive': 'adapters/persistence/crdt_lf_hive',
  'crdt_lf_persistence': 'core/crdt_lf_persistence',
  'crdt_lf_sqlite': 'adapters/persistence/crdt_lf_sqlite',
  'crdt_socket_sync': 'core/crdt_socket_sync',
  'hlc_dart': 'core/hlc',
};

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('crdt_lf_cli');
  });

  tearDown(() => temp.delete(recursive: true));

  Future<Directory> generate(ProjectOptions options) async {
    final root = Directory(p.join(temp.path, options.name));
    await ProjectGenerator(logger: Logger(level: Level.quiet))
        .generate(options, root);
    return root;
  }

  test('writes the workspace, the shared package and the server', () async {
    final root = await generate(
      ProjectOptions(
        name: 'notes',
        server: ServerKind.plain,
        serverStorage: StorageKind.hive,
        handler: HandlerKind.fugueText,
      ),
    );

    final files = root
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => p.relative(file.path, from: root.path))
        .toSet();
    expect(
      files,
      containsAll([
        'pubspec.yaml',
        p.join('notes_shared', 'lib', 'notes_shared.dart'),
        p.join('notes_shared', 'lib', 'src', 'schema.dart'),
        p.join('notes_server', 'bin', 'server.dart'),
        p.join('notes_server', 'lib', 'src', 'storage.dart'),
      ]),
    );
    final storage = File(
      p.join(root.path, 'notes_server', 'lib', 'src', 'storage.dart'),
    ).readAsStringSync();
    expect(storage, contains('CRDTHive.open()'));
  });

  // Resolves every project against the packages of this repository and runs
  // its tests. Slow: it runs `dart pub get` and `dart test` once per project.
  group('every generated project passes its own tests', () {
    for (final storage in StorageKind.values) {
      if (storage == StorageKind.none) {
        continue;
      }
      for (final handler in HandlerKind.values) {
        test('${storage.flag} + ${handler.flag}', () async {
          final options = ProjectOptions(
            name: 'e2e_${storage.flag}',
            server: ServerKind.plain,
            serverStorage: storage,
            handler: handler,
          );
          final root = await generate(options);
          _overrideWithLocalPackages(root);

          await _run('dart', ['pub', 'get'], root);
          await _run(
            'dart',
            ['test'],
            Directory(p.join(root.path, '${options.name}_server')),
          );
        });
      }
    }
  }, tags: 'e2e');
}

/// Points every repository package at its folder, so the project tests the
/// code of this checkout instead of the last release.
void _overrideWithLocalPackages(Directory root) {
  final packages = Directory(p.join('..', '..')).absolute.path;
  final overrides = StringBuffer('dependency_overrides:\n');
  for (final entry in _localPackages.entries) {
    final path = p.normalize(p.join(packages, entry.value));
    overrides
      ..writeln('  ${entry.key}:')
      ..writeln('    path: $path');
  }
  expect(
    _localPackages.keys,
    containsAll(repositoryPackages),
    reason: 'a repository package is missing from the overrides',
  );
  File(p.join(root.path, 'pubspec_overrides.yaml'))
      .writeAsStringSync(overrides.toString());
}

Future<void> _run(String executable, List<String> args, Directory dir) async {
  final result = await Process.run(
    executable,
    args,
    workingDirectory: dir.path,
    runInShell: true,
  );
  expect(
    result.exitCode,
    0,
    reason: '$executable ${args.join(' ')} in ${dir.path}\n'
        '${result.stdout}\n${result.stderr}',
  );
}
