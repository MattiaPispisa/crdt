import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/foundation.dart';

/// Ephemeral presence channel for in-field text cursors.
///
/// A sync session can expose one (see `ExampleSyncSession.textPresence`):
/// the shared `CrdtTextField` then publishes the local selection anchors and
/// draws the remote ones with `CrdtTextCursorsOverlay`. Cursor state never
/// enters the document history.
///
/// Implementations own the transport: the socket example maps it onto the
/// awareness plugin, the crdt_lf example onto an in-memory hub between the
/// simulated peers.
abstract class TextCursorPresence {
  /// Publishes the local selection anchors for the text handler [handlerId]
  /// (`null` anchors = no selection to show).
  void publish(String handlerId, FugueElementID? base, FugueElementID? extent);

  /// The remote collaborators' cursors on the text handler [handlerId]
  /// (never includes the local peer).
  ValueListenable<List<CrdtTextCursor>> cursorsOf(String handlerId);
}

/// [TextCursorPresence] base holding one listenable cursor list per handler
/// id; transports push consolidated remote state via [setRemoteCursors].
abstract class BaseTextCursorPresence implements TextCursorPresence {
  final _cursors = <String, ValueNotifier<List<CrdtTextCursor>>>{};

  @override
  ValueListenable<List<CrdtTextCursor>> cursorsOf(String handlerId) =>
      _notifier(handlerId);

  /// Replaces the remote cursors, grouped by text handler id; handlers
  /// absent from [byHandler] are cleared.
  @protected
  void setRemoteCursors(Map<String, List<CrdtTextCursor>> byHandler) {
    for (final id in {..._cursors.keys, ...byHandler.keys}) {
      final next = byHandler[id] ?? const <CrdtTextCursor>[];
      final notifier = _notifier(id);
      if (!listEquals(notifier.value, next)) {
        notifier.value = next;
      }
    }
  }

  /// Releases the per-handler notifiers.
  @mustCallSuper
  void dispose() {
    for (final notifier in _cursors.values) {
      notifier.dispose();
    }
    _cursors.clear();
  }

  ValueNotifier<List<CrdtTextCursor>> _notifier(String handlerId) {
    return _cursors.putIfAbsent(handlerId, () => ValueNotifier(const []));
  }
}

/// Encodes a selection anchor to a JSON-safe string (base64 of the
/// [FugueElementID] bytes), or `null` for a missing anchor.
String? encodeTextAnchor(FugueElementID? anchor) =>
    anchor == null ? null : base64Encode(anchor.toBytes());

/// Decodes an anchor produced by [encodeTextAnchor].
FugueElementID? decodeTextAnchor(String? encoded) =>
    encoded == null ? null : FugueElementID.fromBytes(base64Decode(encoded));
