import 'package:flutter/material.dart';

import '_state.dart';

class DocumentInfo extends StatelessWidget {
  const DocumentInfo({super.key, required this.state});

  final DocumentState state;

  String _getDocumentInfo() {
    final result = StringBuffer('Document Info\n'.toUpperCase());
    result.writeln('Peer ID: ${state.author}');
    result.writeln('Changes Count: ${state.changesCount}');

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
    return Padding(
      padding: const EdgeInsets.only(left: 24.0, bottom: 24.0),
      child: Tooltip(message: _getDocumentInfo(), child: Icon(Icons.info)),
    );
  }
}
