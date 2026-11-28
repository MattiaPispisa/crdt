import 'dart:io' as io;

import 'package:en_logger/en_logger.dart' as l;

final logger = l.EnLogger(
  handlers: [_ConsoleHandler()],
);

/// Writes errors and worse to stderr, the other messages to stdout.
class _ConsoleHandler extends l.EnLoggerHandler {
  _ConsoleHandler()
      : _stdout = l.PrintLogHandler.custom(
          printCallback: io.stdout.writeln,
          useColors: io.stdout.supportsAnsiEscapes,
        ),
        _stderr = l.PrintLogHandler.custom(
          printCallback: io.stderr.writeln,
          useColors: io.stderr.supportsAnsiEscapes,
        );

  final l.PrintLogHandler _stdout;
  final l.PrintLogHandler _stderr;

  @override
  void write(
    String message, {
    required l.Severity severity,
    required DateTime timestamp,
    required String eventId,
    required Map<String, dynamic> tags,
    required int sequenceNumber,
    String? prefix,
    Object? error,
    StackTrace? stackTrace,
    List<l.EnLoggerData>? data,
    String? isolateName,
    String? callerInfo,
  }) {
    (severity.atLeastError ? _stderr : _stdout).write(
      message,
      severity: severity,
      timestamp: timestamp,
      eventId: eventId,
      tags: tags,
      sequenceNumber: sequenceNumber,
      prefix: prefix,
      error: error,
      stackTrace: stackTrace,
      data: data,
      isolateName: isolateName,
      callerInfo: callerInfo,
    );
  }
}
