import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/shared/layout.dart';
import 'package:crdt_lf_flutter_example/shared/network.dart';
import 'package:crdt_lf_flutter_example/whiteboard/state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'painter.dart';

final author1 = PeerId.parse('79a716de-176e-4347-ba6e-1d9a2de02e17');
final author2 = PeerId.parse('79a716de-176e-4347-ba6e-1d9a2de02e18');

class Whiteboard extends StatelessWidget {
  const Whiteboard({super.key});

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      example: 'Whiteboard',
      leftBody: ChangeNotifierProvider<WhiteboardDocumentState>(
        create:
            (context) => WhiteboardDocumentState.create(
              author1,
              network: context.read<Network>(),
            ),
        child: WhiteboardDocument(author: author1, strokeColor: Colors.blue),
      ),
      rightBody: ChangeNotifierProvider<WhiteboardDocumentState>(
        create:
            (context) => WhiteboardDocumentState.create(
              author2,
              network: context.read<Network>(),
            ),
        child: WhiteboardDocument(author: author2, strokeColor: Colors.red),
      ),
    );
  }
}

class WhiteboardDocument extends StatelessWidget {
  const WhiteboardDocument({
    super.key,
    required this.author,
    required this.strokeColor,
  });

  final PeerId author;
  final Color strokeColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<WhiteboardDocumentState>(
        builder: (context, state, _) {
          return MouseRegion(
            onHover: (event) {
              state.setPointerFeedback(event.localPosition, color: strokeColor);
            },
            onExit: (event) {
              state.removePointerFeedback();
            },
            cursor: SystemMouseCursors.precise,
            child: GestureDetector(
              onPanStart: (details) {
                state.createStrokeFeedback(
                  details.localPosition,
                  color: strokeColor,
                );
              },
              onPanUpdate: (details) {
                state.updateStrokeFeedback(details.localPosition);
              },
              onPanEnd: (details) {
                state.updateStrokeFeedback(details.localPosition);
                state.addStroke();
              },
              child: Stack(
                children: [
                  CustomPaint(
                    painter: WhiteboardPainter(
                      strokes: state.strokesWithFeedbacks,
                    ),
                    // Added child to CustomPaint for hit testing
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black, width: 1.0),
                        color: Colors.transparent,
                      ),
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                  for (final pointer in state.remotePointerFeedbacks)
                    Positioned(
                      left: pointer.offset.dx - 4, // hack to center the icon
                      top: pointer.offset.dy - 20, // hack to center the icon
                      child: Icon(Icons.edit, color: pointer.color, size: 24.0),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
