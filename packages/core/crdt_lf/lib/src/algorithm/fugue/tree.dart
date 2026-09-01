import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/run.dart';
import 'package:crdt_lf/src/algorithm/fugue/value_node.dart';
import 'package:crdt_lf/src/algorithm/sqrt_decomposition/sqrt_decomposition.dart';
import 'package:crdt_lf/src/utils/binary_search.dart';

/// Where an element sits: the run that holds it, and how far into it.
typedef _Spot<T> = ({FugueRun<T> run, int offset});

/// Implementation of the Fugue tree for collaborative text editing
///
/// ([The Art of the Fugue: Minimizing Interleaving in Collaborative Text
/// Editing](https://arxiv.org/abs/2305.00583))
///
/// ## Elements are grouped into runs
///
/// The tree holds one node per **run**, not per element: elements one peer
/// wrote with consecutive counters and that ended up adjacent share a single
/// [FugueRun].
/// Typing a paragraph costs one run, not one node per character.
///
/// Grouping is a **local choice of representation**. Two peers may cut their
/// runs in different places and still answer every query identically: [values],
/// [findNodeAtPosition], [findNextNode] and [liveIndexAfter] are defined on
/// elements, and nothing about a run reaches the wire.
class FugueTree<T> {
  FugueTree._();

  /// Initializes a new empty Fugue tree
  factory FugueTree.empty() => FugueTree<T>._();

  /// How many elements one run may hold.
  ///
  /// A cap, not a target. Higher means fewer runs and less memory, but a longer
  /// list to shift when a split lands in the middle of a peer's runs, and more
  /// values to copy when one is cut. 128 is a starting point to measure
  /// against, not a tuned value.
  static const int maxRunLength = 128;

  /// The runs of each peer, ordered by the counter they start at.
  ///
  /// A peer's counters only grow, so a brand new run always lands at the end;
  /// only a split inserts in the middle. Binary search over one peer's list is
  /// how an id becomes a run — Yjs's `StructStore.clients` and `findIndexSS`.
  final Map<PeerId, List<FugueRun<T>>> _runs = {};

  /// The children of the root, which stands for no element and so has no run.
  List<FugueElementID>? _rootLeftChildren;
  List<FugueElementID>? _rootRightChildren;

  /// Root node ID
  final FugueElementID _rootID = FugueElementID.nullID();

  /// The last-writer-wins stamp of the elements whose value has been
  /// overwritten in place by [update].
  final Map<FugueElementID, OperationId> _stamps = {};

  /// Positional index over the in-order sequence of **runs**, each carrying
  /// how many elements it holds and how many of them are live.
  ///
  /// Keyed by the run itself, not by its start id: going through the ids would
  /// put a binary search between the index and every run it visits, turning a
  /// full read from `O(n)` into `O(n log R)`.
  ///
  /// Answers position↔run and neighbour queries in `O(√R)` for `R` runs. The
  /// walk inside a run is the tree's job — the index does not know which of its
  /// elements are still there.
  final SqrtDecomposition<FugueRun<T>> _index =
      SqrtDecomposition<FugueRun<T>>();

  // --- Locating an element ---------------------------------------------

  /// The run holding [id] and the offset of [id] inside it, or `null` when this
  /// tree does not hold [id].
  ///
  /// `O(log R_p)` with `R_p` the number of runs of [id]'s peer.
  _Spot<T>? _spotOf(FugueElementID id) {
    if (id.isNull) {
      return null;
    }

    // Lookups arrive in runs of their own: linking an element resolves its
    // parent several times over, and a replay walks the sequence in order. One
    // slot of memory turns most of those into arithmetic.
    //
    // Nothing has to invalidate it. A run that was cut is still a run, and an
    // id that moved to the tail simply falls outside the length checked here.
    final cached = _lastSpotRun;
    if (cached != null && cached.startID.replicaID == id.replicaID) {
      final offset = id.counter! - cached.startCounter;
      if (offset >= 0 && offset < cached.length) {
        return (run: cached, offset: offset);
      }
    }

    final list = _runs[id.replicaID];
    if (list == null) {
      return null;
    }
    final counter = id.counter!;
    final index = list.lowerBoundBy<int>(counter, (run, c) {
      if (c < run.startCounter) return 1;
      if (c >= run.startCounter + run.length) return -1;
      return 0;
    });
    if (index == list.length) {
      return null;
    }
    final run = list[index];
    if (counter < run.startCounter ||
        counter >= run.startCounter + run.length) {
      return null;
    }
    _lastSpotRun = run;
    return (run: run, offset: counter - run.startCounter);
  }

