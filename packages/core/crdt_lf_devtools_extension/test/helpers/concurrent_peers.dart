// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// A local document with the text changes `a` then `b`, and a remote one
/// with `r`, concurrent with them.
///
/// Once imported into `local`, `r` sorts between `a` and `b`: the clocks
/// start an hour ahead of the wall clock, so they only count, and the
/// remote peer id sorts first.
({CRDTDocument local, CRDTDocument remote, CRDTTextHandler text})
concurrentPeers({String? documentId}) {
  final ahead =
      DateTime.now().millisecondsSinceEpoch +
      const Duration(hours: 1).inMilliseconds;
  final local = CRDTDocument(
    documentId: documentId,
    peerId: PeerId.parse('ffffffff-ffff-4fff-bfff-ffffffffffff'),
    initialClock: HybridLogicalClock(l: ahead, c: 0),
  );
  final remote = CRDTDocument(
    peerId: PeerId.parse('00000000-0000-4000-8000-000000000000'),
    initialClock: HybridLogicalClock(l: ahead, c: 1),
  );
  // a = (ahead, 1) and b = (ahead, 2) here; r = (ahead, 2) there.
  final text =
      CRDTTextHandler(local, 'text')
        ..insert(0, 'a')
        ..insert(1, 'b');
  CRDTTextHandler(remote, 'text').insert(0, 'r');
  return (local: local, remote: remote, text: text);
}
