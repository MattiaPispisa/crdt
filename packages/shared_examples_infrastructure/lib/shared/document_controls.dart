import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart' show CrdtBuilder;
import 'package:shared_examples_infrastructure/shared/example_document.dart';
import 'package:flutter/material.dart';

/// Shows a tooltip with the document info (peer id, change count, time-travel
/// status). Shared by every example.
class DocumentInfo extends StatelessWidget {
  /// Creates a document info indicator for [state].
  const DocumentInfo({super.key, required this.state});

  /// The document controller to read the info from.
  final ExampleDocument state;

  String _info() {
    final result =
        StringBuffer('Document Info\n'.toUpperCase())
          ..writeln('Peer ID: ${state.author}')
          ..writeln('Changes Count: ${state.changesCount}');
    if (state.isTimeTraveling) {
      result.writeln(
        'Time Traveling: Yes, cursor: ${state.historySession?.cursor}',
      );
    } else {
      result.writeln('Time Traveling: No');
    }
    return result.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    // The info reads the document (changes count): rebuild on any update.
    return CrdtBuilder(
      builder:
          (context, document) => Padding(
            padding: const EdgeInsets.only(left: 24.0, bottom: 24.0),
            child: Tooltip(message: _info(), child: const Icon(Icons.info)),
          ),
    );
  }
}

/// Enters a time-travel session for [state] (disabled when there is no
/// history).
class ToHistoryViewButton extends StatelessWidget {
  /// Creates a time-travel entry button for [state].
  const ToHistoryViewButton({super.key, required this.state});

  /// The document controller to time travel.
  final ExampleDocument state;

  @override
  Widget build(BuildContext context) {
    // Enablement depends on the document history: rebuild on any update.
    return CrdtBuilder(
      builder: (context, document) {
        final canTimeTravel = state.canTimeTravel();
        return IconButton(
          tooltip:
              canTimeTravel
                  ? 'Time travel to the document history'
                  : 'No changes to time travel to',
          icon: const Icon(Icons.history),
          onPressed: canTimeTravel ? state.timeTravel : null,
        );
      },
    );
  }
}

/// Closes the time-travel session of [state].
class BackToLiveButton extends StatelessWidget {
  /// Creates a back-to-live button for [state].
  const BackToLiveButton({super.key, required this.state});

  /// The document controller to bring back to live.
  final ExampleDocument state;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Back to live document',
      icon: const Icon(Icons.live_tv),
      onPressed: state.backToLive,
    );
  }
}

/// Takes a snapshot and garbage collects the history of [state].
class GarbageCollectionButton extends StatelessWidget {
  /// Creates a garbage-collection button for [state].
  const GarbageCollectionButton({super.key, required this.state});

  /// The document controller to garbage collect.
  final ExampleDocument state;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: state.garbageCollection,
      icon: const Icon(Icons.delete, color: Colors.red),
      tooltip:
          'Garbage Collection, take a snapshot and garbage collect the '
          'history until the snapshot version vector',
    );
  }
}

/// Slider bound to a [HistorySession] cursor.
class DocumentHistorySlider extends StatelessWidget {
  /// Creates a history slider for [historySession].
  const DocumentHistorySlider({super.key, required this.historySession});

  /// The session whose cursor the slider controls.
  final HistorySession historySession;

  @override
  Widget build(BuildContext context) {
    final max = historySession.length.toDouble();
    final value = historySession.cursor.toDouble();

    return Slider.adaptive(
      divisions: max.toInt(),
      value: value,
      min: 0,
      max: max,
      label: '${value.toInt()}/${max.toInt()}',
      onChanged: (value) => historySession.jump(value.toInt()),
      inactiveColor: Colors.grey,
    );
  }
}
