import 'dart:io' as io;

int _bad = 1;

/// Installs node dependencies in [workingDir], streaming output to the console.
///
/// When [ci] is `true`, uses `npm ci` (clean, reproducible install from the
/// lockfile, intended for CI) instead of `npm i`.
Future<StreamedResult> npmI({
  io.Directory? workingDir,
  bool ci = false,
}) async {
  return runStreamed(
    'npm',
    [
      if (ci) 'ci' else 'i',
    ],
    workingDir: workingDir,
  );
}

/// Runs `npm run build` in [workingDir], streaming output to the console.
Future<StreamedResult> npmRunBuild({io.Directory? workingDir}) async {
  return runStreamed(
    'npm',
    ['run', 'build'],
    workingDir: workingDir,
  );
}

/// Starts [executable] with [arguments] in [workingDir], inheriting stdio so
/// the process output streams live to the console, and resolves once it exits.
Future<StreamedResult> runStreamed(
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
  return StreamedResult(await process.exitCode);
}

Never badExit() {
  io.exit(_bad);
}

/// Result of a streamed process started with [runStreamed].
///
/// Exposes the same `isOk` / `isNotOk` checks one would use on an
/// [io.ProcessResult], since [runStreamed] inherits stdio and therefore does
/// not capture stdout/stderr.
class StreamedResult {
  StreamedResult(this.exitCode);

  final int exitCode;

  bool get isNotOk => exitCode == _bad;
  bool get isOk => !isNotOk;
}
