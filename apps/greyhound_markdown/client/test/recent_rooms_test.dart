import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:greyhound_markdown_client/l10n/gen/app_l10n.dart';
import 'package:greyhound_markdown_client/src/application/application.dart';
import 'package:greyhound_markdown_client/src/widgets/recent_rooms.dart';

import 'helpers/localized_app.dart';
import 'helpers/memory_storage.dart';

/// Pumps the list over settings holding [rooms], collecting the ids it opens.
///
/// [rooms] is a `List<Object>` on purpose: hydrated_bloc rewrites the list it
/// reads in place, so a stricter element type makes the whole payload fail to
/// load — which is not what these tests are about.
Future<List<String>> _pumpRooms(
  WidgetTester tester,
  List<Object> rooms,
) async {
  final opened = <String>[];
  await tester.pumpWidget(
    BlocProvider(
      create: (_) => UserSettingsCubit(
        storage: MemoryStorage({
          'UserSettings': {'recentRooms': rooms},
        }),
      ),
      child: localizedApp(Scaffold(body: RecentRooms(onOpen: opened.add))),
    ),
  );
  return opened;
}

void main() {
  group('RecentRooms', () {
    testWidgets('draws nothing before a room has been opened', (tester) async {
      await _pumpRooms(tester, []);

      expect(find.text('Recently opened'), findsNothing);
    });

    testWidgets('lists the stored rooms and opens the tapped one', (
      tester,
    ) async {
      final now = DateTime.now().toUtc();
      final opened = await _pumpRooms(tester, <Object>[
        {'roomId': 'abc123', 'openedAt': now.millisecondsSinceEpoch},
        {
          'roomId': 'def456',
          'openedAt': now
              .subtract(const Duration(days: 2))
              .millisecondsSinceEpoch,
        },
      ]);

      expect(find.text('Recently opened'), findsOneWidget);
      expect(find.text('abc123'), findsOneWidget);
      expect(find.text('just now'), findsOneWidget);
      expect(find.text('2 days ago'), findsOneWidget);

      await tester.tap(find.text('def456'));
      expect(opened, ['def456']);
    });
  });

  group('relativeTime', () {
    final now = DateTime.utc(2026, 9, 6, 12);
    late AppL10n l10n;

    setUpAll(() async {
      l10n = await englishL10n();
    });

    test('counts up in the coarsest unit that fits', () {
      String ago(Duration elapsed) =>
          relativeTime(l10n, now.subtract(elapsed), now);

      expect(ago(const Duration(seconds: 30)), 'just now');
      expect(ago(const Duration(minutes: 5)), '5 min ago');
      expect(ago(const Duration(hours: 3)), '3 h ago');
      expect(ago(const Duration(days: 1)), 'yesterday');
      expect(ago(const Duration(days: 6)), '6 days ago');
    });

    test('gives the date once the week is past', () {
      final past = DateTime.utc(2026, 8, 4, 12);
      // Read in the local zone, so the date shown is the user's own, and
      // written the way the locale writes a date.
      final expected = DateFormat.yMd('en').format(past.toLocal());

      expect(relativeTime(l10n, past, now), expected);
    });
  });
}
