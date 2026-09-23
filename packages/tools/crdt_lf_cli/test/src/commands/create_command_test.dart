import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:crdt_lf_cli/src/commands/create_command.dart';
import 'package:crdt_lf_cli/src/project/project_generator.dart';
import 'package:crdt_lf_cli/src/project/project_options.dart';
import 'package:mason/mason.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Records what it is asked to generate, and writes nothing.
class _RecordingGenerator extends ProjectGenerator {
  _RecordingGenerator() : super(logger: Logger(level: Level.quiet));

  final generated = <(ProjectOptions, Directory)>[];

  @override
  Future<List<GeneratedFile>> generate(
    ProjectOptions options,
    Directory root,
  ) async {
    generated.add((options, root));
    return const [];
  }
}

void main() {
  late Directory temp;
  late _RecordingGenerator generator;
  late List<Directory> pubGets;
  late int pubGetCode;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('crdt_lf_cli');
    generator = _RecordingGenerator();
    pubGets = [];
    pubGetCode = 0;
  });

  tearDown(() => temp.delete(recursive: true));

  Future<int?> run(List<String> args) {
    final runner = CommandRunner<int>('crdt_lf', 'test')
      ..addCommand(
        CreateCommand(
          logger: Logger(level: Level.quiet),
          generator: generator,
          pubGet: (directory) async {
            pubGets.add(directory);
            return pubGetCode;
          },
        ),
      );
    return runner.run(['create', ...args, '-o', temp.path]);
  }

  test('reads every choice from its flag', () async {
    final code = await run([
      'notes',
      '--server',
      'plain',
      '--server-storage',
      'drift',
      '--handler',
      'none',
    ]);

    expect(code, ExitCode.success.code);
    final (options, root) = generator.generated.single;
    expect(options.name, 'notes');
    expect(options.server, ServerKind.plain);
    expect(options.serverStorage, StorageKind.drift);
    expect(options.handler, HandlerKind.none);
    expect(root.path, p.join(temp.path, 'notes'));
    expect(pubGets.single.path, root.path);
  });

  test('takes the defaults without prompts when not interactive', () async {
    await run(['notes', '--no-interactive', '--no-pub-get']);

    final (options, _) = generator.generated.single;
    expect(options.server, ServerKind.plain);
    expect(options.serverStorage, StorageKind.sqlite);
    expect(options.handler, HandlerKind.fugueText);
    expect(pubGets, isEmpty);
  });

  test('refuses a folder that already holds files', () async {
    final root = Directory(p.join(temp.path, 'notes'))..createSync();
    File(p.join(root.path, 'keep.txt')).writeAsStringSync('mine');

    final code = await run(['notes', '--no-interactive']);

    expect(code, ExitCode.cantCreate.code);
    expect(generator.generated, isEmpty);
  });

  test('returns the exit code of a failed pub get', () async {
    pubGetCode = 69;

    expect(await run(['notes', '--no-interactive']), 69);
  });

  test('rejects an invalid project name as a usage error', () {
    expect(
      run(['My-Notes', '--no-interactive']),
      throwsA(isA<UsageException>()),
    );
  });

  test('rejects a missing project name as a usage error', () {
    expect(run(['--no-interactive']), throwsA(isA<UsageException>()));
  });
}
