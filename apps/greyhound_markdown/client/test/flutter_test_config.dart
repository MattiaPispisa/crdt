import 'dart:async';

import 'package:greyhound_markdown_client/src/di/service_locator.dart';

/// Registers the app services before every test file, like `main` does.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setupServiceLocator();
  await testMain();
}
