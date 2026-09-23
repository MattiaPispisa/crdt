import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:crdt_lf_cli/src/project/project_generator.dart';
import 'package:crdt_lf_cli/src/project/project_options.dart';
import 'package:mason/mason.dart';
import 'package:path/path.dart' as p;

/// Runs `dart pub get` in a directory and returns the exit code.
typedef PubGet = Future<int> Function(Directory directory);

/// `crdt_lf create <name>`: generates a new project.
///
/// Every choice has a flag. A choice without its flag is asked with a
/// prompt. It takes its default when `--no-interactive` is set or when
/// there is no terminal.
class CreateCommand extends Command<int> {
  /// Creates the command, which reports to [logger].
  ///
  /// [generator] and [pubGet] replace the real ones in tests.
  CreateCommand({
    required Logger logger,
    ProjectGenerator? generator,
    PubGet? pubGet,
  })  : _logger = logger,
        _generator = generator ?? ProjectGenerator(logger: logger),
        _pubGet = pubGet ?? _dartPubGet {
    argParser
      ..addOption(
        'output-directory',
        abbr: 'o',
        help: 'Where the project folder is created.',
        defaultsTo: '.',
      )
      ..addOption(
        'server',
        help: 'The server of the project.',
        allowed: _flags(_servers),
        allowedHelp: _allowedHelp(_servers),
      )
      ..addOption(
        'server-storage',
        help: 'Where the server keeps its documents.',
        allowed: _flags(_serverStorages),
        allowedHelp: _allowedHelp(_serverStorages),
      )
      ..addOption(
        'handler',
        help: 'The handlers the document starts with.',
        allowed: _flags(HandlerKind.values),
        allowedHelp: _allowedHelp(HandlerKind.values),
      )
      ..addFlag(
        'interactive',
        help: 'Ask for every choice that has no flag.',
        defaultsTo: true,
      )
      ..addFlag(
        'pub-get',
        help: 'Run `dart pub get` once the files are written.',
        defaultsTo: true,
      );
  }

  // `none` returns with the client: a project needs one of the two.
  static const _servers = [ServerKind.plain];

  static const _serverStorages = [
    StorageKind.infrastructure,
    StorageKind.hive,
    StorageKind.drift,
    StorageKind.sqlite,
  ];

  final Logger _logger;
  final ProjectGenerator _generator;
  final PubGet _pubGet;

  @override
  String get name => 'create';

  @override
  String get description => 'Generates a new crdt_lf project.';

  @override
  String get invocation => 'crdt_lf create <name> [arguments]';

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.length != 1) {
      usageException('Give exactly one project name.');
    }

    final ProjectOptions options;
    try {
      options = _readOptions(args.rest.single);
    } on ArgumentError catch (error) {
      usageException('${error.message}');
    }

    final root = Directory(
      p.join(args.option('output-directory')!, options.name),
    );
    if (root.existsSync() && root.listSync().isNotEmpty) {
      _logger.err('${root.path} already exists and is not empty.');
      return ExitCode.cantCreate.code;
    }

    final generating = _logger.progress('Generating ${options.name}');
    final files = await _generator.generate(options, root);
    generating.complete('Generated ${files.length} files in ${root.path}');

    if (args.flag('pub-get')) {
      final resolving = _logger.progress('Running dart pub get');
      final code = await _pubGet(root);
      if (code != 0) {
        resolving.fail('dart pub get failed. Run it in ${root.path}.');
        return code;
      }
      resolving.complete();
    }

    _logger
      ..info('')
      ..success('Created ${options.name}.')
      ..info('Start the server:')
      ..info('  cd ${p.join(root.path, '${options.name}_server')}')
      ..info('  dart run bin/server.dart');
    return ExitCode.success.code;
  }

  ProjectOptions _readOptions(String name) {
    final server = _choose(
      'server',
      'Which server?',
      _servers,
      ServerKind.plain,
    );
    final serverStorage = server == ServerKind.none
        ? StorageKind.none
        : _choose(
            'server-storage',
            'Where does the server keep its documents?',
            _serverStorages,
            StorageKind.sqlite,
          );
    final handler = _choose(
      'handler',
      'Which handlers does the document start with?',
      HandlerKind.values,
      HandlerKind.fugueText,
    );
    return ProjectOptions(
      name: name,
      server: server,
      serverStorage: serverStorage,
      handler: handler,
    );
  }

  /// The value of [option]: from its flag, else from a prompt, else
  /// [defaultValue]. A single value is taken without a prompt.
  T _choose<T extends ProjectChoice>(
    String option,
    String question,
    List<T> values,
    T defaultValue,
  ) {
    final args = argResults!;
    if (args.wasParsed(option)) {
      return choiceFromFlag(values, args.option(option)!);
    }
    if (values.length == 1) {
      return values.single;
    }
    // A prompt needs a terminal to read the arrow keys.
    if (!args.flag('interactive') || !stdin.hasTerminal) {
      return defaultValue;
    }
    try {
      return _logger.chooseOne<T>(
        question,
        choices: values,
        defaultValue: defaultValue,
        display: (value) => '${value.flag}: ${value.help}',
      );
    } on StdinException {
      // `hasTerminal` is true for some inputs that are not one, such as
      // `/dev/null` on macOS.
      return defaultValue;
    }
  }
}

List<String> _flags(List<ProjectChoice> values) {
  return [for (final value in values) value.flag];
}

Map<String, String> _allowedHelp(List<ProjectChoice> values) {
  return {for (final value in values) value.flag: value.help};
}

Future<int> _dartPubGet(Directory directory) async {
  final result = await Process.run(
    'dart',
    ['pub', 'get'],
    workingDirectory: directory.path,
    runInShell: true,
  );
  return result.exitCode;
}