  /// The run the last successful [_spotOf] landed in. See the note there.
  FugueRun<T>? _lastSpotRun;

  /// The run [startID] opens. [startID] must be a run start.
  FugueRun<T> _runAt(FugueElementID startID) => _spotOf(startID)!.run;

  /// Files [run] among its peer's runs, keeping them ordered by counter.
  void _register(FugueRun<T> run) {
    final list = _runs.putIfAbsent(
      run.startID.replicaID,
      () => <FugueRun<T>>[],
    );
    final low = list.lowerBoundBy(
      run.startCounter,
      (r, t) => r.startCounter.compareTo(t),
    );
    list.insert(low, run);
  }

  // --- Children of an element ------------------------------------------

  /// The runs hanging off [holder] on [side], by start id, in id order.
  ///
  /// A `null` [holder] is the root, which stands for no element and so has no
  /// run of its own.
  List<FugueElementID> _childrenOf(FugueRun<T>? holder, FugueSide side) {
    if (holder == null) {
      final children =
          side == FugueSide.left ? _rootLeftChildren : _rootRightChildren;
      return children ?? const <FugueElementID>[];
    }
    return side == FugueSide.left ? holder.leftChildren : holder.rightChildren;
  }

  /// Puts the run starting at [id] among [holder]'s children on [side], at
  /// [index].
  ///
  /// [holder] is the run whose edge element is the parent — the run
  /// [_normalizeForChild] hands back — or `null` for the root.
  void _insertChildOf(
    FugueRun<T>? holder,
    FugueSide side,
    int index,
    FugueElementID id,
  ) {
    if (holder == null) {
      if (side == FugueSide.left) {
        (_rootLeftChildren ??= <FugueElementID>[]).insert(index, id);
      } else {
        (_rootRightChildren ??= <FugueElementID>[]).insert(index, id);
      }
      return;
    }
    holder.insertChild(id, side: side, index: index);
  }

  // --- Reading ----------------------------------------------------------

  /// Returns all non-deleted values in the correct order
  ///
  /// Read out of [_index], which already holds the in-order sequence of runs:
  /// no tree walk, and stretches of tombstones are skipped a whole block at a
  /// time.
  List<T> values() {
    final result = <T>[];
    _index.forEachLiveRun((run, length, liveLength) {
      for (var offset = 0; offset < run.length; offset++) {
        if (!run.deletedAt(offset)) {
          result.add(run.valueAt(offset));
        }
      }
    });
    return result;
  }

  /// Returns all non-deleted nodes in the correct order
  List<FugueValueNode<T>> nodes() {
    final result = <FugueValueNode<T>>[];
    forEachLiveNode((id, value) {
      result.add(FugueValueNode<T>(id: id, value: value));
    });
    return result;
  }

  /// The number of non-deleted elements, in `O(1)`.
  int get liveLength => _index.liveLength;

  /// How many runs the elements are grouped into, in `O(1)`.
  ///
  /// A representation detail, and **not** a property of the document: two peers
  /// holding the same elements can report different numbers. It is here to be
  /// measured — it says how well the grouping is working — never to be compared
  /// between peers or written down.
  int get runCount => _index.runCount;

  /// Calls [action] on every non-deleted element, in sequence order.
  ///
  /// The streaming form of [nodes]: a caller that only reads each element once
  /// pays nothing for the list.
  void forEachLiveNode(void Function(FugueElementID id, T value) action) {
    _index.forEachLiveRun((run, length, liveLength) {
      for (var offset = 0; offset < run.length; offset++) {
        if (!run.deletedAt(offset)) {
          action(run.idAt(offset), run.valueAt(offset));
        }
      }
    });
  }

