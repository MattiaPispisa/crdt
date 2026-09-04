import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:flutter/foundation.dart';

import 'package:greyhound_markdown_client/src/services/awareness/awareness_service.dart';

/// An open room, with everything the UI needs to draw it.
///
/// Built by [RoomHost] and handed out by `RoomBuilder`. Nothing here is the
/// caller's to dispose: the room owns all of it for as long as it is open.
class RoomSession {
  /// Creates a session over an already open room.
  const RoomSession({
    required this.roomId,
    required this.document,
    required this.text,
    required this.undo,
    required this.awareness,
    required this.status,
    required this.persistence,
  });

  /// The room this session is for.
  ///
  /// It is the document id **and** the relay room key: every client of the
  /// room uses the same one.
  final String roomId;

  /// The document, already holding what the last session left on this device.
  final CRDTDocument document;

  /// The body of the note, the one handler this room has.
  final CRDTFugueTextHandler text;

  /// The undo history of [text].
  ///
  /// It belongs to the room rather than to a pane, so it outlives the layout
  /// switches that take the editor out of the tree.
  final CRDTUndoManager undo;

  /// The remote cursors and who is in the room.
  final AwarenessService awareness;

  /// Whether the relay is reachable right now.
  final ValueListenable<ConnectionStatus> status;

  /// What writes the document down as it changes.
  ///
  /// `null` on a device that could not read its storage: the room still works,
  /// it just starts empty and keeps nothing for the next launch. Call
  /// [CRDTDocumentPersistence.compact] on it to stop the log from growing.
  final CRDTDocumentPersistence? persistence;
}
