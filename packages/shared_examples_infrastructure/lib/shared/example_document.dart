import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/foundation.dart';

/// Base controller shared by every example document.
///
/// It is bound to an **already-synced** [CRDTDocument] (whatever transport
/// produced it — a simulated in-memory network or a real socket client) and
/// provides the behaviors common to all examples: time travel, garbage
/// collection and the document info getters. It rebuilds on [CRDTDocument
/// .updates].
///
/// The transport wiring and the document lifecycle live in the injected
/// sync session; this controller therefore **does not own and never disposes**
/// [document].
///
/// Subclasses provide their handler via [createHandler] and add their own
/// typed read/write API on top of [liveHandler] / [handler].
///
/// `H` is the handler type (e.g. `CRDTListHandler<...>`).
abstract class ExampleDocument<H extends Handler<dynamic>>
    extends ChangeNotifier {
  /// Creates the controller for an already-synced [document].
  ExampleDocument(this.document) {
    liveHandler = createHandler(document);
    _docChanges = document.updates.listen((_) => notifyListeners());
  }

  /// The live CRDT document. Owned by the transport session, not by this
  /// controller.
  final CRDTDocument document;

  /// The handler bound to the live [document].
  late final H liveHandler;

  /// The active time-travel session and its handler, if any.
  (HistorySession, H)? _history;

  StreamSubscription<void>? _docChanges;

  /// Creates the handler bound to [doc].
  ///
  /// Used both for the live document and for time-travel sessions, so it must
  /// only depend on `doc` (and constants), not on instance state.
  H createHandler(BaseCRDTDocument doc);

  /// The handler to read the current value from: the time-travel handler while
  /// traveling, otherwise the live handler. Local edits should always target
  /// [liveHandler].
  H get handler => _history?.$2 ?? liveHandler;

  // --- Time travel ---

  /// Whether there is any history to time travel into.
  bool canTimeTravel() => document.exportChanges().isNotEmpty;

  /// Whether a time-travel session is currently active.
  bool get isTimeTraveling => _history != null;

  /// The active time-travel session, or `null`.
  HistorySession? get historySession => _history?.$1;

  /// Opens a time-travel session over the document history.
  void timeTravel() {
    final session = document.toTimeTravel();
    final handler = session.getHandler(createHandler);
    session.cursorStream.listen((_) => notifyListeners());
    _history = (session, handler);
    notifyListeners();
  }

  /// Closes the time-travel session and returns to the live document.
  void backToLive() {
    _history?.$1.dispose();
    _history = null;
    notifyListeners();
  }

  // --- Garbage collection ---

  /// Takes a snapshot and prunes the history up to its version vector.
  void garbageCollection() {
    final snapshot = document.takeSnapshot(pruneHistory: false);
    document.garbageCollect(snapshot.versionVector);
    notifyListeners();
  }

  // --- Info ---

  /// The peer id of this document.
  PeerId get author => document.peerId;

  /// The number of changes in the document.
  int get changesCount => document.exportChanges().length;

  @override
  void dispose() {
    _docChanges?.cancel();
    _history?.$1.dispose();
    // NOTE: `document` is owned by the sync session, not disposed here.
    super.dispose();
  }
}