  /// Calls [action] on every element of the sequence, tombstones included, in
  /// sequence order. The root is not one of them.
  ///
  /// `deleted` tells the two apart; the value comes through either way. Use
  /// [forEachLiveNode] to skip the tombstones, which is cheaper: it skips a
  /// whole block of them at a time.
  void forEachNode(
    void Function(FugueElementID id, T value, {required bool deleted}) action,
  ) {
    _index.forEachRun((run, length, liveLength) {
      for (var offset = 0; offset < run.length; offset++) {
        action(
          run.idAt(offset),
          run.valueAt(offset),
          deleted: run.deletedAt(offset),
        );
      }
    });
  }

  /// Every element in sequence order, tombstones among them, read by following
  /// the parent and child links instead of [_index].
  ///
  /// [_index] is built to mirror this walk, so [forEachNode] and this method
  /// must always agree. Reading the order both ways is how a test tells them
  /// apart — that is the only reason this exists. It is `O(n)` and visits every
  /// run, so nothing on a hot path should call it.
  List<({FugueElementID id, bool deleted})> structuralSequence() {
    final result = <({FugueElementID id, bool deleted})>[];
    // The stack holds frames in reverse visiting order, so the top of the
    // stack is always what comes next.
    final stack = <_Frame<T>>[
      for (final id in _childrenOf(null, FugueSide.right).reversed)
        _Frame<T>.expand(id),
      for (final id in _childrenOf(null, FugueSide.left).reversed)
        _Frame<T>.expand(id),
    ];

    while (stack.isNotEmpty) {
      final frame = stack.removeLast();

      final run = frame.run;
      if (run != null) {
        for (var offset = 0; offset < run.length; offset++) {
          result.add((id: run.idAt(offset), deleted: run.deletedAt(offset)));
        }
        continue;
      }

      // A run's left children hang off its first element and its right
      // children off its last, so the whole run sits between the two.
      final subtree = _runAt(frame.id!);
      for (final id in subtree.rightChildren.reversed) {
        stack.add(_Frame<T>.expand(id));
      }
      stack.add(_Frame<T>.emit(subtree));
      for (final id in subtree.leftChildren.reversed) {
        stack.add(_Frame<T>.expand(id));
      }
    }

    return result;
  }

  /// The last-writer-wins stamps of the elements an [update] overwrote.
  ///
  /// A tombstone keeps its entry, because it keeps its value.
  Map<FugueElementID, OperationId> get stamps =>
      Map<FugueElementID, OperationId>.unmodifiable(_stamps);

  /// Finds the element at the specified [position], or a null id if [position]
  /// is negative or past the last live element.
  ///
  /// Backed by [_index]: `O(√R)` to land on the run, then a walk inside it.
  FugueElementID findNodeAtPosition(int position) {
    final hit = _index.liveAt(position);
    if (hit == null) {
      return FugueElementID.nullID();
    }
    final run = hit.key;
    return run.idAt(run.offsetOfLive(hit.liveOffset));
  }

  /// The ids of at most [count] live elements, starting at live [position].
  ///
  /// Shorter than [count] when the range runs off the end of the sequence, and
  /// empty when [position] is already past it. One walk for the whole range,
  /// against one `O(√R)` lookup per element in [count] calls to
  /// [findNodeAtPosition].
  List<FugueElementID> findNodesInRange(int position, int count) {
    final result = <FugueElementID>[];
    if (count <= 0) {
      return result;
    }
    _index.forEachRunFromLive(position, (run, length, live, liveOffset) {
      var toSkip = liveOffset;
      for (var offset = 0; offset < run.length; offset++) {
        if (run.deletedAt(offset)) {
          continue;
        }
        if (toSkip > 0) {
          toSkip--;
          continue;
        }
        result.add(run.idAt(offset));
        if (result.length == count) {
          return false;
        }
      }
      return true;
    });
    return result;
  }

