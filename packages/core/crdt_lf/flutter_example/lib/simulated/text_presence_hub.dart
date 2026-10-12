import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:factory_example/factory_example.dart';

/// In-memory [TextCursorPresence] bus between the simulated peers of one
/// document: what one peer publishes is what the other peers see.
class TextPresenceHub {
  final _views = <TextPresenceView>[];

  /// Registers the presence view of the peer [peerId], shown as [label]
  /// (and colored with `peerColorFor(peerId)`) on the other peers' panes.
  TextPresenceView register({required String peerId, required String label}) {
    final view = TextPresenceView._(this, peerId, label);
    _views.add(view);
    _fanOut();
    return view;
  }

  void _unregister(TextPresenceView view) {
    _views.remove(view);
    _fanOut();
  }

  void _fanOut() {
    for (final view in _views) {
      view._setRemote(_collect(view));
    }
  }

  Map<String, List<CrdtTextCursor>> _collect(TextPresenceView view) {
    final byHandler = <String, List<CrdtTextCursor>>{};
    for (final other in _views) {
      if (identical(other, view)) {
        continue;
      }
      for (final cursor in other._published.entries) {
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

  /// The anchors this peer published: text handler id → cursor.
  final _published = <String, CrdtTextCursor>{};

  @override
  void publish(String handlerId, FugueElementID? base, FugueElementID? extent) {
    if (base == null) {
      _published.remove(handlerId);
    } else {
      _published[handlerId] = CrdtTextCursor(
        id: _peerId,
        color: peerColorFor(_peerId),
        label: _label,
        base: base,
        extent: extent,
      );
    }
    _hub._fanOut();
  }

  void _setRemote(Map<String, List<CrdtTextCursor>> byHandler) {
    setRemoteCursors(byHandler);
  }

  @override
  void dispose() {
    _hub._unregister(this);
    super.dispose();
  }
}
