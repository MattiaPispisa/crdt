// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/editor/crdt_editor_binding.dart';
import 'package:crdt_lf_flutter/src/effects/_text_field_core.dart';
import 'package:crdt_lf_flutter/src/effects/text_delta.dart';
import 'package:crdt_lf_flutter/src/provider/handler_delta_subscription.dart';
import 'package:flutter/widgets.dart';

/// What `TextFieldEngine` asks of the field that owns it.
///
/// [C] is the content the field keeps (the text, or the spans) and [D] the
/// delta the handler publishes.
abstract interface class TextFieldContent<C, D extends ComposableDelta<D>> {
  /// Builds the controller the first time, showing [content].
  TextEditingController createController(C content);

  /// The plain text of [content].
  String textOf(C content);

  /// How many runes [content] holds.
  int runesOf(C content);

  /// [base] with [delta] applied.
  C apply(C base, D delta);

  /// Runes [delta] puts in, net of the ones it takes out.
  int netRunes(D delta);

  /// Maps a rune index of the old text to the new one, through [delta].
  int Function(int rune) offsetMapper(D delta);

  /// Writes the edit into the handler, inside the push.
  ///
  /// [pushed] holds code-unit offsets into [baseText]; [index] and [deleted]
  /// are the same edit in runes. Returns the content once the edit is in.
  C write(C base, String baseText, TextDelta pushed, int index, int deleted);

  /// Whether [dropped] holds nothing but the write of [deleted] and
  /// [inserted] runes.
  bool echoes(
    List<D> dropped, {
    required int deleted,
    required int inserted,
  });

  /// The part of [typed] the field writes to the handler.
  String writable(String typed);

  /// Gives the controller a new [value] showing [content].
  void show(TextEditingValue value, C content);

  /// Shows [content], which has the text the controller already holds.
  void showFormats(C content);

  /// Whether the field still agrees with the handler, cheaply.
  bool projectionAgrees();

  /// Whether the handler has element identities to anchor the selection to.
  bool get anchored;

  /// The anchor of a rune index.
  FugueElementID? anchorAt(int rune);

  /// The rune index of [anchor] now; `null` when it cannot be placed.
  int? runeOf(FugueElementID anchor);

  /// The selection changed with the text at rest.
  void selectionSettled();

  /// A remote [delta] is about to be taken in.
  void remoteReported(D delta);
}

/// What a [TextFieldContent] adds when U+FFFC stands for an embed: the engine
/// then keeps the embeds a value rewrites.
abstract interface class EmbedFieldContent<C> {
  /// Writes [regions] into the handler in one transaction, inside the push.
  ///
  /// Each region holds offsets into the text the regions before it left.
  /// Returns the content once the edits are in.
  C writeRegions(C base, String baseText, List<TextRegion> regions);
}

/// What the handler holds, as far as the engine knows it.
typedef _Known<C> = ({C content, String text, int runes});

/// One edit of a write: `pushed` in code units, `index` and `deleted` in
/// runes.
typedef TextRegion = ({TextDelta pushed, int index, int deleted});

const String _embed = '\uFFFC';

/// The sync loop of a text field: local edits in, remote changes out.
///
/// Local edits are pushed as the delta of each gesture. A composition is
/// committed when it ends. A remote change is adopted in place with the caret
/// kept. It carries what the two text fields share, and asks the field for
/// what differs through `TextFieldContent`.
class TextFieldEngine<C, D extends ComposableDelta<D>> {
  /// Creates an engine that follows no handler until [attach].
  ///
  /// [publish] receives the anchors of the selection; [resolve] finds the
  /// handler, as for `CrdtEditorBinding`.
  TextFieldEngine(
    this._content, {
    required void Function(FugueElementID? base, FugueElementID? extent)
        publish,
    DeltaProviderResolver<C, D>? resolve,
  })  : _embeds = _content is EmbedFieldContent<C>
            ? _content as EmbedFieldContent<C>
            : null,
        anchors = SelectionAnchors(publish) {
    binding = CrdtEditorBinding<C, D>(
      resolve: resolve,
      onReset: (value, cause) {
        if (_seeding) {
          _seed(value);
          return;
        }
        _settle(content: value);
      },
      onRemoteDelta: (event) => _settle(reported: event.delta),
      verifyProjection: _content.projectionAgrees,
      // An empty delta still has to commit a pending composition.
      skipEmptyDeltas: false,
    );
  }

