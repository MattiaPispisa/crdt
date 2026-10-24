// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// The hybrid logical clock of one peer, and the ids it mints.
///
/// Every id it mints is strictly newer than the ids it minted before and than
/// every time passed to [receive] or [advancePast].
class DocumentClock {
  /// Creates the clock of [peerId], starting at [initial]; at zero when it is
  /// `null`.
  DocumentClock(this.peerId, {HybridLogicalClock? initial})
      : _clock = initial ?? HybridLogicalClock.initialize();

  /// The peer whose ids this clock mints.
  final PeerId peerId;

  final HybridLogicalClock _clock;

  /// A copy of the current time.
  HybridLogicalClock get now => _clock.copy();

  /// Moves the clock forward, at [physicalTime] when it is set and at the
  /// wall-clock time otherwise.
  void tick({int? physicalTime}) {
    _clock.localEvent(physicalTime ?? DateTime.now().millisecondsSinceEpoch);
  }

  /// Ticks, and returns the id of a new operation at the new time.
  OperationId mint({int? physicalTime}) {
    tick(physicalTime: physicalTime);
    return OperationId(peerId, _clock.copy());
  }

  /// Moves the clock past [hlc], the time of a change this peer received.
  void receive(HybridLogicalClock hlc) {
    _clock.receiveEvent(DateTime.now().millisecondsSinceEpoch, hlc);
  }

  /// Moves the clock past every entry of [versionVector].
  void advancePast(VersionVector versionVector) {
    final physicalTime = DateTime.now().millisecondsSinceEpoch;
    for (final entry in versionVector.entries) {
      _clock.receiveEvent(physicalTime, entry.value);
    }
  }
}
