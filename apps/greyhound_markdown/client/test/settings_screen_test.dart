import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:greyhound_markdown_client/src/application/application.dart';
import 'package:greyhound_markdown_client/src/screens/settings_screen.dart';

import 'helpers/localized_app.dart';
import 'helpers/memory_storage.dart';

void main() {
  testWidgets('SettingsScreen stores the picked theme mode', (tester) async {
    final cubit = UserSettingsCubit(storage: MemoryStorage());
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: localizedApp(const SettingsScreen()),
      ),
    );

    expect(cubit.state.themeMode, ThemeMode.system);

    await tester.tap(find.text('Dark'));
    await tester.pump();

    expect(cubit.state.themeMode, ThemeMode.dark);
  });

  testWidgets('SettingsScreen stores the editor options', (tester) async {
    final cubit = UserSettingsCubit(storage: MemoryStorage());
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: localizedApp(const SettingsScreen()),
      ),
    );

    expect(cubit.state.showLineNumbers, isFalse);
    expect(cubit.state.wordWrap, isTrue);

    // Both switches sit below the fold of the test surface, far enough down
    // that the ListView has not built them yet.
    Future<void> toggle(String label) async {
      await tester.scrollUntilVisible(find.text(label), 100);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await toggle('Line numbers');
    await toggle('Word wrap');

    expect(cubit.state.showLineNumbers, isTrue);
    expect(cubit.state.wordWrap, isFalse);
  });

  testWidgets('SettingsScreen stores the picked language', (tester) async {
    final cubit = UserSettingsCubit(storage: MemoryStorage());
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: localizedApp(const SettingsScreen()),
      ),
    );

    expect(cubit.state.language, AppLanguage.system);

    // The list lives behind a dropdown, so the entry has to be opened first.
    await tester.tap(find.byType(DropdownButton<AppLanguage>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Italiano').last);
    await tester.pumpAndSettle();

    expect(cubit.state.language, AppLanguage.italian);
  });

  testWidgets('SettingsScreen reads Italian under an it locale', (
    tester,
  ) async {
    final cubit = UserSettingsCubit(storage: MemoryStorage());
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: localizedApp(
          const SettingsScreen(),
          locale: const Locale('it'),
        ),
      ),
    );

    expect(find.text('Impostazioni'), findsOneWidget);
    expect(find.text('Aspetto'), findsOneWidget);
    expect(find.text('Scuro'), findsOneWidget);
  });
}
