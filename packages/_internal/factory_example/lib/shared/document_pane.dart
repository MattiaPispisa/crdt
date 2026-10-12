import 'package:factory_example/shared/add_item_dialog.dart';
import 'package:factory_example/shared/connection_indicator.dart';
import 'package:factory_example/shared/document_controls.dart';
import 'package:factory_example/shared/example_document.dart';
import 'package:flutter/material.dart';

/// One pane of an example: the document info, the connection status, the
/// list [body], the time-travel slider and the bottom actions, plus an add
/// FAB.
///
/// The [body] (the actual list rendering) is provided by each example because
/// it differs (a plain list vs a reorderable one); everything around it is
/// shared.
class DocumentPane extends StatelessWidget {
  /// Creates a pane for [state] rendering [body].
  const DocumentPane({
    required this.state,
    required this.body,
    required this.onAdd,
    super.key,
    this.addDialogTitle = 'Add New Todo',
  });

  /// The document controller backing this pane.
  final ExampleDocument state;

  /// The list rendering for this example.
  final Widget body;

  /// Called with the new item text from the add dialog.
  final void Function(String text) onAdd;

  /// Title of the add dialog.
  final String addDialogTitle;

  Future<void> _showAddDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => AddItemDialog(title: addDialogTitle, onAdd: onAdd),
    );
  }

  Widget _historySlider() {
    final session = state.historySession;
    if (!state.isTimeTraveling || session == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DocumentHistorySlider(historySession: session),
    );
  }

  Widget _bottomActions() {
    final children = <Widget>[
      if (state.isTimeTraveling)
        BackToLiveButton(state: state)
      else ...[
        ToHistoryViewButton(state: state),
        GarbageCollectionButton(state: state),
      ],
    ];
    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: children),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DocumentInfo(state: state),
              const Spacer(),
              if (state.client case final client?)
                ConnectionIndicator(client: client),
            ],
          ),
          Expanded(child: body),
          _historySlider(),
          _bottomActions(),
        ],
      ),
      floatingActionButton:
          state.isTimeTraveling
              ? null
              : FloatingActionButton(
                heroTag: state.author.toString(),
                onPressed: () => _showAddDialog(context),
                tooltip: 'Add',
                child: const Icon(Icons.add),
              ),
    );
  }
}
