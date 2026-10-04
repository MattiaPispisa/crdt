import 'package:en_logger/en_logger.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:greyhound_markdown_client/src/logging/app_logger.dart';
import 'package:greyhound_markdown_client/src/routing/app_router.dart';

/// The app-wide service locator.
final GetIt getIt = GetIt.instance;

/// Registers the app services in [getIt]: the root [EnLogger], one logger
/// per [LogScope], and the [GoRouter].
///
/// Call it once, before anything logs.
void setupServiceLocator() {
  final logger = createAppLogger();
  getIt.registerSingleton<EnLogger>(logger);
  for (final scope in LogScope.values) {
    getIt.registerLazySingleton<EnLogger>(
      () => logger.getConfiguredInstance(prefix: scope.prefix),
      instanceName: scope.name,
    );
  }
  getIt.registerLazySingleton<GoRouter>(createAppRouter);
}

/// The logger of [scope], whose logs carry [LogScope.prefix].
EnLogger loggerFor(LogScope scope) => getIt<EnLogger>(instanceName: scope.name);
