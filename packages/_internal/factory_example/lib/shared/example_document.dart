import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/client.dart';
import 'package:crdt_socket_sync/replica.dart';
import 'package:flutter/foundation.dart';

/// Base controller shared by every example document.
///
/// It is bound to the document of a [CRDTReplica] and provides the behaviors
/// common to all examples: time travel, garbage collection and the document
/// info getters.
///
/// It only notifies for its **own** state (time travel, GC): document
/// reactivity belongs to the `crdt_lf_flutter` widgets (`CrdtBuilder`,
/// `CrdtHandlerBuilder`, …) rooted in the `CrdtProvider` of each pane.
///
/// Subclasses provide their handler via [createHandler] and add their own
/// typed read/write API on top of [liveHandler] / [handler].
///
/// `H` is the handler type (e.g. `CRDTListHandler<...>`).
abstract class ExampleDocument<H extends Handler<dynamic>>
    extends ChangeNotifier {
  /// Creates the controller for the document of [replica].
  ExampleDocument(this.replica) {
    liveHandler = createHandler(document);
  }

  /// The replica this pane shows. Owned by the screen, not by this
  /// controller.
  final CRDTReplica replica;

  /// The live CRDT document of [replica].
  CRDTDocument get document => replica.document;

  /// The client that syncs [document]; `null` when the replica has none.
  CRDTSocketClient? get client => replica.client;

  /// The handler bound to the live [document].
  late final H liveHandler;

  /// The active time-travel session and its handler, if any.
  (HistorySession, H)? _history;

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
    _history?.$1.dispose();
    super.dispose();
  }
}
