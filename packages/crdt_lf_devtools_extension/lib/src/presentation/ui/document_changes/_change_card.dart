import 'package:crdt_lf/crdt_lf.dart' as crdt_lf;
import 'package:flutter/material.dart';

class CrdtLfChangeCard extends StatelessWidget {
  const CrdtLfChangeCard({super.key, required this.change});

  final crdt_lf.Change change;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          Text(change.payload.toString()),
        ],
      ),
    );
  }
}