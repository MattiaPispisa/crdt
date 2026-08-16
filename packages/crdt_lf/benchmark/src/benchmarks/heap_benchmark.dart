import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';

const _kElementCounts = [10000, 100000];

/// Prints the process RSS retained by a Fugue text document holding
/// [elements] runes.
///
/// `ProcessInfo.currentRss` is a whole-process sample, not a heap profile —
/// it is noisy and only useful as a rough, directional number. It is not
/// the live-heap snapshot a VM service session would give, but that needs a
/// running VM service, which this benchmark runner does not start.
void _report(int elements) {
  final before = ProcessInfo.currentRss;

  final doc = CRDTDocument(peerId: PeerId.generate());
  final text = CRDTFugueTextHandler(doc, 'text');
  doc.runInTransaction(() {
    text.insert(0, 'a' * elements);
  });
  // Materialize the value once, the same way a reader would before the
  // document is left alone.
  text.value;

  final after = ProcessInfo.currentRss;

  // ignore: avoid_print benchmark results
  print(
    'Fugue text retained RSS for $elements elements(Size): '
    '${after - before} bytes (before: $before, after: $after)',
  );
}

void main() {
  for (final elements in _kElementCounts) {
    _report(elements);
  }
}
