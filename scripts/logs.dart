import 'dart:io' as io;
import 'package:en_logger/en_logger.dart' as l;

final logger = l.EnLogger(
  handlers: [
    _PrinterHandler(),
  ],
);

/// Per-severity ANSI colors, reusing en_logger's default color mapping
/// (error → red, warning → yellow, notice → blue, informational → green,
/// debug → cyan).
final _colors = l.DevLogColorConfiguration();

/// ANSI reset sequence.
const _reset = '\x1B[0m';

class _PrinterHandler extends l.EnLoggerHandler {
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
    final header = _colorize(
      severity,
      '${_time(timestamp)} ${_label(severity)}',
    );

    final buffer = StringBuffer(header);

    if (prefix != null && prefixFormat != null) {
      buffer.write(' ${prefixFormat!.format(prefix)}');
    }

    buffer.write(' $message');

    if (error != null) {
      buffer.write('\n  ↳ error: $error');
    }
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }

    // ignore: avoid_print just for scripts purpose
    print(buffer);
  }
}

/// Formats [time] as `HH:mm:ss`.
String _time(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

/// A short, fixed-width label for [severity].
String _label(l.Severity severity) {
  switch (severity) {
    case l.Severity.emergency:
    case l.Severity.alert:
    case l.Severity.critical:
    case l.Severity.error:
      return '[ERROR]';
    case l.Severity.warning:
      return '[WARN] ';
    case l.Severity.notice:
    case l.Severity.informational:
      return '[INFO] ';
    case l.Severity.debug:
      return '[DEBUG]';
  }
}

/// Wraps [text] in en_logger's ANSI color for [severity].
///
/// Returns [text] unchanged when the terminal does not support ANSI escapes
/// (so piped/redirected output stays clean).
String _colorize(l.Severity severity, String text) {
  if (!io.stdout.supportsAnsiEscapes) {
    return text;
  }
  return '${_colors.getColor(severity).schema}$text$_reset';
}
