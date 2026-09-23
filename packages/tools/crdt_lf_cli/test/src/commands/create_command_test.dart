import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:crdt_lf_cli/src/commands/create_command.dart';
import 'package:crdt_lf_cli/src/project/project_generator.dart';
import 'package:crdt_lf_cli/src/project/project_options.dart';
import 'package:mason/mason.dart';
import 'package:path/path.dart' as p;
import 'package:test/fake.dart';
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

/// Answers every prompt with its last choice, and keeps what it showed.
class _PromptLogger extends Logger {
  _PromptLogger({this.failWith}) : super(level: Level.quiet);

  /// Thrown by every prompt instead of an answer.
  final Exception? failWith;

  final questions = <String>[];
  final shown = <String>[];

  @override
  T chooseOne<T extends Object?>(
    String? message, {
    required List<T> choices,
    T? defaultValue,
    String Function(T choice)? display,
  }) {
    final error = failWith;
    if (error != null) {
      throw error;
    }
    questions.add('$message');
    shown.addAll(choices.map(display!));
    return choices.last;
  }
}

/// A stdin that says it is a terminal.
class _Terminal extends Fake implements Stdin {
  @override
  bool get hasTerminal => true;
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

  Future<int?> run(List<String> args, {Logger? logger}) {
    final runner = CommandRunner<int>('crdt_lf', 'test')
      ..addCommand(
        CreateCommand(
          logger: logger ?? Logger(level: Level.quiet),
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

  test('asks for every choice without a flag on a terminal', () async {
    final logger = _PromptLogger();

    await IOOverrides.runZoned(
      () => run(['notes', '--handler', 'none'], logger: logger),
      stdin: _Terminal.new,
    );

    final (options, _) = generator.generated.single;
    expect(options.serverStorage, StorageKind.sqlite);
    expect(options.handler, HandlerKind.none);
    // One server only: it is taken without a question.
    expect(logger.questions, ['Where does the server keep its documents?']);
    expect(logger.shown, contains('hive: Hive, with crdt_lf_hive.'));
  });

  test('takes the default when the terminal cannot prompt', () async {
    await IOOverrides.runZoned(
      () => run(
        ['notes'],
        logger: _PromptLogger(failWith: const StdinException('no echo')),
      ),
      stdin: _Terminal.new,
    );

    final (options, _) = generator.generated.single;
    expect(options.serverStorage, StorageKind.sqlite);
    expect(options.handler, HandlerKind.fugueText);
  });

  test('runs dart pub get in the new project by default', () async {
    final runner = CommandRunner<int>('crdt_lf', 'test')
      ..addCommand(
        CreateCommand(
          logger: Logger(level: Level.quiet),
          generator: _PubspecGenerator(),
        ),
      );

    final code = await runner.run(
      ['create', 'notes', '--no-interactive', '-o', temp.path],
    );

    expect(code, ExitCode.success.code);
    final root = p.join(temp.path, 'notes');
    expect(File(p.join(root, 'pubspec.lock')).existsSync(), isTrue);
  });
}

/// Writes a pubspec with no dependencies, which resolves offline.
class _PubspecGenerator extends ProjectGenerator {
  _PubspecGenerator() : super(logger: Logger(level: Level.quiet));

  @override
  Future<List<GeneratedFile>> generate(
    ProjectOptions options,
    Directory root,
  ) async {
    root.createSync(recursive: true);
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
      'name: ${options.name}\n'
      'environment:\n'
      '  sdk: ^3.8.0\n',
    );
    return const [];
  }
}
