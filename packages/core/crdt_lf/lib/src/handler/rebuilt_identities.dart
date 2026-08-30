import 'package:crdt_lf/crdt_lf.dart';

/// Follows an identity through the new ones an undo had to give it.
///
/// A CRDT never brings a removed thing back to life: undoing a removal writes
/// the value again under a **new** identity — a new element id, a new tag.
/// An inverse built before that still names the old one and would miss it.
///
/// A handler that rebuilds identities records each step with [noteRebuilt] and
/// reads them back in [Handler.prepareInverse], through [latestOf] for an
/// operation that addresses one thing, or [chainOf] for one that can address
/// them all.
///
/// The links form chains: a rebuilt identity can be removed and rebuilt again.
/// At most [maxRebuilt] of them are kept; past that the oldest is dropped, and
/// an undo reaching that far back leaves behind what it could not follow.
base mixin RebuiltIdentities<K extends Object> {
  /// How many links are remembered.
  static const int maxRebuilt = 8192;

  final Map<K, K> _rebuilt = <K, K>{};

  /// Whether anything has been rebuilt, so a caller can skip the work.
  bool get hasRebuiltIdentities => _rebuilt.isNotEmpty;

  /// Records that [was] now stands as [now].
  void noteRebuilt(K was, K now) {
    _rebuilt[was] = now;
    if (_rebuilt.length > maxRebuilt) {
      _rebuilt.remove(_rebuilt.keys.first);
    }
  }

  /// What stands for [key] now: the last link of its chain, or [key] itself.
  K latestOf(K key) {
    var current = key;
    // A link always points at a freshly minted identity, so a cycle cannot
    // happen — but a corrupt map must not hang the caller.
    for (var hops = 0; hops < maxRebuilt; hops++) {
      final next = _rebuilt[current];
      if (next == null) {
        return current;
      }
      current = next;
    }
    return current;
  }

  /// [key] followed by everything that has stood for it, oldest first.
  List<K> chainOf(K key) {
    final chain = <K>[key];
    var current = key;
    for (var hops = 0; hops < maxRebuilt; hops++) {
      final next = _rebuilt[current];
      if (next == null) {
        break;
      }
      chain.add(next);
      current = next;
    }
    return chain;
  }

  /// Forgets every link.
  void clearRebuiltIdentities() {
    _rebuilt.clear();
  }
}
