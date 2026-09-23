import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:crdt_lf_cli/src/commands/create_command.dart';
import 'package:crdt_lf_cli/src/version.dart';
import 'package:mason/mason.dart' hide packageVersion;

/// The `crdt_lf` command-line tool.
class CrdtLfCommandRunner extends CommandRunner<int> {
  /// Creates the runner, which reports to [logger].
  CrdtLfCommandRunner({Logger? logger})
      : _logger = logger ?? Logger(),
        super('crdt_lf', 'Generates crdt_lf projects.') {
    argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print the current version.',
    );
    addCommand(CreateCommand(logger: _logger));
  }

  final Logger _logger;

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      return await runCommand(parse(args)) ?? ExitCode.success.code;
    } on UsageException catch (error) {
      _logger
        ..err(error.message)
        ..info('')
        ..info(error.usage);
      return ExitCode.usage.code;
    }
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults.flag('version')) {
      _logger.info(packageVersion);
      return ExitCode.success.code;
    }
    return super.runCommand(topLevelResults);
  }
}
