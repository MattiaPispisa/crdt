import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/shared/network.dart';
import 'package:flutter/foundation.dart';

/// Base controller shared by every example document.
///
/// It owns a [CRDTDocument], wires it to the simulated [Network] (apply remote
/// changes, broadcast local ones, rebuild on updates) and provides the
/// behaviors common to all examples: time travel, garbage collection and the
/// document info getters.
///
/// Subclasses provide their handler via [createHandler] and add their own
/// typed read/write API on top of [liveHandler] / [handler].
///
/// `H` is the handler type (e.g. `CRDTListHandler<...>`).
abstract class ExampleDocument<H extends Handler<dynamic>>
    extends ChangeNotifier {
  /// Creates the controller for [author], wired to [network].
  ExampleDocument({required PeerId author, required Network network})
      : document = CRDTDocument(peerId: author),
        _network = network {
    liveHandler = createHandler(document);
    _networkChanges =
        _network.stream(document.peerId).listen(_applyNetworkChange);
    _localChanges = document.localChanges.listen(_network.sendChange);
    _docChanges = document.updates.listen((_) => notifyListeners());
  }

  /// The live CRDT document.
  final CRDTDocument document;

  final Network _network;

  /// The handler bound to the live [document].
  late final H liveHandler;

  /// The active time-travel session and its handler, if any.
  (HistorySession, H)? _history;

  StreamSubscription<Change>? _networkChanges;
  StreamSubscription<Change>? _localChanges;
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

  void _applyNetworkChange(Change change) {
    document.applyChange(change);
    notifyListeners();
  }

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
    _networkChanges?.cancel();
    _localChanges?.cancel();
    _docChanges?.cancel();
    _history?.$1.dispose();
    document.dispose();
    super.dispose();
  }
}
