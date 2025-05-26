import 'dart:async';

/// Try to execute a function and ignore the error
Future<void> tryCatchIgnore(FutureOr<void> Function() fn) async {
  try {
    await fn();
  } catch (e) {
    // Ignore the error
  }
}
