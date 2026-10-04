import 'package:en_logger/en_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:greyhound_markdown_client/src/di/service_locator.dart';
import 'package:greyhound_markdown_client/src/logging/app_logger.dart';

/// Keeps the prefix and severity of every log it receives.
class _RecordingHandler extends EnLoggerHandler {
  final List<({String? prefix, Severity severity, String message})> logs = [];

  @override
  void write(
    String message, {
    required Severity severity,
    required DateTime timestamp,
    required String eventId,
    required Map<String, dynamic> tags,
    required int sequenceNumber,
    String? prefix,
    Object? error,
    StackTrace? stackTrace,
    List<EnLoggerData>? data,
    String? isolateName,
    String? callerInfo,
  }) {
    logs.add((prefix: prefix, severity: severity, message: message));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each scope logs through its own prefixed instance', () async {
    // Before the first `loggerFor`: an instance copies the root's handlers
    // when it is created.
    final handler = _RecordingHandler();
    getIt<EnLogger>().addHandler(handler);

    for (final scope in LogScope.values) {
      loggerFor(scope).info('hello');
    }
    await pumpEventQueue();

    expect(handler.logs.map((log) => log.prefix), [
      for (final scope in LogScope.values) scope.prefix,
    ]);
    expect(
      handler.logs.map((log) => log.severity),
      everyElement(Severity.informational),
    );
    expect(loggerFor(LogScope.room), same(loggerFor(LogScope.room)));
  });

  test('provides the router', () {
    expect(getIt<GoRouter>(), same(getIt<GoRouter>()));
  });
}