  /// Whether [nodeID] is in the tree and still part of the sequence.
  ///
  /// `false` for an unknown id and for a tombstone.
  bool isLive(FugueElementID nodeID) {
    final spot = _spotOf(nodeID);
    return spot != null && !spot.run.deletedAt(spot.offset);
  }

  /// The value [nodeID] holds, tombstones included; `null` for an id this tree
  /// does not hold.
  ///
  /// `O(log R_p)` with `R_p` the number of runs of [nodeID]'s peer.
  T? valueOf(FugueElementID nodeID) {
    final spot = _spotOf(nodeID);
    if (spot == null) {
      return null;
    }
    return spot.run.valueAt(spot.offset);
  }

  /// The live index of a caret anchored immediately **after** [nodeID]: the
  /// number of live elements up to and including it — or strictly before it, if
  /// [nodeID] is a tombstone (the caret stays where the element used to be).
  ///
  /// Returns `null` for an id unknown to this tree. Backed by [_index]:
  /// `O(√R)`.
  int? liveIndexAfter(FugueElementID nodeID) {
    final spot = _spotOf(nodeID);
    if (spot == null) {
      return null;
    }
    final rank = _index.liveRankOfRunStart(spot.run);
    if (rank == -1) {
      return null;
    }
    final within = rank + spot.run.liveBefore(spot.offset);
    return spot.run.deletedAt(spot.offset) ? within : within + 1;
  }

  /// Finds the next element after [nodeID] in the traversal, tombstones
  /// included, or a null id when [nodeID] is the last of the sequence.
  ///
  /// A null [nodeID] means "before everything", so it resolves to the first
  /// element of the sequence. Callers use it to anchor an insertion at index
  /// `0`.
  FugueElementID findNextNode(FugueElementID nodeID) {
    // The root sits before every other element and is the only structural node
    // kept out of [_index], so its successor is the head of the sequence.
    if (nodeID == _rootID) {
      return _index.first()?.startID ?? FugueElementID.nullID();
    }

    final spot = _spotOf(nodeID);
    if (spot == null) {
      return FugueElementID.nullID();
    }

    // Inside a run the successor is the next element, in `O(1)`.
    if (spot.offset < spot.run.length - 1) {
      return spot.run.idAt(spot.offset + 1);
    }

    // guard for editing inside a document: a right child with no left children
    // of its own opens its subtree, so it is the successor.
    final rightChildren = spot.run.rightChildren;
    if (rightChildren.isNotEmpty) {
      final first = _runAt(rightChildren.first);
      if (first.leftChildren.isEmpty) {
        return first.startID;
      }
    }

    return _index.successorOf(spot.run)?.startID ?? FugueElementID.nullID();
  }

  // --- Writing ----------------------------------------------------------

  /// Seeds an empty tree with [nodes], in sequence order, plus their [stamps].
  /// [live] says which of them are still in the sequence, one flag per node;
  /// all of them when it is left out.
  ///
  /// Element for element this is what `iterableInsert(0, nodes)` builds — a
  /// right spine hanging off the root — but it cuts the runs in one pass, links
  /// them directly and builds the positional index with a single
  /// [SqrtDecomposition.bulkBuild]. That turns the seed from n insertions of
  /// `O(√n)` into `O(n)`.
  void bulkSeed(
    List<FugueValueNode<T>> nodes,
    Map<FugueElementID, OperationId> stamps, {
    List<bool>? live,
  }) {
    assert(_runs.isEmpty, 'bulkSeed expects an empty tree');
    assert(
      live == null || live.length == nodes.length,
      'bulkSeed expects one liveness flag per node',
    );
    if (nodes.isEmpty) {
      _stamps.addAll(stamps);
      return;
    }

    final keys = <FugueRun<T>>[];
    final lengths = <int>[];
    final liveLengths = <int>[];

    FugueRun<T>? holder;
    var parentID = _rootID;
    var start = 0;
    while (start < nodes.length) {
      final startID = nodes[start].id;
      var end = start + 1;
      while (end < nodes.length &&
          end - start < maxRunLength &&
          nodes[end].id.replicaID == startID.replicaID &&
          nodes[end].id.counter == startID.counter! + (end - start)) {
        end++;
      }

      final run = FugueRun<T>(
        startID: startID,
        parentID: parentID,
        side: FugueSide.right,
        values: [for (var i = start; i < end; i++) nodes[i].value],
        deleted: [
          for (var i = start; i < end; i++) live != null && !live[i],
        ],
      );
      _register(run);
      // A right spine: the parent is the run built one step earlier, so it has
      // no children yet and this one opens its list.
      _insertChildOf(holder, FugueSide.right, 0, startID);

      keys.add(run);
      lengths.add(run.length);
      liveLengths.add(run.liveCount);

      holder = run;
      parentID = run.lastID;
      start = end;
    }

    _index.bulkBuild(keys, lengths, liveLengths);
    _stamps.addAll(stamps);
  }