  final TextFieldContent<C, D> _content;

  final EmbedFieldContent<C>? _embeds;

  /// The handler's delta stream, and the guard around a push.
  late final CrdtEditorBinding<C, D> binding;

  /// The stable anchors of the selection.
  final SelectionAnchors anchors;

  TextEditingController? _controller;

  // Whether the engine is taking out of the controller what it does not write.
  bool _dropping = false;

  /// Whether [binding] is reading the value while attaching.
  ///
  /// That read builds the controller the first time, so it skips [_settle].
  bool _seeding = false;

  // Whether [anchors] hold the selection of the content in place. A keystroke
  // asks for them several times, and each capture costs tree lookups.
  bool _anchorsCurrent = false;

  late C _committed;
  String _committedText = '';

  /// How many runes [committedText] holds.
  ///
  /// Carried by arithmetic, so the projection check needs no count.
  int committedRunes = 0;

  /// The controller the field shows. Set by the first [attach].
  TextEditingController get controller => _controller!;

  /// What the field has last pushed or adopted. Local deltas are computed
  /// against it.
  C get committed => _committed;

  /// The plain text of [committed].
  String get committedText => _committedText;

  /// Follows the handler [id] of [document].
  ///
  /// Covers a new document and a new id alike. The first call builds the
  /// controller. [onBeforeAttach] runs as `CrdtEditorBinding.attach` says.
  void attach(
    CRDTDocument document,
    String id, {
    VoidCallback? onBeforeAttach,
  }) {
    _seeding = true;
    try {
      binding.attach(
        document,
        id,
        // The anchors belong to the old handler; they must go before anything
        // reads the new one, because seeding captures them again.
        onBeforeAttach: () {
          anchors.clear();
          onBeforeAttach?.call();
        },
      );
    } finally {
      _seeding = false;
    }
  }

  /// Stops following the handler.
  void dispose() {
    binding.dispose();
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
  }

  // Takes in the content read while attaching, building the controller the
  // first time and adopting into it afterwards.
  void _seed(C seeded) {
    final text = _content.textOf(seeded);
    final runes = _content.runesOf(seeded);
    if (_controller == null) {
      _commit(seeded, text, runes);
      _controller = _content.createController(seeded)
        ..addListener(_onControllerChanged);
      return;
    }
    _adopt(seeded, text, runes);
    captureAnchors();
  }

  void _commit(C content, String text, int runes) {
    _anchorsCurrent = false;
    _committed = content;
    _committedText = text;
    committedRunes = runes;
  }

  /// Replaces the content with one of the same text, with new formats.
  void reformat(C content) {
    _committed = content;
    _content.showFormats(content);
  }

  /// Anchors the current selection. Call it when the controller and the
  /// handler agree.
  void captureAnchors() {
    if (_anchorsCurrent) {
      return;
    }
    // Mid-burst the controller is behind the handler: its offsets would name
    // the wrong elements.
    if (!_content.anchored || binding.isBehind) {
      return;
    }
    // Before the capture: a listener of the anchors may move the selection.
    _anchorsCurrent = true;
    anchors.capture(controller.selection, controller.text, _content.anchorAt);
  }

