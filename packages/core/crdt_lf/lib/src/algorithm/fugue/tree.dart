import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/node.dart';
import 'package:crdt_lf/src/algorithm/fugue/node_triple.dart';
import 'package:crdt_lf/src/algorithm/fugue/run.dart';
import 'package:crdt_lf/src/algorithm/fugue/value_node.dart';
import 'package:crdt_lf/src/algorithm/sqrt_decomposition/sqrt_decomposition.dart';

/// Where an element sits: the run that holds it, and how far into it.
typedef _Spot<T> = ({FugueRun<T> run, int offset});

/// Implementation of the Fugue tree for collaborative text editing
///
/// ([The Art of the Fugue: Minimizing Interleaving in Collaborative Text
/// Editing](https://arxiv.org/abs/2305.00583))
///
/// ## Elements are grouped into runs
///
/// The tree does not hold one node per element. Elements one peer wrote with
/// consecutive counters, that ended up adjacent in the sequence, share a single
/// [FugueRun] — the model of Yjs's `Item` and of the *bunch* in
/// `mweidner037/list-positions`. Typing a paragraph costs one run, not one node
/// per character.
///
/// Grouping is a **local choice of representation**. Two peers that applied the
/// same operations may cut their runs in different places and still answer
/// every query identically: [values], [findNodeAtPosition], [findNextNode] and
/// [liveIndexAfter] are all defined on elements, and [FugueElementID] keeps its
/// meaning and its encoding. Nothing about a run reaches the wire.
class FugueTree<T> {
  FugueTree._();

  /// Initializes a new empty Fugue tree
  factory FugueTree.empty() => FugueTree<T>._();

