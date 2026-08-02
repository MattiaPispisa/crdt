import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/services/export/document_export.dart';
import 'package:greyhound_markdown_client/src/widgets/export_menu.dart';

import 'helpers/recording_file_saver.dart';

void main() {
  // The PDF format loads its fonts from the asset bundle.
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A room whose document is bound to [text], with the menu in an app bar.
  Future<RecordingFileSaver> pumpMenu(WidgetTester tester, String text) async {
    final document = CRDTDocument(peerId: PeerId.generate());
    final handler = CRDTFugueTextHandler(document, kHandlerId);
    if (text.isNotEmpty) {
      handler.insert(0, text);
    }
    addTearDown(document.dispose);

    final saver = RecordingFileSaver();
    await tester.pumpWidget(
      CrdtProvider.value(
        value: document,
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                ExportMenu(
                  fallbackName: 'greyhound-42',
                  exporter: DocumentExporter(saver: saver),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return saver;
  }

  testWidgets('an empty document has nothing to export', (tester) async {
    await pumpMenu(tester, '');

    final button = tester.widget<PopupMenuButton<ExportFormat>>(
      find.byType(PopupMenuButton<ExportFormat>),
    );
    expect(button.enabled, isFalse);
  });

  testWidgets('picking a format asks for a name, then saves under it', (
    tester,
  ) async {
    final saver = await pumpMenu(tester, '# Notes\n\nHello.');

    await tester.tap(find.byType(PopupMenuButton<ExportFormat>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HTML (.html)'));
    await tester.pumpAndSettle();

    // The name is offered, taken from the document's first heading, and the
    // user is free to change it.
    expect(find.text('Export as HTML'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'notes'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'My Draft');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saver.saves, 1);
    expect(saver.fileName, 'my-draft.html');
    expect(find.text('Saved my-draft.html'), findsOneWidget);
  });

  testWidgets('backing out of the name dialog exports nothing', (
    tester,
  ) async {
    final saver = await pumpMenu(tester, '# Notes');

    await tester.tap(find.byType(PopupMenuButton<ExportFormat>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF (.pdf)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(saver.saves, 0);
  });
}
