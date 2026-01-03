import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '_state.dart';

class GarbageCollectionButton extends StatelessWidget {
  const GarbageCollectionButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        context.read<DocumentState>().garbageCollection();
      },
      icon: const Icon(Icons.delete, color: Colors.red),
      tooltip:
          'Garbage Collection, take a snapshot and garbage collect the history until the snapshot version vector',
    );
  }
}
