import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:crdt_socket_sync/replica.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:en_logger/en_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:greyhound_markdown_client/src/application/application.dart';
import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/di/service_locator.dart';
import 'package:greyhound_markdown_client/src/logging/app_logger.dart';
import 'package:greyhound_markdown_client/src/services/awareness/'
    'awareness_service.dart';
import 'package:greyhound_markdown_client/src/services/room/room_session.dart';

/// Opens a room and keeps it alive for as long as the [State] using it is in
/// the tree.
///
/// A room is a [CRDTReplica] — the document restored from this device, and
/// the relay client on it — plus what the app builds on top: the undo
/// history and the awareness service. [room] is `null` until all of it is
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

  Future<CRDTReplica>? _replica;
  AwarenessService? _awareness;
  RoomSession? _room;
  ValueNotifier<ConnectionStatus>? _status;
  StreamSubscription<ConnectionStatus>? _statusSubscription;

  /// The open room, or `null` while the local copy is still being read.
  ///
  /// Showing an editor before this is set would let someone type into a
  /// document that is about to be replaced.
  RoomSession? get room => _room;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_replica != null) {
      return;
    }

    _roomLogger.info('Opening room $roomId');
    final settings = context.read<UserSettingsCubit>();
    final profile = settings.state;
    // Before the replica: the relay client carries its plugin.
    final awareness = _awareness = AwarenessService(
      name: profile.displayName,
      color: profile.color,
    );
    final replica = _replica = CRDTReplica.open(
      documentId: roomId,
      storage: CRDTHive.open,
      sync: (document) {
        final url = roomUrl(kServerUrl, roomId);
        _syncLogger.info('Relay client created for $url');
        return WebSocketRelayClient(
          url: url,
          document: document,
          author: document.peerId,
          plugins: [awareness.plugin],
        );
      },
      // A device that cannot read its storage still edits the room. It starts
      // empty, fills up from the relay, and keeps nothing for the next launch.
      onStorageError: reportRoomError,
    );
    unawaited(_showRoom(replica, settings, awareness));
  }

  Future<void> _showRoom(
    Future<CRDTReplica> opening,
    UserSettingsCubit settings,
    AwarenessService awareness,
  ) async {
    final replica = await opening;

    // After the first await on purpose: the cubit is read while the tree is
    // building, and emitting there would change state mid-build. The room is
    // recorded even when the teardown below wins, because the user did open
    // it.
    settings.recordRoomOpened(roomId);

    // `dispose` ran while the storage was being read, and closes the replica
    // on its own.
    if (!mounted) {
      return;
    }

    final sync = replica.client!;
    final status = _status = ValueNotifier(sync.connectionStatusValue);
    _statusSubscription = sync.connectionStatus.listen((value) {
      _logStatus(value);
      status.value = value;
    });

    final text = CRDTFugueTextHandler(replica.document, kHandlerId);
    _roomLogger.info(
      'Document of room $roomId opened: peer ${replica.document.peerId}, '
      '${text.value.length} characters, '
      '${replica.persistence == null ? 'no' : 'with'} local storage',
    );
    setState(() {
      _room = RoomSession(
        roomId: roomId,
        document: replica.document,
        text: text,
        undo: CRDTUndoManager(replica.document)..track(text),
        awareness: awareness,
        status: status,
        persistence: replica.persistence,
      );
    });
  }

  /// Reports a failure of the local copy, which never stops the room.
  ///
  /// Override it to show the user something; the default logs it and hands it
  /// to [FlutterError.reportError].
  @protected
  void reportRoomError(Object error, StackTrace stackTrace) {
    _roomLogger.error(
      'Local storage of room $roomId failed',
      error: error,
      stackTrace: stackTrace,
    );
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
    unawaited(_statusSubscription?.cancel());
    _status?.dispose();
    _room?.undo.dispose();
    _awareness?.dispose();
    // Not awaited: `dispose` cannot wait. The replica writes what is still
    // waiting before it lets the document go.
    _roomLogger.info('Closing room $roomId');
    unawaited(_replica?.then((replica) => replica.close()));
    super.dispose();
  }

  EnLogger get _roomLogger => loggerFor(LogScope.room);

  EnLogger get _syncLogger => loggerFor(LogScope.sync);

  void _logStatus(ConnectionStatus status) {
    final message = 'Room $roomId: ${status.name}';
    switch (status) {
      case ConnectionStatus.connected:
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
        _syncLogger.info(message);
      case ConnectionStatus.disconnected:
      case ConnectionStatus.error:
      case ConnectionStatus.unsupported:
        _syncLogger.warning(message);
    }
  }
}
