import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/shared/document_state.dart';
import 'package:crdt_lf_flutter_example/shared/network.dart';
import 'package:crdt_lf_flutter_example/whiteboard/stroke.dart';
import 'package:flutter/material.dart';

class WhiteboardDocumentState extends DocumentState {
  WhiteboardDocumentState._(
    CRDTDocument document,
    this._handler,
    this._peerFeedbackHandler,
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
    return WhiteboardDocumentState._(
      document,
      handler,
      peerFeedbackHandler,
      network,
    );
  }

  final CRDTMapHandler<Stroke> _handler;
  final CRDTMapHandler<Stroke?> _peerFeedbackHandler;

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
    for (final strokeFeedback in _peerFeedbackHandler.value.values)
      if (strokeFeedback != null) strokeFeedback,
  ];
}
