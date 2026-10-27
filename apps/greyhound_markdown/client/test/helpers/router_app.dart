// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

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
/// The room pages are stubs that show their room id: opening a room needs a
/// relay that a test must not reach. The shell around them shows nothing of
/// its own unless [roomShell] says otherwise.
Future<GoRouter> pumpRouterApp(
  WidgetTester tester, {
  String initialLocation = '/',
  Map<String, dynamic>? stored,
  Widget Function(String roomId, Widget child)? roomShell,
}) async {
  final storage = MemoryStorage(
    stored == null ? null : {'UserSettings': stored},
  );
  final router = createAppRouter(
    initialLocation: initialLocation,
    roomShell: roomShell ?? (roomId, child) => child,
    roomBuilder: (roomId) => Scaffold(body: Text('room $roomId')),
    historyBuilder: (roomId) => Scaffold(body: Text('history $roomId')),
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

/// The location [router] reports to the platform, the one a browser shows in
/// its address bar.
///
/// It differs from [locationOf] after a `push`, which the address bar ignores.
String reportedLocationOf(GoRouter router) => router.routeInformationParser
    .restoreRouteInformation(router.routerDelegate.currentConfiguration)!
    .uri
    .toString();

/// A context below [router], to navigate with.
BuildContext contextOf(GoRouter router) =>
    router.routerDelegate.navigatorKey.currentContext!;
