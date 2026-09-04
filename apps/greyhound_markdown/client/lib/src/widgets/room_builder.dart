import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';

import 'package:greyhound_markdown_client/src/services/room/room_host.dart';
import 'package:greyhound_markdown_client/src/services/room/room_session.dart';

/// Opens the room named by [roomId] and builds the UI with it.
///
/// It owns the whole room for as long as it is in the tree — the document, its
/// undo history, the awareness service, the relay client — and hands them out
/// as a [RoomSession]. A screen under it gets all of that ready to use and
/// closes none of it.
///
/// The document is also put in the tree with `CrdtProvider`, so anything below
/// reaches it without being handed it.
///
/// ```dart
/// RoomBuilder(
///   roomId: roomId,
///   builder: (context, room) => Scaffold(
///     body: EditorPane(awareness: room.awareness, undo: room.undo),
///   ),
/// )
/// ```
class RoomBuilder extends StatefulWidget {
  /// Creates a builder over the room named by [roomId].
  const RoomBuilder({
    required this.roomId,
    required this.builder,
    this.loading,
    super.key,
  });

  /// The room to open. It is the document id and the relay room key.
  final String roomId;

  /// Builds the UI of an open room.
  final Widget Function(BuildContext context, RoomSession room) builder;

  /// What to show while the local copy is being read.
  ///
  /// A spinner by default. Give one that keeps the frame of the screen — an
  /// app bar, say — so the page does not jump when the room arrives.
  final WidgetBuilder? loading;

  @override
  State<RoomBuilder> createState() => _RoomBuilderState();
}

class _RoomBuilderState extends State<RoomBuilder> with RoomHost<RoomBuilder> {
  @override
  String get roomId => widget.roomId;

  @override
  Widget build(BuildContext context) {
    final room = this.room;
    if (room == null) {
      return widget.loading?.call(context) ??
          const Center(child: CircularProgressIndicator());
    }

    return CrdtProvider.value(
      value: room.document,
      child: widget.builder(context, room),
    );
  }
}
