import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:greyhound_markdown_client/src/application/application.dart';
import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/services/awareness/awareness_service.dart';
import 'package:greyhound_markdown_client/src/services/room/room_session.dart';

/// Opens a room and keeps it alive for as long as the [State] using it is in
/// the tree.
///
/// Everything a room is made of, in the order it has to be built: the stored
/// identity, the document restored from this device, the undo history, the
/// awareness service, the relay client. [room] is `null` until all of it is
/// ready, and disposing the state closes all of it.
///
/// `RoomBuilder` is this mixin as a widget, and is what a screen should use.
/// Mix it in directly only to own a room somewhere a builder cannot go.
///
/// A state that mixes this in must give a [roomId] and must not open the
/// document itself.
mixin RoomHost<T extends StatefulWidget> on State<T> {
  /// The room to open.
  String get roomId;

  RoomSession? _room;
  WebSocketRelayClient? _sync;
  ValueNotifier<ConnectionStatus>? _status;
  StreamSubscription<ConnectionStatus>? _statusSubscription;
  bool _opening = false;
  bool _disposed = false;

  /// The open room, or `null` while the local copy is still being read.
  ///
  /// Showing an editor before this is set would let someone type into a
  /// document that is about to be replaced.
  RoomSession? get room => _room;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opening) {
      return;
    }
    _opening = true;
    unawaited(_restoreThenConnect(context.read<UserSettingsCubit>().state));
  }

  /// Brings back what the last session left on this device, then goes online.
  ///
  /// In that order on purpose: offline, or on a relay that has forgotten the
  /// room, the local copy is all there is. Connecting first would show an
  /// empty page for as long as the handshake takes.
  Future<void> _restoreThenConnect(UserSettingsState profile) async {
    final opened = await _openDocument();

    // [dispose] can have run while the storage was being read. It found
    // nothing built yet and had nothing to close, so this closes it here.
    if (_disposed) {
      unawaited(opened.persistence?.dispose());
      opened.document.dispose();
      return;
    }

    // Nothing below suspends, so the teardown cannot cut in again.
    final document = opened.document;
    final text = CRDTFugueTextHandler(document, kHandlerId);
    final awareness = AwarenessService(
      name: profile.displayName,
      color: profile.color,
    );
    final sync = WebSocketRelayClient(
      url: roomUrl(kServerUrl, roomId),
      document: document,
      author: document.peerId,
      plugins: [awareness.plugin],
    );
    final status = ValueNotifier(sync.connectionStatusValue);

    _sync = sync;
    _status = status;
    _statusSubscription = sync.connectionStatus.listen(
      (value) => _status?.value = value,
    );

    setState(() {
      _room = RoomSession(
        roomId: roomId,
        document: document,
        text: text,
        undo: CRDTUndoManager(document)..track(text),
        awareness: awareness,
        status: status,
        persistence: opened.persistence,
      );
    });

    // Only now: the restored document is what the relay is caught up against,
    // so anything written offline goes out with the next welcome.
    sync.connect();
  }

  /// The document as this device last left it, and what keeps writing it down.
  ///
  /// A device that cannot read its storage still edits the room. It starts
  /// empty, fills up from the relay, and writes under a new identity — which
  /// is what happened on every launch before there was a local copy. The
  /// `persistence` is `null` there, and nothing is kept for the next launch.
  Future<({CRDTDocument document, CRDTDocumentPersistence? persistence})>
      _openDocument() async {
    try {
      final backend = await CRDTHive.open();
      // The backend keeps the identity too, so the device writes under the
      // same author on every launch. A new one per launch would grow the
      // room's version vector by an entry that never leaves — carried inside
      // every snapshot from then on.
      final opened = await backend.openDocument(
        roomId,
        onError: reportRoomError,
      );
      return (document: opened.document, persistence: opened.persistence);
    } catch (error, stackTrace) {
      reportRoomError(error, stackTrace);
      return (
        document: CRDTDocument(documentId: roomId),
        persistence: null,
      );
    }
  }

  /// Reports a failure of the local copy, which never stops the room.
  ///
  /// Override it to show the user something; the default hands it to
  /// [FlutterError.reportError].
  @protected
  void reportRoomError(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'greyhound_markdown',
        context: ErrorDescription('storing room $roomId'),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _statusSubscription?.cancel();
    // Flushes whatever is still waiting to be written.
    unawaited(_room?.persistence?.dispose());
    // Disposes the awareness plugin too.
    _sync?.dispose();
    _room?.awareness.dispose();
    _status?.dispose();
    _room?.undo.dispose();
    _room?.document.dispose();
    super.dispose();
  }
}