  // Local edits: push the delta of the gesture into the handler.
  void _onControllerChanged() {
    _anchorsCurrent = false;
    if (_dropping) {
      return;
    }
    final document = binding.document;
    if (document == null || document.isDeleted(binding.id!)) {
      // Until the next frame swaps the field out, an edit has nowhere to go.
      return;
    }
    final value = controller.value;
    if (value.text == _committedText) {
      // Selection-only change, or a canceled composition.
      _content.selectionSettled();
      captureAnchors();
      return;
    }
    if (value.isComposingRangeValid) {
      // Mid-composition (IME/autocorrect): commit when composition ends. The
      // anchors go stale with the uncommitted text.
      anchors.clear();
      return;
    }
    _pushLocalEdits();
  }

  // Pushes the gesture the controller is holding into the handler.
  //
  // [known] is what the handler holds now, when the caller knows it. It is
  // believed only while the stream is level: it describes **one** event, and a
  // burst is published at once but delivered one at a time, so the handler has
  // already folded the rest. When the stream is ahead, one read settles it
  // instead — guessing pushes the edit at the wrong index and marks the events
  // still in flight as accounted for, dropping them.
  void _pushLocalEdits({_Known<C>? known}) {
    var base = known;
    if (binding.isBehind) {
      final read = binding.readSynced();
      base = (
        content: read,
        text: _content.textOf(read),
        runes: _content.runesOf(read),
      );
    }
    final baseContent = base?.content ?? _committed;
    final baseText = base?.text ?? _committedText;
    final baseRunes = base?.runes ?? committedRunes;

    // The post-edit caret disambiguates edits inside a run of identical
    // characters (e.g. a newline typed right before another newline), so the
    // gesture is recorded where the user actually is, not slid past it.
    final selection = controller.selection;
    final caret = selection.isCollapsed ? selection.baseOffset : null;
    final computed =
        computeTextDelta(_committedText, controller.text, caret: caret);
    if (_embeds != null && _rewritesEmbed(computed)) {
      _pushRegions(computed!, baseContent, baseText, baseRunes);
      return;
    }
    final delta = _writableDelta(computed);
    if (delta == null) {
      // Nothing of ours to push — both callers rule this out, but whatever the
      // handler moved still has to be taken in rather than dropped.
      if (base != null) {
        _adopt(baseContent, baseText, baseRunes);
        captureAnchors();
      }
      return;
    }

    // A remote change landed while local edits were pending (only possible
    // during a composition): rebase onto the merged text.
    var pushed = delta;
    if (baseText != _committedText) {
      final rebased = rebaseDelta(delta, _committedText, baseText);
      if (rebased.length > 1) {
        _writeRegions(rebased, baseContent, baseText, baseRunes);
        return;
      }
      pushed = rebased.single;
    }

    // [TextDelta] is expressed in code units, the handlers in runes. The
    // delta's boundaries are snapped to code-point boundaries by
    // [computeTextDelta], so both ends convert exactly.
    final index = RuneOffsets.runeIndex(baseText, pushed.index);
    final deleted = pushed.deleted == 0
        ? 0
        : RuneOffsets.runeIndex(baseText, pushed.index + pushed.deleted) -
            index;
    final inserted = RuneOffsets.length(pushed.inserted);

    binding.push(
      () {
        final content = _content.write(
          baseContent,
          baseText,
          pushed,
          index,
          deleted,
        );
        // We know what we pushed, so the new content comes from the old one:
        // no need to project the document again. Adopting also covers the
        // rebase above having merged remote content in.
        _adopt(
          content,
          _content.textOf(content),
          baseRunes - deleted + inserted,
        );
      },
      isEcho: (dropped) => _content.echoes(
        dropped,
        deleted: deleted,
        inserted: inserted,
      ),
    );
    captureAnchors();
  }

  // Whether [delta] deletes an embed and puts a U+FFFC back: a value set with
  // edits on both sides of the embed, which one region would delete.
  bool _rewritesEmbed(TextDelta? delta) {
    if (delta == null ||
        delta.deleted == 0 ||
        !delta.inserted.contains(_embed)) {
      return false;
    }
    final end = delta.index + delta.deleted;
    for (var i = delta.index; i < end; i++) {
      if (_committedText.codeUnitAt(i) == 0xFFFC) {
        return true;
      }
    }
    return false;
  }

