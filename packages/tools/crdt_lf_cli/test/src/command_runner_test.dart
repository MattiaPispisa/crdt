import 'dart:io';

import 'package:crdt_lf_cli/src/command_runner.dart';
import 'package:crdt_lf_cli/src/version.dart';
import 'package:mason/mason.dart' hide packageVersion;
import 'package:test/test.dart';

/// Keeps what the runner prints.
class _RecordingLogger extends Logger {
  _RecordingLogger() : super(level: Level.quiet);

  final infos = <String>[];
  final errors = <String>[];

  @override
  void info(String? message, {LogStyle? style}) => infos.add('$message');

  @override
  void err(String? message, {LogStyle? style}) => errors.add('$message');
}

void main() {
  test('--version prints the version', () async {
    final logger = _RecordingLogger();

    final code = await CrdtLfCommandRunner(logger: logger).run(['--version']);

    expect(code, ExitCode.success.code);
    expect(logger.infos, [packageVersion]);
  });

  test('a usage error prints it and exits with the usage code', () async {
    final logger = _RecordingLogger();

    final code = await CrdtLfCommandRunner(logger: logger).run(['create']);

    expect(code, ExitCode.usage.code);
    expect(logger.errors.single, contains('project name'));
  });

  test('the version matches the pubspec', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    expect(pubspec, contains('version: $packageVersion'));
  });
}
