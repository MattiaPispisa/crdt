import 'dart:async';
import 'dart:io' as io;

import 'logs.dart';

/// A failure that the script reports without a stack trace.
class ScriptException implements Exception {
  ScriptException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Logs [message], waits until the logger writes it, and exits with code 1.
Future<Never> badExit(
  String message, {
  Object? error,
  StackTrace? stackTrace,
}) async {
  logger.error(message, error: error, stackTrace: stackTrace);
  await logger.close();
  await Future.wait([io.stdout.flush(), io.stderr.flush()]);
  io.exit(1);
}

/// Runs [action], and exits with [error] when it throws.
///
/// A [ScriptException] adds its message, any other error its stack trace.
Future<void> step({
  required FutureOr<void> Function() action,
  required String error,
}) async {
  try {
    await action();
  } on ScriptException catch (exception) {
    await badExit(error, error: exception);
  } catch (exception, stackTrace) {
    await badExit(error, error: exception, stackTrace: stackTrace);
  }
}

/// Runs [executable] with its output on the console, and throws a
/// [ScriptException] when it exits with a code other than 0.
Future<void> run(
  String executable,
  List<String> arguments, {
  io.Directory? workingDir,
}) async {
  final process = await io.Process.start(
    executable,
    arguments,
    workingDirectory: workingDir?.path,
    mode: io.ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ScriptException(
      '`$executable ${arguments.join(' ')}` failed (exit code: $exitCode)',
    );
  }
}
