import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:greyhound_markdown_client/src/routing/app_router.dart';

/// The app-wide service locator.
final GetIt getIt = GetIt.instance;

/// Registers the app services in [getIt]: the [GoRouter].
///
/// Call it once, before `runApp`.
void setupServiceLocator() {
  getIt.registerLazySingleton<GoRouter>(createAppRouter);
}