  /// Inserts a list of nodes into the tree at the specified index.
  ///
  /// Convenience for the local-edit path: derives `leftOrigin`/`rightOrigin`
  /// from [index] and delegates to [iterableInsertChain].
  void iterableInsert(
    int index,
    Iterable<FugueValueNode<T>> nodes,
  ) {
    if (nodes.isEmpty) {
      return;
    }

    final leftOrigin =
        index == 0 ? FugueElementID.nullID() : findNodeAtPosition(index - 1);
    final rightOrigin = findNextNode(leftOrigin);

    iterableInsertChain(
      leftOrigin: leftOrigin,
      rightOrigin: rightOrigin,
      nodes: nodes,
    );
  }

  /// Inserts a chain of nodes between [leftOrigin] and [rightOrigin].
  ///
  /// The first node is inserted with the given origins; each subsequent node
  /// is chained as a right child of the previously-inserted one, with the
  /// same [rightOrigin].
  ///
  /// The result is the same as inserting the nodes one by one at consecutive
  /// indexes, and the chain stays contiguous under concurrent insertions at
  /// the same position. A chain from one peer with consecutive counters — a
  /// paste, or a batch of keystrokes — collapses into as few runs as
  /// [maxRunLength] allows.
  void iterableInsertChain({
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
    required Iterable<FugueValueNode<T>> nodes,
  }) {
    if (nodes.isEmpty) {
      return;
    }

    var previousID = leftOrigin;
    for (final node in nodes) {
      insert(
        newID: node.id,
        value: node.value,
        leftOrigin: previousID,
        rightOrigin: rightOrigin,
      );
      previousID = node.id;
    }
  }

  /// Inserts a new element into the tree with [newID] and [value]
  ///
  /// [leftOrigin] is the element at position `index-1`
  ///
  /// [rightOrigin] the element after [leftOrigin] in traversal order
  ///
  /// If [leftOrigin] is an ancestor of [rightOrigin] the new element becomes a
  /// left child of [rightOrigin]; otherwise it becomes a right child of
  /// [leftOrigin]. When [leftOrigin] is unknown the element becomes a left
  /// child of [rightOrigin], and when neither origin is known it hangs off the
  /// root.
  void insert({
    required FugueElementID newID,
    required T value,
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
  }) {
    final left = _spotOf(leftOrigin);
    final right = _spotOf(rightOrigin);

    final FugueElementID parentID;
    final FugueSide side;
    // The parent's spot is carried along rather than looked up again: resolving
    // an id is a binary search over its peer's runs, and the linking below
    // would otherwise repeat it half a dozen times.
    final _Spot<T>? parentSpot;
    if (left != null && right != null) {
      if (_isAncestorOf(left, right)) {
        // Insert as left child of rightOrigin to maintain order
        parentID = rightOrigin;
        side = FugueSide.left;
        parentSpot = right;
      } else {
        parentID = leftOrigin;
        side = FugueSide.right;
        parentSpot = left;
      }
    } else if (left != null) {
      parentID = leftOrigin;
      side = FugueSide.right;
      parentSpot = left;
    } else if (right != null) {
      parentID = rightOrigin;
      side = FugueSide.left;
      parentSpot = right;
    } else if (leftOrigin.isNull) {
      // If leftOrigin is null, the new element hangs off the root's right side
      parentID = _rootID;
      side = FugueSide.right;
      parentSpot = null;
    } else {
      // If neither origin exists, insert at the beginning
      parentID = _rootID;
      side = FugueSide.left;
      parentSpot = null;
    }

    _addElement(newID, value, parentID, side, parentSpot);
  }

