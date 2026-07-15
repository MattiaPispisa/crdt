import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrdtTextField', () {
    testWidgets('reports local edits through onChanged', (tester) async {
      var lastValue = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CrdtTextFieldBuilder(
              value: '',
              builder: (context, textEditingController) {
                return TextField(
                  controller: textEditingController,
                  onChanged: (v) => lastValue = v,
                );
              },
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'hello');
      expect(lastValue, 'hello');
    });

    testWidgets('adopts a remote value change while focused', (tester) async {
      await tester.pumpWidget(
        const _Host(initial: 'hello'),
      );

      // Focus the field.
      await tester.tap(find.byType(TextField));
      await tester.pump();

      // A concurrent remote edit changes the value out from under the field.
      tester.state<_HostState>(find.byType(_Host)).setValue('hello world');
      await tester.pump();

      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;
      expect(controller.text, 'hello world');
      // Caret stays within bounds.
      expect(controller.selection.baseOffset, lessThanOrEqualTo(11));
    });
  });
}

class _Host extends StatefulWidget {
  const _Host({required this.initial});

  final String initial;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late String _value = widget.initial;

  void setValue(String value) => setState(() => _value = value);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: CrdtTextFieldBuilder(
          value: _value,
          builder: (context, textEditingController) {
            return TextField(
              controller: textEditingController,
              onChanged: setValue,
            );
          },
        ),
      ),
    );
  }
}
