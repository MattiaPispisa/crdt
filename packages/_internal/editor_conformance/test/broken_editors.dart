// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

/// Editors that break one rule of the contract each.
///
/// **These tests are meant to fail.** The file has no `_test` suffix, so
/// `flutter test` never picks it up on its own: `conformance_test.dart` runs
/// it in a subprocess and checks that each editor made the clauses it breaks
/// go red. A clause that stays green here checks nothing, and every binding
/// passing it is passing on nothing.
library;

import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:editor_conformance/editor_conformance.dart';
import 'package:flutter/widgets.dart';

import 'reference_editor.dart';

void main() {
  editor('never writes a deletion', _NeverDeletes.new);
  editor('counts code units as runes', _CountsCodeUnits.new);
  editor('rebuilds on a remote change', _Rebuilds.new);
  editor('leaves the caret at its offset on a remote change', _FixedCaret.new);
  editor('shifts the caret by how much the text grew', _ShiftedCaret.new);
  editor('ignores a remote change that shortens the text', _KeepsLonger.new);
  editor('remembers what it shows in one place for every editor', _Shared.new);
  editor('ignores the deletion of its handler', _IgnoresDeletion.new);
  editor('binds a handler of any type', _BindsAnything.new);
  editor('publishes anchors without the focus', _PublishesUnfocused.new);
  editor('does not publish after its own edit', _SilentEdits.new);
  editor('publishes on every remote change', _PublishesAgain.new);
  editor('commits while composing', _CommitsComposing.new);
  editor('drops the pending composition on a remote change', _DropsPending.new);
  editor('commits a composition at its old index', _OldIndexes.new);
  editor('skips an embed when it counts positions', _SkipsEmbeds.new);
  editor('writes a typed U+FFFC', _WritesObjectReplacement.new);
  editor('stops following after a write made inside its own', _Stuck.new);
  editor('keeps its anchors during a composition', _AnchorsComposing.new);
  editor('maps the caret through an undo like a remote change', _NoStep.new);
  editor('writes without its origin', _NoOrigin.new);
  editor('undoes with its own text history', _OwnHistory.new);
  editor('moves the caret on an undo that changes nothing', _CaretHome.new);
  editor('formats inside the typing step', _OpenStep.new);
}

/// Runs the suite against the editor [create] makes.
void editor(String name, ReferenceBinding Function() create) {
  runEditorConformanceTests(name, () => ReferenceHarness(create));
}

class _NeverDeletes extends ReferenceBinding {
  @override
  void writeDelete(int index) {}
}

class _CountsCodeUnits extends ReferenceBinding {
  @override
  int runeIndex(String text, int offset) => offset;

  @override
  int offsetOf(String text, int rune) => min(rune, text.length);
}

class _Rebuilds extends ReferenceBinding {
  @override
  void onHandlerChanged(Object? event) {
    super.onHandlerChanged(event);
    rebuild();
  }
}

class _FixedCaret extends ReferenceBinding {
  @override
  TextSelection mapSelection(String text) {
    final selection = controller.selection;
    return TextSelection(
      baseOffset: min(selection.baseOffset, text.length),
      extentOffset: min(selection.extentOffset, text.length),
    );
  }
}

class _ShiftedCaret extends ReferenceBinding {
  @override
  TextSelection mapSelection(String text) {
    final selection = controller.selection;
    final grown = text.length - controller.text.length;
    return TextSelection(
      baseOffset: (selection.baseOffset + grown).clamp(-1, text.length),
      extentOffset: (selection.extentOffset + grown).clamp(-1, text.length),
    );
  }
}

class _KeepsLonger extends ReferenceBinding {
  @override
  void onHandlerChanged(Object? event) {
    if (!writing && handler.text.length < controller.text.length) {
      return;
    }
    super.onHandlerChanged(event);
  }
}

class _Shared extends ReferenceBinding {
  // Right with one editor on screen, wrong with two.
  static String _shown = '';

  @override
  String get shown => _shown;

  @override
  void attach(CRDTDocument document, String id) {
    super.attach(document, id);
    _shown = controller.text;
    controller.addListener(() => _shown = controller.text);
  }
}

class _IgnoresDeletion extends ReferenceBinding {
  @override
  void onDocumentUpdated() {}
}

class _BindsAnything extends ReferenceBinding {
  @override
  CRDTFugueRichTextHandler resolve(CRDTDocument document, String id) {
    final found = document.registeredHandlers[id];
    return found is CRDTFugueRichTextHandler
        ? found
        : CRDTFugueRichTextHandler(
            CRDTDocument(peerId: PeerId.generate()),
            id,
          );
  }
}

class _PublishesUnfocused extends ReferenceBinding {
  @override
  bool get publishes => pending == null;
}

class _SilentEdits extends ReferenceBinding {
  bool _committing = false;

  @override
  void commit() {
    _committing = true;
    try {
      super.commit();
    } finally {
      _committing = false;
    }
  }

  @override
  void publishAnchors() {
    if (!_committing) {
      super.publishAnchors();
    }
  }
}

class _PublishesAgain extends ReferenceBinding {
  @override
  void onHandlerChanged(Object? event) {
    if (!writing) {
      published = (null, null);
    }
    super.onHandlerChanged(event);
  }
}

class _CommitsComposing extends ReferenceBinding {
  @override
  bool isComposing(TextEditingValue value) => false;
}

class _DropsPending extends ReferenceBinding {
  @override
  void onHandlerChanged(Object? event) {
    if (!writing) {
      pending = null;
    }
    super.onHandlerChanged(event);
  }
}

class _OldIndexes extends ReferenceBinding {
  @override
  List<int> deletedIndexes(Edit edit) => [
        for (var index = edit.start + edit.count - 1;
            index >= edit.start;
            index--)
          if (index < handler.length) index,
      ];

  @override
  int insertIndex(Edit edit) => min(edit.start, handler.length);
}

class _SkipsEmbeds extends ReferenceBinding {
  @override
  int runeIndex(String text, int offset) {
    final rune = super.runeIndex(text, offset);
    final before = text.substring(0, super.offsetOf(text, rune));
    return rune - '￼'.allMatches(before).length;
  }
}

class _WritesObjectReplacement extends ReferenceBinding {
  @override
  String writable(String inserted) => inserted;
}

class _Stuck extends ReferenceBinding {
  // Raised by a change of another origin heard inside a write.
  bool _stuck = false;

  @override
  set writing(bool value) => super.writing = value || _stuck;

  @override
  void onHandlerChanged(Object? event) {
    if (writing && event is HandlerDelta && event.origin != origin) {
      _stuck = true;
    }
    super.onHandlerChanged(event);
  }
}

class _AnchorsComposing extends ReferenceBinding {
  @override
  bool get publishes => focusNode.hasFocus;
}

class _NoStep extends ReferenceBinding {
  @override
  int? stepCaret(String before, String after) => null;
}

class _NoOrigin extends ReferenceBinding {
  @override
  Object? get origin => null;
}

class _OwnHistory extends ReferenceBinding {
  final List<String> _history = [];

  @override
  void commit() {
    _history.add(handler.text);
    super.commit();
  }

  @override
  void undo() {
    if (_history.isNotEmpty) {
      controller.text = _history.removeLast();
    }
  }

  @override
  void redo() {}
}

class _CaretHome extends ReferenceBinding {
  @override
  int? stepCaret(String before, String after) =>
      super.stepCaret(before, after) ?? 0;
}

class _OpenStep extends ReferenceBinding {
  @override
  void closeUndoStep() {}
}