  /// Links a new element under [parentID] on [side], extending a run when it
  /// can and opening one when it cannot.
  void _addElement(
    FugueElementID newID,
    T value,
    FugueElementID parentID,
    FugueSide side,
    _Spot<T>? parentSpot,
  ) {
    // Element ids are unique by construction, so an id already in the tree
    // means the history is broken.
    if (_spotOf(newID) != null) {
      throw DuplicateNodeException('Node already exists: $newID');
    }

    if (_appendToRun(newID, value, parentSpot, side)) {
      return;
    }

    // Anything hanging off an inner element of a run breaks the chain, so the
    // run is cut first and [parentID] ends up on the edge it needs.
    final holder = _normalizeForChild(parentSpot, side);

    final run = FugueRun<T>(
      startID: newID,
      parentID: parentID,
      side: side,
      values: [value],
      deleted: [false],
    );
    _register(run);

    // Same-side siblings are kept sorted by id.
    final siblings = _childrenOf(holder, side);
    final position = _siblingInsertionPoint(siblings, newID);
    _insertChildOf(holder, side, position, newID);

    _indexInsert(run, position, holder);
  }

  /// Grows the run the parent sits in by one element, when the new element
  /// only continues it. Returns whether it did.
  ///
  /// The path sequential typing takes: a gesture at a time arrives as
  /// one-element operations with consecutive counters, which without this would
  /// never share a run.
  ///
  /// The rule is Yjs's `Item.mergeWith` minus its same-liveness condition,
  /// which a run does not need because it flags each element: same peer, next
  /// counter, hanging off the run's last element on the right, nothing else
  /// already there, and room under [maxRunLength].
  bool _appendToRun(
    FugueElementID newID,
    T value,
    _Spot<T>? parentSpot,
    FugueSide side,
  ) {
    if (side != FugueSide.right || parentSpot == null) {
      return false;
    }
    final spot = parentSpot;
    final run = spot.run;
    if (spot.offset != run.length - 1 ||
        run.length >= maxRunLength ||
        run.rightChildren.isNotEmpty ||
        run.startID.replicaID != newID.replicaID ||
        run.startCounter + run.length != newID.counter) {
      return false;
    }

    run.append(value);
    _index.setLengths(run, length: run.length, liveLength: run.liveCount);
    return true;
  }

  /// Cuts the run at [parentSpot] so that the parent sits where a child on
  /// [side] can hang off it: last element of its run for a right child, first
  /// for a left one.
  ///
  /// Only a run's first and last element may carry children. Splitting restores
  /// that and costs the sequence nothing: the halves keep the parent/child
  /// relation those elements already had.
  ///
  /// Returns the run the parent ends up in, the one that will carry the new
  /// child; `null` for the root, which has no run.
  FugueRun<T>? _normalizeForChild(_Spot<T>? parentSpot, FugueSide side) {
    if (parentSpot == null) {
      return null;
    }
    if (side == FugueSide.right) {
      if (parentSpot.offset < parentSpot.run.length - 1) {
        // The parent keeps its place and becomes the left half's last element.
        _splitRun(parentSpot.run, parentSpot.offset + 1);
      }
      return parentSpot.run;
    }
    if (parentSpot.offset > 0) {
      // The parent opens the tail, so the tail is the run that carries it.
      return _splitRun(parentSpot.run, parentSpot.offset);
    }
    return parentSpot.run;
  }

