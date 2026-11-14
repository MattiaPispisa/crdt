// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:greyhound_markdown_client/src/widgets/router_back_button.dart';

import 'helpers/router_app.dart';

void main() {
  group('RouterBackButton', () {
    testWidgets('leaves the first page of the room shell for Home', (
      tester,
    ) async {
      final router = await pumpRouterApp(
        tester,
        initialLocation: '/room/abc123',
        roomBuilder: (roomId) => Scaffold(
          appBar: AppBar(leading: const RouterBackButton()),
          body: Text('room $roomId'),
        ),
      );

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(locationOf(router), '/');
    });
  });
}
