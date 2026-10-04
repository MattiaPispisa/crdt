import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:greyhound_markdown_client/l10n/gen/app_l10n.dart';
import 'package:greyhound_markdown_client/src/application/application.dart';
import 'package:greyhound_markdown_client/src/routing/app_router.dart';

import 'memory_storage.dart';

/// Pumps the app router at [initialLocation], over settings restored from
/// [stored], and returns it.
///
/// The room page is a stub that shows its room id: the editor needs a relay
/// that a test must not reach.
Future<GoRouter> pumpRouterApp(
  WidgetTester tester, {
  String initialLocation = '/',
  Map<String, dynamic>? stored,
}) async {
  final storage = MemoryStorage(
    stored == null ? null : {'UserSettings': stored},
  );
  final router = createAppRouter(
    initialLocation: initialLocation,
    roomBuilder: (roomId) => Scaffold(body: Text('room $roomId')),
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    BlocProvider(
      create: (_) => UserSettingsCubit(storage: storage),
      child: MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  // One frame, not `pumpAndSettle`: the changelog shows a spinner until its
  // asset loads, and that load may still be pending under the fake clock.
  await tester.pump();
  return router;
}

/// The location [router] shows now.
String locationOf(GoRouter router) => router.state.uri.toString();

/// A context below [router], to navigate with.
BuildContext contextOf(GoRouter router) =>
    router.routerDelegate.navigatorKey.currentContext!;
