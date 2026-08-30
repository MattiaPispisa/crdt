import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/effects/text_delta.dart';
import 'package:crdt_lf_flutter/src/provider/_handler_delta_subscription.dart';
import 'package:crdt_lf_flutter/src/provider/crdt_helper.dart';
import 'package:flutter/widgets.dart';

/// Whether the text bindings compare their whole text against the handler.
///
/// A field derives its text from the deltas instead of projecting the whole
/// document, and checks the result after every step — in release too, with a
/// question that costs nothing: the whole string for `CRDTTextHandler`, the
/// O(1) length for the Fugue-backed handlers. A drift that keeps the length is
/// the one that cheap question cannot see.
///
/// While `true`, a debug build **also** compares the whole value and throws on
/// a mismatch, closing that gap. That comparison reads the value, which is the
/// cost the field exists to avoid, so only a benchmark should turn it off.
bool debugVerifyCrdtTextFieldProjection = true;

/// What the text-syncing engine needs from a handler, and the only thing it
/// knows about one.
///
/// It exists so that plain text and rich text are bound by the same code: the
/// two differ in the shape of their value and their delta, and in nothing the
/// engine does with them.
abstract class TextHandlerAdapter<V, D extends ComposableDelta<D>> {
  /// The handler's delta stream.
  DeltaProvider<V, D> get provider;

  /// The characters inside [value].
  String textOf(V value);

  /// The part of [delta] that moved the characters, or `null` when the delta
  /// says nothing about them.
  SequenceDelta<String>? textDeltaOf(D delta);

  /// Puts [text] in at [index], counted in runes.
  void insert(int index, String text);

  /// Takes [count] runes out at [index].
  void delete(int index, int count);

  /// Whether the handler still holds exactly [text], which is [runes] runes
  /// long.
  ///
  /// The engine derives its text from the deltas and never reads it back, so
  /// it asks this after every step — in release too. An implementation
  /// answers with the cheapest question it has: an `O(1)` rune count where
  /// there is one, the whole string otherwise.
  bool agreesWith(String text, int runes);

  /// The handler's whole text, read. Only for the debug-only strict check.
  String get debugWholeText => textOf(provider.value);

  /// A stable anchor for a caret at [runeIndex], or `null` for a handler that
  /// carries no element identity.
  FugueElementID? stablePositionAt(int runeIndex) => null;

  /// Where the caret anchored at [position] sits now, in runes.
  int? indexOfStablePosition(FugueElementID position) => null;
}

/// Binds a [TextEditingController] to a text handler, whatever the shape of
/// its value.
///
/// This is the whole of `CrdtTextFieldBuilder`'s behaviour, with the handler
/// reached through a [TextHandlerAdapter]. See that widget for what it
/// promises; everything documented there is done here.
class TextSyncBuilder<V, D extends ComposableDelta<D>> extends StatefulWidget {
  /// Creates a binding to the handler registered under [id].
  const TextSyncBuilder({
    required this.id,
    required this.adapterFor,
    required this.builder,
    this.createController,
    this.onSelectionAnchorsChanged,
    this.onSeed,
    this.onDelta,
    super.key,
  });

  /// The id of the handler to bind.
  final String id;

  /// Builds the adapter for the handler registered under [id] on a document.
  ///
  /// Throws when the handler is missing or of a type this binding refuses.
  final TextHandlerAdapter<V, D> Function(CRDTDocument document, String id)
      adapterFor;

  /// Builds the controller the field will use. Defaults to a plain
  /// [TextEditingController].
  final TextEditingController Function(String text)? createController;

  /// Called once, with the controller this widget owns.
  final Widget Function(
    BuildContext context,
    TextEditingController controller,
  ) builder;

  /// Called whenever the stable anchors of the local selection change.
  final void Function(FugueElementID? base, FugueElementID? extent)?
      onSelectionAnchorsChanged;

  /// Called with the handler's whole value whenever it had to be read.
  ///
  /// Where a consumer of the value — the formatting of a rich text field, say
  /// — seeds itself.
  final void Function(V value)? onSeed;

  /// Called with each delta, after the text has been folded in.
  final void Function(D delta)? onDelta;

  @override
  State<TextSyncBuilder<V, D>> createState() => _TextSyncBuilderState<V, D>();
}