  /// Creates a tree from a JSON object
  ///
  /// The JSON is **per element**, the shape this tree had before runs existed:
  /// runs are cut again on the way in, so a document written by any build
  /// reads back the same. See [toJson].
  factory FugueTree.fromJson(
    Map<String, dynamic> json,
  ) {
    final nodesJson = json['nodes'] as Map<String, dynamic>;
    final elements = <FugueElementID, FugueNodeTriple<T>>{};
    for (final entry in nodesJson.entries) {
      elements[FugueElementID.parse(entry.key)] =
          FugueNodeTriple<T>.fromJson(entry.value as Map<String, dynamic>);
    }

    final tree = FugueTree<T>._().._buildFromElements(elements);

    final stampsJson = json['stamps'] as Map<String, dynamic>?;
    if (stampsJson != null) {
      for (final entry in stampsJson.entries) {
        tree._stamps[FugueElementID.parse(entry.key)] =
            OperationId.parse(entry.value as String);
      }
    }

    return tree;
  }

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
  /// Keyed by the run itself rather than by its start id, so reading the
  /// sequence hands back the runs directly. Going through the ids would put a
  /// binary search between the index and every run it visits, which turns a
  /// full read from `O(n)` into `O(n log R)`.
  ///
  /// Answers position↔run and neighbour queries in `O(√R)` with `R` the number
  /// of runs; the walk inside the run is the tree's job, because the index does
  /// not know which of a run's elements are still there.
  ///
  /// - Never serialized;
  /// - Rebuilt on deserialization.
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
    var low = 0;
    var high = list.length - 1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      final run = list[middle];
      if (counter < run.startCounter) {
        high = middle - 1;
      } else if (counter >= run.startCounter + run.length) {
        low = middle + 1;
      } else {
        _lastSpotRun = run;
        return (run: run, offset: counter - run.startCounter);
      }
    }
    return null;
  }

  /// The run the last successful [_spotOf] landed in. See the note there.
  FugueRun<T>? _lastSpotRun;

  /// The run [startID] opens. [startID] must be a run start.
  FugueRun<T> _runAt(FugueElementID startID) => _spotOf(startID)!.run;

  /// Whether this tree holds [id].
  bool contains(FugueElementID id) => _spotOf(id) != null;

  /// Files [run] among its peer's runs, keeping them ordered by counter.
  void _register(FugueRun<T> run) {
    final list = _runs.putIfAbsent(
      run.startID.replicaID,
      () => <FugueRun<T>>[],
    );
    var low = 0;
    var high = list.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (list[middle].startCounter < run.startCounter) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
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
  /// This is the path sequential typing takes. `CrdtTextFieldBuilder` pushes
  /// one gesture at a time, so a paragraph arrives as one-element operations
  /// with consecutive counters; without this they would never share a run.
  ///
  /// The rule, element for element, is Yjs's `Item.mergeWith` minus its
  /// same-liveness condition, which a run does not need because it carries a
  /// flag per element:
  /// the same peer, the next counter, the new element hanging off the run's
  /// last element on the right, nothing else already hanging there, and room
  /// left under [maxRunLength].
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
  /// Only the first and last element of a run may carry children — everything
  /// in between is the chain that makes the run a run. Splitting restores that,
  /// and costs the sequence nothing: the two halves keep the parent/child
  /// relation the two elements already had.
  /// Returns the run the parent ends up in, which is the one that will carry
  /// the new child — or `null` for the root, which has no run.
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
  int _siblingInsertionPoint(List<FugueElementID> siblings, FugueElementID id) {
    var low = 0;
    var high = siblings.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (siblings[middle].compareTo(id) < 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

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

  // --- Building from a per-element description --------------------------

  /// Rebuilds this empty tree from a per-element description, cutting runs
  /// wherever the elements allow it.
  ///
  /// Two elements share a run under the same rule [_appendToRun] applies: the
  /// same peer, consecutive counters, the second hanging off the first on the
  /// right and nothing else hanging there, and no left children of its own.
  void _buildFromElements(Map<FugueElementID, FugueNodeTriple<T>> elements) {
    final ordered = <FugueElementID>[];
    _collectInOrder(elements, ordered);

    final keys = <FugueRun<T>>[];
    final lengths = <int>[];
    final liveLengths = <int>[];

    var start = 0;
    while (start < ordered.length) {
      final startID = ordered[start];
      var end = start + 1;
      while (end < ordered.length &&
          end - start < maxRunLength &&
          _continuesRun(elements, ordered[end - 1], ordered[end])) {
        end++;
      }

      final first = elements[startID]!;
      final last = elements[ordered[end - 1]]!;
      final run = FugueRun<T>(
        startID: startID,
        parentID: first.node.parentID,
        side: first.node.side,
        values: [
          for (var i = start; i < end; i++)
            elements[ordered[i]]!.node.value as T,
        ],
        deleted: [
          for (var i = start; i < end; i++) elements[ordered[i]]!.node.deleted,
        ],
      );
      for (var i = 0; i < first.leftChildren.length; i++) {
        run.insertChild(first.leftChildren[i], side: FugueSide.left, index: i);
      }
      for (var i = 0; i < last.rightChildren.length; i++) {
        run.insertChild(
          last.rightChildren[i],
          side: FugueSide.right,
          index: i,
        );
      }
      _register(run);

      keys.add(run);
      lengths.add(run.length);
      liveLengths.add(run.liveCount);
      start = end;
    }

    // The root's own children come straight from the description.
    final rootTriple = elements[_rootID];
    if (rootTriple != null) {
      for (var i = 0; i < rootTriple.leftChildren.length; i++) {
        _insertChildOf(null, FugueSide.left, i, rootTriple.leftChildren[i]);
      }
      for (var i = 0; i < rootTriple.rightChildren.length; i++) {
        _insertChildOf(null, FugueSide.right, i, rootTriple.rightChildren[i]);
      }
    }

    _index.bulkBuild(keys, lengths, liveLengths);
  }

  /// Whether [next] only continues the run [previous] belongs to.
  bool _continuesRun(
    Map<FugueElementID, FugueNodeTriple<T>> elements,
    FugueElementID previous,
    FugueElementID next,
  ) {
    final before = elements[previous]!;
    final after = elements[next]!;
    return next.replicaID == previous.replicaID &&
        next.counter == previous.counter! + 1 &&
        after.node.parentID == previous &&
        after.node.side == FugueSide.right &&
        after.leftChildren.isEmpty &&
        before.rightChildren.length == 1;
  }

  /// In-order traversal of a per-element description, collecting every element
  /// except the root, tombstones included.
  void _collectInOrder(
    Map<FugueElementID, FugueNodeTriple<T>> elements,
    List<FugueElementID> ordered,
  ) {
    final stack = <_TraversalStep>[_TraversalStep(_rootID, emitSelf: false)];

    while (stack.isNotEmpty) {
      final step = stack.removeLast();
      final triple = elements[step.id];
      if (triple == null) {
        continue;
      }

      if (step.emitSelf) {
        if (step.id != _rootID) {
          ordered.add(step.id);
        }
        continue;
      }

      for (final childID in triple.rightChildren.reversed) {
        stack.add(_TraversalStep(childID, emitSelf: false));
      }
      stack.add(_TraversalStep(step.id, emitSelf: true));
      for (final childID in triple.leftChildren.reversed) {
        stack.add(_TraversalStep(childID, emitSelf: false));
      }
    }
  }

  /// Serializes the tree to JSON format
  ///
  /// **Per element**, whatever the runs look like: a run is expanded back into
  /// the chain it stands for, each element carrying the parent, side and
  /// children it would have had on its own. Two peers that cut their runs
  /// differently therefore write the same JSON, and [FugueTree.fromJson] reads
  /// back anything any build wrote.
  ///
  /// Carries the [update] stamps next to the elements, because they are state:
  /// a tree restored without them accepts an update it had already rejected.
  Map<String, dynamic> toJson() {
    final nodesJson = <String, dynamic>{
      _rootID.toString(): FugueNodeTriple<T>(
        FugueNode<T>(
          id: _rootID,
          value: null,
          parentID: _rootID,
          side: FugueSide.left,
          deleted: true,
        ),
      ).toJson(),
    };
    _writeChildren(nodesJson, _rootID);

    for (final runs in _runs.values) {
      for (final run in runs) {
        for (var offset = 0; offset < run.length; offset++) {
          final id = run.idAt(offset);
          final isFirst = offset == 0;
          final isLast = offset == run.length - 1;
          nodesJson[id.toString()] = <String, dynamic>{
            'node': FugueNode<T>(
              id: id,
              value: run.valueAt(offset),
              parentID: isFirst ? run.parentID : run.idAt(offset - 1),
              side: isFirst ? run.side : FugueSide.right,
              deleted: run.deletedAt(offset),
            ).toJson(),
            'leftChildren': isFirst
                ? [for (final c in run.leftChildren) c.toJson()]
                : <dynamic>[],
            'rightChildren': isLast
                ? [for (final c in run.rightChildren) c.toJson()]
                : [run.idAt(offset + 1).toJson()],
          };
        }
      }
    }

    final stampsJson = <String, dynamic>{};
    for (final entry in _stamps.entries) {
      stampsJson[entry.key.toString()] = entry.value.toString();
    }

    return {
      'nodes': nodesJson,
      'stamps': stampsJson,
    };
  }

  /// Fills in the root's two child arrays, which have no run to come from.
  void _writeChildren(Map<String, dynamic> nodesJson, FugueElementID id) {
    final entry = nodesJson[id.toString()] as Map<String, dynamic>;
    entry['leftChildren'] = [
      for (final c in _childrenOf(null, FugueSide.left)) c.toJson(),
    ];
    entry['rightChildren'] = [
      for (final c in _childrenOf(null, FugueSide.right)) c.toJson(),
    ];
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

/// One frame of the explicit-stack in-order traversal in [FugueTree].
///
/// `emitSelf == false` expands the node (pushing its children and its own
/// emit frame); `emitSelf == true` visits the node itself.
class _TraversalStep {
  _TraversalStep(this.id, {required this.emitSelf});

  final FugueElementID id;
  final bool emitSelf;
}