  /// Cuts [run] in two at [offset], leaving the sequence unchanged, and
  /// returns the new right half.
  FugueRun<T> _splitRun(FugueRun<T> run, int offset) {
    final tail = run.splitAt(offset);
    _register(tail);
    // The tail is now the only right child of the left half's last element,
    // which is the relation those two elements already had.
    run.insertChild(tail.startID, side: FugueSide.right, index: 0);

    _index
      ..setLengths(run, length: run.length, liveLength: run.liveCount)
      // In-order, the tail opens right where the left half stops.
      ..insertAfter(
        run,
        tail,
        length: tail.length,
        liveLength: tail.liveCount,
      );
    return tail;
  }

  /// Whether the element at [descendant] sits in the subtree rooted at the one
  /// at [ancestor].
  ///
  /// Answers the one question [insert] asks — is the left origin an ancestor of
  /// the right one — and leans on it: an element with no right child has no
  /// descendant that could follow it in the sequence.
  bool _isAncestorOf(_Spot<T> ancestor, _Spot<T> descendant) {
    // One run is a chain, so every element is an ancestor of the ones after it.
    if (identical(ancestor.run, descendant.run)) {
      return ancestor.offset < descendant.offset;
    }

    // An inner element's one right child is the next element of its own run,
    // and the descendant is in another run.
    final isLast = ancestor.offset == ancestor.run.length - 1;
    if (!isLast) {
      return false;
    }
    if (ancestor.run.rightChildren.isEmpty) {
      return false;
    }

    final ancestorID = ancestor.run.idAt(ancestor.offset);

    // Walk up the parents. Inside a run the parent chain is the run itself, so
    // one hop per run is enough.
    var run = descendant.run;
    while (true) {
      final parentID = run.parentID;
      if (parentID.isNull) {
        return false;
      }
      if (parentID == ancestorID) {
        return true;
      }
      final spot = _spotOf(parentID);
      if (spot == null) {
        return false;
      }
      if (identical(spot.run, ancestor.run)) {
        // The chain reached the ancestor's run: everything from [ancestor] on
        // is an ancestor of the element the walk landed on.
        return ancestor.offset <= spot.offset;
      }
      run = spot.run;
    }
  }

  /// Takes [nodeID] out of the sequence, keeping the element.
  ///
  /// The tombstone keeps its value, its place in its run, and the stamp of the
  /// update that last wrote it. Only its liveness goes, so the run stays whole.
  ///
  /// A deletion is monotone: it wins over every update, and nothing brings the
  /// element back. So there is no race to settle and no stamp to compare — the
  /// call is idempotent and order-independent on its own.
  ///
  /// Does nothing for an id this tree does not hold.
  void delete(FugueElementID nodeID) {
    final spot = _spotOf(nodeID);
    if (spot == null || !spot.run.deleteAt(spot.offset)) {
      return;
    }
    _index.setLengths(
      spot.run,
      length: spot.run.length,
      liveLength: spot.run.liveCount,
    );
  }

  /// Overwrites the value of [nodeID] in place, keeping its identity, its
  /// position and its liveness.
  ///
  /// Last-writer-wins on [stamp] (more details in [OperationId.compareTo]).
  ///
  /// Refuses unknown and tombstoned elements. A deletion is monotone, so an
  /// update that loses the race against one — or that arrives after the
  /// tombstone has been dropped by a snapshot — must not bring the element
  /// back.
  ///
  /// Returns whether [value] won.
  bool update({
    required FugueElementID nodeID,
    required T value,
    required OperationId stamp,
  }) {
    final spot = _spotOf(nodeID);
    if (spot == null || spot.run.deletedAt(spot.offset)) {
      return false;
    }

    final current = _stamps[nodeID];
    if (current != null && stamp.compareTo(current) <= 0) {
      return false;
    }

    spot.run.setValueAt(spot.offset, value);
    _stamps[nodeID] = stamp;
    return true;
  }

  /// The index at which [id] belongs in the id-sorted [siblings] list.
  int _siblingInsertionPoint(
    List<FugueElementID> siblings,
    FugueElementID id,
  ) =>
      siblings.lowerBoundBy(id, (s, t) => s.compareTo(t));

