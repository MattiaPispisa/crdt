import 'package:crdt_lf/crdt_lf.dart';

/// Follows an identity through the new ones an undo had to give it.
///
/// A CRDT never brings a removed thing back to life: undoing a removal writes
/// the value again under a **new** identity — a new element id, a new tag.
/// An inverse built before that still names the old one and would miss it.
///
/// A handler that rebuilds identities works in two moments:
///
/// - while it builds an inverse that puts something back, it records what that
///   inverse restores with [noteRestores], and pairs it with the identities the
///   inverse really got with [commitRestores];
/// - while it makes an older inverse ready to be written
///   ([Handler.prepareInverse]), it follows the links: [expandChains] for an
///   operation that can address every identity of a chain, [latestOfAll] for
///   one that addresses a single thing.
///
/// The links form chains: a rebuilt identity can be removed and rebuilt again.
/// At most [maxRebuilt] of them are kept; past that the oldest is dropped, and
/// an undo reaching that far back leaves behind what it could not follow.
base mixin RebuiltIdentities<K extends Object> {
  /// How many links are remembered.
  static const int maxRebuilt = 8192;

  final Map<K, K> _rebuilt = <K, K>{};

  /// What an inverse puts back, until the identities it really gets are known.
  ///
  /// Weakly keyed: an entry dies with the operation it belongs to, so an
  /// inverse that never runs costs nothing.
  final Expando<List<K>> _pendingRestores = Expando<List<K>>();

  /// Whether anything has been rebuilt, so a caller can skip the work.
  bool get hasRebuiltIdentities => _rebuilt.isNotEmpty;

  /// Records that [was] now stands as [now].
  void noteRebuilt(K was, K now) {
    _rebuilt[was] = now;
    if (_rebuilt.length > maxRebuilt) {
      _rebuilt.remove(_rebuilt.keys.first);
    }
  }

  /// Records that [inverse] puts [was] back, under identities it does not have
  /// yet.
  ///
  /// Called while the inverse is built. [commitRestores] closes the pair once
  /// the new identities are known.
  void noteRestores(Object inverse, List<K> was) {
    _pendingRestores[inverse] = was;
  }

  /// Links what [inverse] restores to [now], the identities it really got.
  ///
  /// Pairs them by position, and does nothing for an [inverse] that
  /// [noteRestores] never named. Call it the moment the inverse is written: an
  /// identity minted with the operation is known as soon as it is built, one
  /// that **is** the operation's stamp only once the document mints it.
  void commitRestores(Object inverse, List<K> now) {
    final was = _pendingRestores[inverse];
    if (was == null) {
      return;
    }
    for (var i = 0; i < was.length && i < now.length; i += 1) {
      noteRebuilt(was[i], now[i]);
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

  /// [keys] plus everything that has stood for them, oldest first.
  ///
  /// `null` when no key of [keys] was ever rebuilt, so the caller keeps the
  /// operation it already has instead of building an equal one.
  List<K>? expandChains(Iterable<K> keys) {
    if (!hasRebuiltIdentities) {
      return null;
    }
    final expanded = <K>[];
    final seen = <K>{};
    var moved = false;
    for (final key in keys) {
      final chain = chainOf(key);
      if (chain.length > 1) {
        moved = true;
      }
      for (final link in chain) {
        if (seen.add(link)) {
          expanded.add(link);
        }
      }
    }
    return moved ? expanded : null;
  }

  /// [keys] each mapped to what stands for it now.
  ///
  /// `null` when none of them moved, for the reason [expandChains] returns one.
  List<K>? latestOfAll(Iterable<K> keys) {
    if (!hasRebuiltIdentities) {
      return null;
    }
    final latest = <K>[];
    var moved = false;
    for (final key in keys) {
      final now = latestOf(key);
      if (now != key) {
        moved = true;
      }
      latest.add(now);
    }
    return moved ? latest : null;
  }

  /// Forgets every link.
  void clearRebuiltIdentities() {
    _rebuilt.clear();
  }
}
