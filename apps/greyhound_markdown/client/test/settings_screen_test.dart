import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:greyhound_markdown_client/src/application/application.dart';
import 'package:greyhound_markdown_client/src/screens/settings_screen.dart';

import 'helpers/memory_storage.dart';

void main() {
  testWidgets('SettingsScreen stores the picked theme mode', (tester) async {
    final cubit = UserSettingsCubit(storage: MemoryStorage());
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    expect(cubit.state.themeMode, ThemeMode.system);

    await tester.tap(find.text('Dark'));
    await tester.pump();

    expect(cubit.state.themeMode, ThemeMode.dark);
  });
}
