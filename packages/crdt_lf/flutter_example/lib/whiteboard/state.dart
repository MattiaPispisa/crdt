import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/shared/document_state.dart';
import 'package:crdt_lf_flutter_example/shared/network.dart';
import 'package:crdt_lf_flutter_example/whiteboard/pointer_feedback.dart';
import 'package:crdt_lf_flutter_example/whiteboard/stroke.dart';
import 'package:flutter/material.dart';

class WhiteboardDocumentState extends DocumentState {
  WhiteboardDocumentState._(
    CRDTDocument document,
    this._handler,
    this._peerFeedbackHandler,
    this._peerPointerFeedbackHandler,
    Network network,
  ) : super(document, network);

  factory WhiteboardDocumentState.create(
    PeerId author, {
    required Network network,
  }) {
    final document = CRDTDocument(peerId: author);
    final handler = CRDTMapHandler<Stroke>(document, 'whiteboard');
    final peerFeedbackHandler = CRDTMapHandler<Stroke?>(
      document,
      'whiteboard_feedback',
    );
    final peerPointerFeedbackHandler = CRDTMapHandler<PointerFeedback?>(
      document,
      'whiteboard_pointer_feedback',
    );
    return WhiteboardDocumentState._(
      document,
      handler,
      peerFeedbackHandler,
      peerPointerFeedbackHandler,
      network,
    );
  }

  final CRDTMapHandler<Stroke> _handler;
  final CRDTMapHandler<Stroke?> _peerFeedbackHandler;
  final CRDTMapHandler<PointerFeedback?> _peerPointerFeedbackHandler;

  void setPointerFeedback(Offset offset, {Color color = Colors.black}) {
    final pointer = PointerFeedback(
      offset: offset,
      color: color,
      peerId: peerId,
    );

    _peerPointerFeedbackHandler.set(pointer.peerId.id, pointer);
    notifyListeners();
  }

  void removePointerFeedback() {
    _peerPointerFeedbackHandler.set(peerId.id, null);
    notifyListeners();
  }

  void createStrokeFeedback(
    Offset offset, {
    Color color = Colors.black,
    double strokeWidth = 5.0,
  }) {
    final strokeFeedback = Stroke(
      // Temporary ID
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      points: [offset],
      color: color,
      width: strokeWidth,
    );

    _peerFeedbackHandler.set(peerId.id, strokeFeedback);
    notifyListeners();
  }

  void updateStrokeFeedback(Offset offset) {
    final strokeFeedback = _peerFeedbackHandler.value[peerId.id];

    if (strokeFeedback == null) return;

    final updatedStrokeFeedback = strokeFeedback.copyWith(
      points: [...strokeFeedback.points, offset],
    );

    _peerFeedbackHandler.set(peerId.id, updatedStrokeFeedback);

    // Update also the pointer feedback
    final pointerFeedback = _peerPointerFeedbackHandler.value[peerId.id];
    if (pointerFeedback != null) {
      _peerPointerFeedbackHandler.set(
        peerId.id,
        pointerFeedback.copyWith(offset: offset),
      );
    }
    notifyListeners();
  }

  void addStroke() {
    final strokeFeedback = _peerFeedbackHandler.value[peerId.id];

    if (strokeFeedback == null) return;

    _handler.set(strokeFeedback.id, strokeFeedback);
    _peerFeedbackHandler.set(peerId.id, null);
    notifyListeners();
  }

  void removeStroke(StrokeId id) {
    _handler.delete(id);
    notifyListeners();
  }

  List<Stroke> get strokes => _handler.value.values.toList();

  List<Stroke> get strokesWithFeedbacks => [
    ..._handler.value.values,
    ..._peerFeedbackHandler.value.values.whereType<Stroke>(),
  ];

  List<PointerFeedback> get remotePointerFeedbacks =>
      _peerPointerFeedbackHandler.value.values
          .whereType<PointerFeedback>()
          .where((feedback) => feedback.peerId != peerId)
          .toList();
}
