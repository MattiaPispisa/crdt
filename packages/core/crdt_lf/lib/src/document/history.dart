part of 'document.dart';

class _CRDTStaticProxyDocument extends BaseCRDTDocument {
  _CRDTStaticProxyDocument({
    required String documentId,
    required HybridLogicalClock hlc,
    required PeerId peerId,
    required List<Change> frozenChanges,
    required List<Set<OperationId>> historyVersions,
    required int visibleCount,
    required Snapshot? lastSnapshot,
    required Map<String, Handler<dynamic>> handlers,
  })  : _documentId = documentId,
        _hlc = hlc,
        _peerId = peerId,
        _frozenChanges = frozenChanges,
        _historyVersions = historyVersions,
        _visibleCount = visibleCount,
        _lastSnapshot = lastSnapshot,
        _handlers = handlers;

  final String _documentId;

  final HybridLogicalClock _hlc;

  final PeerId _peerId;

  final List<Change> _frozenChanges;

  final List<Set<OperationId>> _historyVersions;

  int _visibleCount;

  @override
  String get documentId => _documentId;

  @override
  HybridLogicalClock get hlc => _hlc;

  @override
  PeerId get peerId => _peerId;

  @override
  final Snapshot? _lastSnapshot;

  @override
  final Map<String, Handler<dynamic>> _handlers;

  @override
  void registerOperation(Operation operation) {
    throw const ReadOnlyDocumentException('registerOperation');
  }

  @override
  void prepareMutation() {
    throw const ReadOnlyDocumentException('prepareMutation');
  }

  @override
  Set<OperationId> get version {
    if (_visibleCount == 0) {
      return {};
    }
    return _historyVersions[_visibleCount - 1];
  }

  @override
  List<Change> exportChanges({
    Set<OperationId>? from,
    VersionVector? fromVersionVector,
  }) {
    var changes = _frozenChanges.sublist(0, _visibleCount);

    if (fromVersionVector != null && _lastSnapshot != null) {
      changes = changes.newerThan(_lastSnapshot!.versionVector).toList();
    }

    return changes;
  }

  @override
  List<Change> changesForHandler(
    String handlerId, {
    VersionVector? fromVersionVector,
  }) {
    final result = <Change>[];
    for (final change in exportChanges(fromVersionVector: fromVersionVector)) {
      try {
        final env = OperationEnvelopeCodec.decode(change.payloadBytes());
        if (env.handlerId == handlerId) {
          result.add(change);
        }
      } catch (_) {
        // Ignore changes whose envelope cannot be decoded.
      }
    }
    return result;
  }

  @override
  int changeCountForHandler(String handlerId) {
    return changesForHandler(handlerId).length;
  }

  // The frozen view never imports snapshots, so the visible change count
  // (which follows the time-travel cursor) is a complete revision signal.
  @override
  int revisionForHandler(String handlerId) => changeCountForHandler(handlerId);
}

/// {@template history_session}
/// An interactive controller for navigating the history of a [CRDTDocument].
///
/// A [HistorySession] creates a frozen, immutable view of a [CRDTDocument]
/// as the moment of instantiation. It allows "Time tavel" functionality by
/// moving a temporal cursor back and forth through the [Change]s.
///
/// ```dart
/// final document = CRDTDocument();
/// final listHandler = CRDTListHandler<String>(document, 'list');
/// listHandler
///   ..insert(0, 'Hello')
///   ..insert(1, 'World')
///   ..insert(2, 'Dart');
///
/// final historySession = document.toTimeTravel();
/// final viewListHandler = historySession.getHandler(
///   (doc) => CRDTListHandler<String>(doc, 'list'),
/// );
///
/// print(viewListHandler.value); // ['Hello', 'World', 'Dart']
///
/// historySession.previous();
/// print(viewListHandler.value); // ['Hello', 'World']
///
/// historySession.next();
/// print(viewListHandler.value); // ['Hello', 'World', 'Dart']
/// ```
/// {@endtemplate}
class HistorySession {
  HistorySession._({
    required int cursor,
    required _CRDTStaticProxyDocument document,
    required this.length,
  })  : _document = document,
        _cursor = cursor,
        _cursorController = StreamController<int>.broadcast();

  factory HistorySession._fromLiveDocument(
    BaseCRDTDocument document,
  ) {
    final changes = document.exportChanges().sorted();

    final historyVersions = <Set<OperationId>>[];
    final tempFrontiers = Frontiers();

    for (final change in changes) {
      tempFrontiers.update(
        newOperationId: change.id,
        oldDependencies: change.deps,
      );

      historyVersions.add(tempFrontiers.get());
    }

    final cursor = changes.length;

    final proxy = _CRDTStaticProxyDocument(
      documentId: document.documentId,
      hlc: document.hlc,
      peerId: document.peerId,
      frozenChanges: changes,
      historyVersions: historyVersions,
      visibleCount: cursor,
      lastSnapshot: document._lastSnapshot,
      handlers: {},
    );
    // Carry over the factories so nested handlers resolved through the
    // read-only session can be reconstructed against the historical changes.
    proxy._factories.addAll(document._factories);

    return HistorySession._(
      cursor: cursor,
      length: cursor,
      document: proxy,
    );
  }

  final _CRDTStaticProxyDocument _document;
  int _cursor;
  final StreamController<int> _cursorController;

  /// The total number of changes available in this history session.
  final int length;

  /// The stream of cursor position updates.
  ///
  /// Emits the new cursor index whenever
  /// [next], [previous], or [jump] is called.
  Stream<int> get cursorStream => _cursorController.stream;

  /// The current position of the temporal cursor.
  ///
  /// Represents the number of changes currently applied to the view.
  /// - 0: Initial state (snapshot only).
  /// - [length]: The full state at the time the session was created.
  int get cursor => _cursor;

  /// Whether the cursor can move forward (Redo).
  bool get canNext => _cursor < length;

  /// Whether the cursor can move backward (Undo).
  bool get canPrevious => _cursor > 0;

  /// Factory method to instantiate a CRDT Handler linked
  /// to this history session.
  ///
  /// [Handler]s bound to the history session can only view their states,
  /// on write operations (example [BaseCRDTDocument.registerOperation]) a
  /// [ReadOnlyDocumentException] is thrown
  H getHandler<H extends Handler<T>, T>(
    H Function(BaseCRDTDocument document) factory,
  ) {
    return factory(_document);
  }

  /// Advances the cursor by one step.
  ///
  /// Does nothing if [canNext] is false.
  void next() => jump(_cursor + 1);

  /// Moves the cursor back by one step.
  ///
  /// Does nothing if [canPrevious] if false.
  void previous() => jump(_cursor - 1);

  /// Jumps immediately to a specific point in history.
  ///
  /// [cursor] must be between 0 and [length] (inclusive).
  /// Does nothing if cursor remains the same.
  void jump(int cursor) {
    if (cursor < 0 || cursor > length) {
      return;
    }
    if (cursor == _cursor) {
      return;
    }

    _cursor = cursor;
    _document._visibleCount = _cursor;
    _cursorController.add(_cursor);
  }

  /// Releases resources used by this session.
  void dispose() {
    _cursorController.close();
    _document.dispose();
  }
}
