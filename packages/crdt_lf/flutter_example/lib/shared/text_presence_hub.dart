import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:shared_examples_infrastructure/shared_examples_infrastructure.dart';

/// In-memory [TextCursorPresence] bus between the simulated peers of one
/// example screen: what one peer publishes is what the other peers see.
///
/// The real-transport analogue is the awareness plugin of the socket
/// example — here presence just crosses the two panes of the same window.
class TextPresenceHub {
  final _views = <TextPresenceView>[];

  /// The published anchors: peer id → text handler id → cursor.
  final _cursors = <String, Map<String, CrdtTextCursor>>{};

  /// Registers the presence view of the peer [peerId], shown as [label]
  /// (and colored with `peerColorFor(peerId)`) on the other peers' panes.
  TextPresenceView register({required String peerId, required String label}) {
    final view = TextPresenceView._(this, peerId, label);
    _views.add(view);
    return view;
  }

  void _publish(
    TextPresenceView view,
    String handlerId,
    FugueElementID? base,
    FugueElementID? extent,
  ) {
    final byHandler = _cursors.putIfAbsent(view._peerId, () => {});
    if (base == null) {
      byHandler.remove(handlerId);
    } else {
      byHandler[handlerId] = CrdtTextCursor(
        id: view._peerId,
        color: peerColorFor(view._peerId),
        label: view._label,
        base: base,
        extent: extent,
      );
    }
    // Fan out to every other peer's view.
    for (final other in _views) {
      if (!identical(other, view)) {
        other._setRemote(_collect(other));
      }
    }
  }

  Map<String, List<CrdtTextCursor>> _collect(TextPresenceView view) {
    final byHandler = <String, List<CrdtTextCursor>>{};
    for (final entry in _cursors.entries) {
      if (entry.key == view._peerId) {
        continue;
      }
      for (final cursor in entry.value.entries) {
        byHandler.putIfAbsent(cursor.key, () => []).add(cursor.value);
      }
    }
    return byHandler;
  }
}

/// One peer's view on a [TextPresenceHub].
class TextPresenceView extends BaseTextCursorPresence {
  TextPresenceView._(this._hub, this._peerId, this._label);

  final TextPresenceHub _hub;
  final String _peerId;
  final String _label;

  @override
  void publish(String handlerId, FugueElementID? base, FugueElementID? extent) {
    _hub._publish(this, handlerId, base, extent);
  }

  void _setRemote(Map<String, List<CrdtTextCursor>> byHandler) {
    setRemoteCursors(byHandler);
  }
}