class _TextSyncBuilderState<V, D extends ComposableDelta<D>>
    extends State<TextSyncBuilder<V, D>> {
  TextEditingController? _controller;

  /// Set by the first `build`; everything else runs after one.
  late CRDTDocument _document;

  /// The adapter for the handler currently bound, rebuilt on every attach.
  TextHandlerAdapter<V, D>? _adapter;

  /// The handler's delta stream, and the bookkeeping every consumer of one
  /// needs: which handler, how far it has got, what it has already taken in.
  late final HandlerDeltaSubscription<V, D> _delta =
      HandlerDeltaSubscription<V, D>(
    resolve: (document, id) => _adapterFor(document, id).provider,
    onReset: (point, cause) {
      if (_pushing) {
        // Not an echo: the base the deltas describe is gone. It cannot be
        // dropped, only put off until the push has finished.
        _resetWhilePushing = true;
        return;
      }
      _observeValue(point.value);
      _settle(text: _adapter!.textOf(point.value));
    },
    onDelta: (event) {
      // The observer is told whatever the delta says, echo or not: what it
      // watches — the formatting of a rich text field — is absolute rather
      // than expressed in the coordinates the push guard is about. Dropping
      // the echo here would leave the formatting a step behind every local
      // edit.
      _observeDelta(event.delta);
      if (_pushing) {
        return;
      }
      _settle(reported: _adapter!.textDeltaOf(event.delta));
    },
    isAlive: () => mounted,
    // Read while attaching, so the first frame already shows the document
    // instead of an empty field that fills in a frame later.
    seed: true,
  );

  /// Whether this widget is writing into the handler right now.
  ///
  /// A write commits synchronously, so everything it publishes comes back
  /// before the push has written down what it did. Nothing may be folded in
  /// until then, whoever it came from:
  ///
  /// - **our own echo** — already in the controller; folding it in would apply
  ///   the edit twice;
  /// - **someone else's delta** — the flush hands our echo to the other
  ///   watchers, and one that writes back is served in the same pass, so its
  ///   delta reaches us still inside our `runInTransaction`. Its coordinates
  ///   are those of a text `_lastCommittedText` does not hold yet.
  ///
  /// Both are dropped here and settled afterwards: `markSyncedToPublished`
  /// accounts for them, and `_verifyProjection` reads once if the second left
  /// the field behind.
  ///
  /// This is why `HandlerDelta.origin` cannot replace the flag — it identifies
  /// the first case and lets the second through. Nor does it cover the reset,
  /// which carries no origin.
  bool _pushing = false;

  /// Whether the engine is in the middle of its own work.
  ///
  /// It writes to the controller as it settles, and telling an observer what
  /// moved may make the controller notify as well. Either would come back
  /// through [_onControllerChanged] and be read as the user typing — in the
  /// very window where the controller and [_lastCommittedText] are *meant* to
  /// disagree, so the guess would be a second push of an edit already in
  /// flight.
  bool _busy = false;

  /// Runs [work] with [_busy] set, restoring what it was.
  ///
  /// Saved and restored rather than cleared: this work nests.
  void _guarded(VoidCallback work) {
    final was = _busy;
    _busy = true;
    try {
      work();
    } finally {
      _busy = was;
    }
  }

  void _observeDelta(D delta) => _guarded(() => widget.onDelta?.call(delta));

  void _observeValue(V value) => _guarded(() => widget.onSeed?.call(value));

  /// Whether the handler asked for a read while [_pushing] was set.
  bool _resetWhilePushing = false;

  /// The handler-side text this widget has last pushed or adopted. Local
  /// deltas are computed against it.
  String _lastCommittedText = '';

  /// How many runes [_lastCommittedText] holds.
  ///
  /// Carried by arithmetic — every delta says how many elements it puts in and
  /// takes out — so [_verifyProjection] can ask the handler whether the two
  /// still agree without counting anything.
  int _lastCommittedRunes = 0;

  /// Stable anchors for the current selection, captured whenever controller
  /// and handler agree. `null` while they diverge (a composition is pending)
  /// or for a handler that carries no element identity — [_adopt] then places
  /// the offsets from the reported delta instead.
  FugueElementID? _selectionBaseAnchor;
  FugueElementID? _selectionExtentAnchor;

  /// Whether the field inside the builder has focus. Anchors keep being
  /// captured regardless (they anchor [_adopt] too), but they are only
  /// *published* while focused: an unfocused field retains its selection,
  /// which is not the collaborator's cursor.
  bool _hasFocus = false;

  /// What was last handed to `onSelectionAnchorsChanged`.
  FugueElementID? _publishedBase;
  FugueElementID? _publishedExtent;

  @override
  Widget build(BuildContext context) {
    final document = _document = context.crdtDocument;
    // Covers a new document and a new id alike, which is why there is no
    // `didUpdateWidget`: `build` always runs after one.
    final seed = _delta.syncTo(
      document,
      widget.id,
      // The anchors belong to the old handler; they must go before anything
      // reads the new one, because seeding captures them again.
      onBeforeAttach: _invalidateSelectionAnchors,
    );
    if (seed != null) {
      _observeValue(seed.value);
      _seed(_adapter!.textOf(seed.value));
    }
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: _onFocusChange,
      child: widget.builder(context, _controller!),
    );
  }

  @override
  void dispose() {
    _delta.cancel();
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  TextHandlerAdapter<V, D> _adapterFor(CRDTDocument document, String id) {
    return _adapter = widget.adapterFor(document, id);
  }

  TextHandlerAdapter<V, D> _handler() => _adapterFor(_document, widget.id);

  /// Takes in the text read while attaching, building the controller the
  /// first time and adopting into it afterwards.
  void _seed(String seeded) {
    if (_controller == null) {
      _lastCommittedText = seeded;
      _lastCommittedRunes = RuneOffsets.length(seeded);
      _controller = widget.createController?.call(seeded) ??
          TextEditingController(text: seeded);
      _controller!.addListener(_onControllerChanged);
      return;
    }
    _adopt(seeded, runes: RuneOffsets.length(seeded));
  }

  /// Pushes [delta] into the handler. Its offsets are code-unit offsets into
  /// [against], the handler's text as the delta was computed against it.
  ///
  /// Returns how many runes the push takes out and puts in, which is what
  /// keeps [_lastCommittedRunes] right without counting the text again.
  ({int deleted, int inserted}) _applyDelta(TextDelta delta, String against) {
    final handler = _handler();

    // [TextDelta] is expressed in code units, the handlers in runes. The
    // delta's boundaries are snapped to code-point boundaries by
    // [computeTextDelta], so both ends convert exactly.
    final index = RuneOffsets.runeIndex(against, delta.index);
    final deleted = delta.deleted == 0
        ? 0
        : RuneOffsets.runeIndex(against, delta.index + delta.deleted) - index;
    final inserted = RuneOffsets.length(delta.inserted);

    void run() {
      if (deleted > 0) {
        handler.delete(index, deleted);
      }
      if (delta.inserted.isNotEmpty) {
        handler.insert(index, delta.inserted);
      }
    }

    _pushing = true;
    try {
      _document.runInTransaction(run);
    } finally {
      _pushing = false;
    }
    return (deleted: deleted, inserted: inserted);
  }

  /// Captures the stable anchors of the current selection.
  ///
  /// Only meaningful when the controller text matches the handler text (the
  /// offsets must be valid in the handler's coordinates).
  void _captureSelectionAnchors() {
    final handler = _adapter;
    if (handler == null) {
      return;
    }
    final selection = _controller!.selection;
    // Selection offsets are code-unit offsets; the handler anchors by rune.
    final text = _controller!.text;
    _setSelectionAnchors(
      selection.baseOffset < 0
          ? null
          : handler.stablePositionAt(
              RuneOffsets.runeIndex(text, selection.baseOffset),
            ),
      selection.extentOffset < 0
          ? null
          : handler.stablePositionAt(
              RuneOffsets.runeIndex(text, selection.extentOffset),
            ),
    );
  }

  void _invalidateSelectionAnchors() {
    _setSelectionAnchors(null, null);
  }

  void _setSelectionAnchors(FugueElementID? base, FugueElementID? extent) {
    if (base == _selectionBaseAnchor && extent == _selectionExtentAnchor) {
      return;
    }
    _selectionBaseAnchor = base;
    _selectionExtentAnchor = extent;
    _publishAnchors();
  }

  void _onFocusChange(bool hasFocus) {
    if (_hasFocus == hasFocus) {
      return;
    }
    _hasFocus = hasFocus;
    _publishAnchors();
  }

  void _publishAnchors() {
    final base = _hasFocus ? _selectionBaseAnchor : null;
    final extent = _hasFocus ? _selectionExtentAnchor : null;
    if (base == _publishedBase && extent == _publishedExtent) {
      return;
    }
    _publishedBase = base;
    _publishedExtent = extent;
    widget.onSelectionAnchorsChanged?.call(base, extent);
  }

  /// Local edits: push the delta of the gesture into the handler.
  void _onControllerChanged() {
    if (_busy) {
      // The engine is writing, not the user.
      return;
    }
    final value = _controller!.value;
    if (value.text == _lastCommittedText) {
      // Selection-only change, or a canceled composition.
      _captureSelectionAnchors();
      return;
    }
    if (value.isComposingRangeValid) {
      // Mid-composition (IME/autocorrect): commit when composition ends. The
      // anchors go stale with the uncommitted text.
      _invalidateSelectionAnchors();
      return;
    }
    _pushLocalEdits();
  }

  /// Pushes the gesture the controller is holding into the handler.
  ///
  /// [handlerState] is what the handler holds now, when the caller knows it. It
  /// is believed only while the stream is level: it describes **one** event,
  /// and a burst is published at once but delivered one at a time, so the
  /// handler has already folded the rest. When the stream is ahead, one read
  /// settles it instead — guessing pushes the edit at the wrong index and marks
  /// the events still in flight as accounted for, dropping them.
  void _pushLocalEdits({({String text, int runes})? handlerState}) {
    _guarded(() => _pushLocalEditsWork(handlerState));
  }

  void _pushLocalEditsWork(({String text, int runes})? handlerState) {
    var known = handlerState;
    if (_delta.publishedSeq != _delta.synced) {
      final point = _delta.readSynced();
      _observeValue(point.value);
      final text = _adapter!.textOf(point.value);
      known = (text: text, runes: RuneOffsets.length(text));
    }
    final handlerText = known?.text ?? _lastCommittedText;
    final handlerRunes = known?.runes ?? _lastCommittedRunes;

    final target = _controller!.text;

    // The post-edit caret disambiguates edits inside a run of identical
    // characters (e.g. a newline typed right before another newline), so the
    // gesture is recorded where the user actually is, not slid past it.
    final selection = _controller!.selection;
    final caret = selection.isCollapsed ? selection.baseOffset : null;
    final delta = computeTextDelta(_lastCommittedText, target, caret: caret);
    if (delta == null) {
      // Nothing of ours to push — both callers rule this out, but whatever the
      // handler moved still has to be taken in rather than dropped.
      if (known != null) {
        _adopt(handlerText, runes: handlerRunes);
      }
      return;
    }

    var pushed = delta;
    if (handlerText != _lastCommittedText) {
      // Rare: a remote change landed while local edits were pending (only
      // possible during composition). Rebase the local delta onto the merged
      // text, best-effort, and let the CRDT do the merging.
      final remote = computeTextDelta(_lastCommittedText, handlerText)!;
      final index = mapOffsetThroughDelta(delta.index, remote)
          .clamp(0, handlerText.length);
      final deletable = handlerText.length - index;
      pushed = TextDelta(
        index: index,
        deleted: delta.deleted > deletable ? deletable : delta.deleted,
        inserted: delta.inserted,
      );
    }

    final moved = _applyDelta(pushed, handlerText);

    // We know what we pushed, so the new text is the old one spliced — no need
    // to project the document again.
    _lastCommittedText = handlerText.replaceRange(
      pushed.index,
      pushed.index + pushed.deleted,
      pushed.inserted,
    );
    _lastCommittedRunes = handlerRunes - moved.deleted + moved.inserted;
    // Everything before the push is folded in above, and the push published its
    // own events as it ran. So this covers our echo too.
    _delta.markSyncedToPublished();

    if (_resetWhilePushing) {
      _resetWhilePushing = false;
      // The base moved while we were writing, so the lines above may describe a
      // document that is gone. The value the reset carried is no good either:
      // read mid-transaction, it could not see the edit being pushed.
      final point = _delta.readSynced();
      _observeValue(point.value);
      _lastCommittedText = _adapter!.textOf(point.value);
      _lastCommittedRunes = RuneOffsets.length(_lastCommittedText);
    }

    if (_lastCommittedText != _controller!.text) {
      // The rebase above merged remote content in: adopt it.
      _adopt(_lastCommittedText, runes: _lastCommittedRunes);
    } else {
      _captureSelectionAnchors();
    }
    _verifyProjection();
  }

  /// Folds one reported move into the field.
  ///
  /// [text] is the handler's whole text when it had to be read; [reported] is
  /// the delta when it did not.
  ///
  /// Done now rather than batched: taking a delta in costs the size of the
  /// edit, so waiting would only make the field lag behind the CRDT.
  void _settle({String? text, SequenceDelta<String>? reported}) {
    _guarded(() => _settleWork(text: text, reported: reported));
  }

  void _settleWork({String? text, SequenceDelta<String>? reported}) {
    final base = text ?? _lastCommittedText;
    final runes = text != null
        ? RuneOffsets.length(text)
        : _lastCommittedRunes + _netRunes(reported);
    // Worked out from what the handler said it did, so the whole document is
    // never projected again for an edit of a few characters.
    final merged = reported == null ? base : reported.applyToText(base);

    if (_controller!.text != _lastCommittedText) {
      // Uncommitted local edits (a composition in progress): commit them
      // first. The handler merges them with what just arrived, and the push
      // adopts the result.
      _pushLocalEdits(handlerState: (text: merged, runes: runes));
      return;
    }

    // After a read the delta and the controller's text belong to different
    // bases, so the caret cannot ride on them — [reported] is null there.
    _adopt(merged, runes: runes, reported: reported);
    _verifyProjection();
  }

  /// Runes [delta] puts in, net of the ones it takes out.
  ///
  /// A move carries its element along, so it changes nothing here.
  static int _netRunes(SequenceDelta<String>? delta) {
    if (delta == null) {
      return 0;
    }
    var net = 0;
    for (final op in delta.ops) {
      switch (op) {
        case SeqInsert<String>():
          net += op.values.length;
        case SeqDelete<String>():
          net -= op.count;
        case SeqRetain<String>():
        case SeqMove<String>():
          break;
      }
    }
    return net;
  }

  /// Puts the field back in step when its text has drifted from the handler.
  ///
  /// The text is derived and never read back, so a mistake would leave a
  /// document on screen that does not exist until the next reset. This is the
  /// cheapest question that catches it; see
  /// [debugVerifyCrdtTextFieldProjection] for the strict version and the gap it
  /// closes.
  void _verifyProjection() {
    if (_delta.synced != _delta.publishedSeq) {
      // A burst is published at once and delivered one at a time, so the two
      // are meant to disagree in between. Ask only once they are level.
      return;
    }

    final handler = _handler();
    final agrees = handler.agreesWith(_lastCommittedText, _lastCommittedRunes);
    assert(
      !debugVerifyCrdtTextFieldProjection ||
          handler.debugWholeText == _lastCommittedText,
      'the text derived from the deltas drifted from the handler',
    );
    if (agrees) {
      return;
    }
    final point = _delta.readSynced();
    _observeValue(point.value);
    final text = _adapter!.textOf(point.value);
    _adopt(text, runes: RuneOffsets.length(text));
  }

  /// Replaces the controller text with [merged], keeping caret and selection
  /// visually anchored.
  ///
  /// Three ways to place an offset, best first:
  ///
  /// 1. its **stable position**, the identity of the element left of it, which
  ///    only a Fugue-backed handler carries;
  /// 2. [reported], the delta the handler published, exact even when the change
  ///    touched several regions;
  /// 3. a diff of the two texts, which collapses several regions into one span.
  ///    Best-effort, and only used when the handler asked for a fresh read.
  void _adopt(
    String merged, {
    required int runes,
    SequenceDelta<String>? reported,
  }) {
    final old = _controller!.value;
    _lastCommittedText = merged;
    _lastCommittedRunes = runes;
    if (old.text == merged) {
      _captureSelectionAnchors();
      return;
    }

    final handler = _handler();
    TextDelta? diffed;
    int map(int offset, FugueElementID? anchor) {
      if (offset < 0) {
        // No selection (field never touched): keep it that way — turning it
        // into a caret would publish a phantom cursor on adopt.
        return offset;
      }
      if (anchor != null) {
        final resolved = handler.indexOfStablePosition(anchor);
        if (resolved != null) {
          // A rune index: back to a code-unit offset for the selection.
          return RuneOffsets.utf16Offset(merged, resolved);
        }
      }
      if (reported != null) {
        // The handler counts runes, the field counts code units.
        final rune = RuneOffsets.runeIndex(old.text, offset);
        return RuneOffsets.utf16Offset(merged, reported.mapOffset(rune))
            .clamp(0, merged.length);
      }
      diffed ??= computeTextDelta(old.text, merged)!;
      return mapOffsetThroughDelta(offset, diffed!).clamp(0, merged.length);
    }

    // A composition in progress spans code units that just moved. Carry it, or
    // a remote change throws away what the user is typing.
    var composing = TextRange.empty;
    if (old.composing.isValid) {
      final start = map(old.composing.start, null);
      final end = map(old.composing.end, null);
      if (start < end) {
        composing = TextRange(start: start, end: end);
      }
    }

    _controller!.value = TextEditingValue(
      text: merged,
      selection: TextSelection(
        baseOffset: map(old.selection.baseOffset, _selectionBaseAnchor),
        extentOffset: map(old.selection.extentOffset, _selectionExtentAnchor),
      ),
      composing: composing,
    );
    _captureSelectionAnchors();
  }
}