  // Pushes [computed] as the regions a diff finds in it: the embeds both
  // sides hold stay common, and each edit around them is a write of its own.
  void _pushRegions(
    TextDelta computed,
    C baseContent,
    String baseText,
    int baseRunes,
  ) {
    final regions = <TextDelta>[];
    final strips = <({int start, String typed, String kept})>[];
    // Offsets into the committed text and into the controller's.
    var oldAt = computed.index;
    var newAt = computed.index;
    var start = -1;
    var deleted = 0;
    final inserted = StringBuffer();
    void close() {
      if (start >= 0 && (deleted > 0 || inserted.isNotEmpty)) {
        regions.add(
          TextDelta(
            index: start,
            deleted: deleted,
            inserted: inserted.toString(),
          ),
        );
      }
      start = -1;
      deleted = 0;
      inserted.clear();
    }

    final removed = _committedText.substring(
      computed.index,
      computed.index + computed.deleted,
    );
    for (final segment in myersDiff(removed, computed.inserted)) {
      final length = segment.text.length;
      switch (segment.op) {
        case DiffOp.equal:
          close();
          oldAt += length;
          newAt += length;
        case DiffOp.remove:
          if (start < 0) {
            start = oldAt;
          }
          deleted += length;
          oldAt += length;
        case DiffOp.insert:
          if (start < 0) {
            start = oldAt;
          }
          final kept = _content.writable(segment.text);
          if (kept.length != length) {
            strips.add((start: newAt, typed: segment.text, kept: kept));
          }
          inserted.write(kept);
          newAt += length;
      }
    }
    close();

    if (strips.isNotEmpty) {
      var text = controller.text;
      for (final (:start, :typed, :kept) in strips.reversed) {
        text = text.replaceRange(start, start + typed.length, kept);
      }
      _showWritable(text, (offset) {
        var mapped = offset;
        for (final (:start, :typed, :kept) in strips) {
          if (offset <= start) {
            break;
          }
          mapped -= offset >= start + typed.length
              ? typed.length - kept.length
              : offset -
                  start -
                  _content.writable(typed.substring(0, offset - start)).length;
        }
        return mapped;
      });
    }

    _writeRegions(
      baseText == _committedText
          ? regions
          : [
              for (final region in regions)
                ...rebaseDelta(region, _committedText, baseText),
            ],
      baseContent,
      baseText,
      baseRunes,
    );
  }

  // Pushes `regions`, offsets into `baseText`, as one write.
  void _writeRegions(
    List<TextDelta> regions,
    C baseContent,
    String baseText,
    int baseRunes,
  ) {
    // Each region moves by the ones before it.
    var text = baseText;
    var shift = 0;
    var deletedRunes = 0;
    var insertedRunes = 0;
    final written = <TextRegion>[];
    for (final region in regions) {
      final at = (region.index + shift).clamp(0, text.length);
      final cut = region.deleted.clamp(0, text.length - at);
      final pushed =
          TextDelta(index: at, deleted: cut, inserted: region.inserted);
      final index = RuneOffsets.runeIndex(text, at);
      final runes =
          cut == 0 ? 0 : RuneOffsets.runeIndex(text, at + cut) - index;
      written.add((pushed: pushed, index: index, deleted: runes));
      text = text.replaceRange(at, at + cut, pushed.inserted);
      shift += pushed.inserted.length - cut;
      deletedRunes += runes;
      insertedRunes += RuneOffsets.length(pushed.inserted);
    }

    binding.push(
      () {
        final embeds = _embeds;
        final content = embeds == null
            ? _writeEach(baseContent, baseText, written)
            : embeds.writeRegions(baseContent, baseText, written);
        _adopt(content, text, baseRunes - deletedRunes + insertedRunes);
      },
      isEcho: (dropped) => _content.echoes(
        dropped,
        deleted: deletedRunes,
        inserted: insertedRunes,
      ),
    );
    captureAnchors();
  }

