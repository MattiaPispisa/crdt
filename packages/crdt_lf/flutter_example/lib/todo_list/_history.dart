import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '_state.dart';

class ToDocumentHistoryViewButton extends StatelessWidget {
  const ToDocumentHistoryViewButton({super.key, required this.state});

  final DocumentState state;

  @override
  Widget build(BuildContext context) {
    final canTimeTravel = state.canTimeTravel();

    return IconButton(
      tooltip:
          canTimeTravel
              ? 'Time travel to the document history'
              : 'No changes to time travel to',
      icon: const Icon(Icons.history),
      onPressed:
          canTimeTravel
              ? () => context.read<DocumentState>().timeTravel()
              : null,
    );
  }
}

class BackToLiveButton extends StatelessWidget {
  const BackToLiveButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Back to live document',
      icon: const Icon(Icons.live_tv),
      onPressed: () => context.read<DocumentState>().backToLive(),
    );
  }
}

class DocumentHistorySlider extends StatelessWidget {
  const DocumentHistorySlider({super.key, required this.historySession});

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