  /// Keeps [_index] in sync after [run] has been linked into the tree as the
  /// child at [position] on its side.
  void _indexInsert(FugueRun<T> run, int position, FugueRun<T>? holder) {
    final predecessor = _indexPredecessorFor(run, position, holder);
    if (predecessor == null) {
      _index.insertAtFront(
        run,
        length: run.length,
        liveLength: run.liveCount,
      );
    } else {
      _index.insertAfter(
        predecessor,
        run,
        length: run.length,
        liveLength: run.liveCount,
      );
    }
  }

  /// The run in-order before [run], linked as the child at [position] on its
  /// side, or `null` when [run] sorts at the very front of the sequence.
  FugueRun<T>? _indexPredecessorFor(
    FugueRun<T> run,
    int position,
    FugueRun<T>? holder,
  ) {
    final siblings = _childrenOf(holder, run.side);

    // A previous sibling exists: the predecessor is the in-order-last run of
    // its subtree.
    if (position > 0) {
      return _inOrderLastOfSubtree(siblings[position - 1]);
    }

    // [run] is the first child on its side.
    if (run.side == FugueSide.right) {
      if (holder == null) {
        // The root emits no value, so the predecessor is the in-order-last run
        // of the root's left subtree, or the front if there is none.
        final left = _childrenOf(null, FugueSide.left);
        return left.isEmpty ? null : _inOrderLastOfSubtree(left.last);
      }
      // An element immediately precedes its first right child in traversal
      // order, and normalization put the parent at the end of [holder].
      return holder;
    }

    // [run] now opens its parent's region: it sorts before every left sibling
    // already there, and before the parent itself when there are none. Taking
    // the predecessor of the parent would be wrong as soon as the parent has
    // other left children, because those come between the two.
    if (siblings.length > 1) {
      return _index.predecessorOf(_inOrderFirstOfSubtree(siblings[1]));
    }
    if (holder == null) {
      // The root emits no value and nothing precedes its left subtree.
      return null;
    }
    // Normalization put the parent at the start of [holder].
    return _index.predecessorOf(holder);
  }

  /// The last run visited by an in-order traversal of the subtree at [startID],
  /// i.e. following the right-children spine to its deepest end.
  FugueRun<T> _inOrderLastOfSubtree(FugueElementID startID) {
    var run = _runAt(startID);
    while (run.rightChildren.isNotEmpty) {
      run = _runAt(run.rightChildren.last);
    }
    return run;
  }

  /// The first run visited by an in-order traversal of the subtree at
  /// [startID], i.e. following the left-children spine to its deepest end.
  FugueRun<T> _inOrderFirstOfSubtree(FugueElementID startID) {
    var run = _runAt(startID);
    while (run.leftChildren.isNotEmpty) {
      run = _runAt(run.leftChildren.first);
    }
    return run;
  }

  /// Returns a string representation of the tree for debugging
  @override
  String toString() {
    final buffer = StringBuffer()..writeln('Tree:');
    for (final id in _childrenOf(null, FugueSide.left)) {
      _buildTreeString(id, 1, buffer);
    }
    for (final id in _childrenOf(null, FugueSide.right)) {
      _buildTreeString(id, 1, buffer);
    }
    return buffer.toString();
  }

  /// Helper to build the string representation of a run and its children
  void _buildTreeString(
    FugueElementID startID,
    int depth,
    StringBuffer buffer,
  ) {
    final spot = _spotOf(startID);
    if (spot == null) {
      return;
    }
    final run = spot.run;
    final indent = '  ' * depth;
    buffer
      ..writeln('$indent$run')
      ..writeln('$indent Left children:');
    for (final childID in run.leftChildren) {
      _buildTreeString(childID, depth + 1, buffer);
    }

    buffer.writeln('$indent Right children:');
    for (final childID in run.rightChildren) {
      _buildTreeString(childID, depth + 1, buffer);
    }
  }
}

/// One frame of the explicit-stack walk in [FugueTree.structuralSequence].
///
/// A frame either expands the subtree rooted at [id], or emits the elements
/// of [run].
class _Frame<T> {
  _Frame.expand(this.id) : run = null;

  _Frame.emit(this.run) : id = null;

  final FugueElementID? id;
  final FugueRun<T>? run;
}