  // Writes `regions` one by one, as one document update.
  C _writeEach(C base, String baseText, List<TextRegion> regions) {
    var content = base;
    var text = baseText;
    binding.document!.runInTransaction(() {
      for (final (:pushed, :index, :deleted) in regions) {
        content = _content.write(content, text, pushed, index, deleted);
        text = _content.textOf(content);
      }
    });
    return content;
  }

  // [delta] without the runes the field does not write, which also leave the
  // controller.
  TextDelta? _writableDelta(TextDelta? delta) {
    if (delta == null) {
      return null;
    }
    final typed = delta.inserted;
    final kept = _content.writable(typed);
    if (kept.length == typed.length) {
      return delta;
    }
    final start = delta.index;
    final end = start + typed.length;
    int map(int offset) {
      if (offset <= start) {
        return offset;
      }
      if (offset >= end) {
        return offset - typed.length + kept.length;
      }
      return start +
          _content.writable(typed.substring(0, offset - start)).length;
    }

    _showWritable(controller.text.replaceRange(start, end, kept), map);
    return TextDelta(index: start, deleted: delta.deleted, inserted: kept);
  }

  // Shows [text], the controller's without what the field does not write;
  // [map] moves an offset of the controller's text onto it.
  void _showWritable(String text, int Function(int offset) map) {
    final value = controller.value;
    final composing = value.composing.isValid
        ? TextRange(
            start: map(value.composing.start),
            end: map(value.composing.end),
          )
        : TextRange.empty;
    _dropping = true;
    try {
      controller.value = TextEditingValue(
        text: text,
        selection: value.selection.copyWith(
          baseOffset: map(value.selection.baseOffset),
          extentOffset: map(value.selection.extentOffset),
        ),
        composing: composing.isCollapsed ? TextRange.empty : composing,
      );
    } finally {
      _dropping = false;
    }
  }

  // Folds one reported move into the field.
  //
  // [content] is the handler's whole content when it had to be read; [reported]
  // is the delta when it did not. Exactly one of them is given.
  //
  // Done now rather than batched: taking a delta in costs the size of the edit,
  // so waiting would only make the field lag behind the CRDT.
  void _settle({C? content, D? reported}) {
    if (reported != null) {
      _content.remoteReported(reported);
    }
    final base = content ?? _committed;
    final runes = content != null
        ? _content.runesOf(content)
        : committedRunes + _content.netRunes(reported!);
    // Worked out from what the handler said it did, so the whole document is
    // never projected again for an edit of a few characters.
    final merged = reported == null ? base : _content.apply(base, reported);
    final mergedText = _content.textOf(merged);

    if (controller.text != _committedText) {
      // Uncommitted local edits (a composition in progress): commit them
      // first. The handler merges them with what just arrived, and the push
      // adopts the result.
      _pushLocalEdits(known: (content: merged, text: mergedText, runes: runes));
      return;
    }

    // After a read the delta and the controller's text belong to different
    // bases, so the caret cannot ride on them — [reported] is null there.
    _adopt(merged, mergedText, runes, reported: reported);
    captureAnchors();
  }

  // Replaces the controller text with [merged], keeping caret and selection
  // visually anchored (see `adoptedValue`).
  void _adopt(C merged, String mergedText, int runes, {D? reported}) {
    final old = controller.value;
    _commit(merged, mergedText, runes);
    if (old.text == mergedText) {
      // Same text: the content may still have new formats.
      _content.showFormats(merged);
      captureAnchors();
      return;
    }

    _content.show(
      adoptedValue(
        old: old,
        merged: mergedText,
        baseAnchor: anchors.base,
        extentAnchor: anchors.extent,
        resolve: _content.runeOf,
        mapReported: reported == null ? null : _content.offsetMapper(reported),
      ),
      merged,
    );
  }
}
