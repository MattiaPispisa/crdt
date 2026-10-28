// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart' hide ChangeSource;
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_quill/src/crdt_quill_binding.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

const _measuredCycles = 100;

enum Check { off, length, full }

void _fill(CRDTFugueRichTextHandler handler, int size) {
  final line = '${'a' * 99}\n';
  final text = StringBuffer();
  while (text.length < size) {
    text.write(line);
  }
  handler.insert(0, text.toString().substring(0, size));
  for (var at = 0; at + 20 < size; at += 100) {
    handler.format(at, 10, 'bold', true, expand: MarkExpand.none);
  }
  for (var at = 50; at + 20 < size; at += 300) {
    handler.format(
      at,
      15,
      'link',
      'https://example.com',
      expand: MarkExpand.none,
    );
  }
}

class Editor {
  Editor(int size, Check check) {
    handler = CRDTFugueRichTextHandler(document, 'page');
    _fill(handler, size);
    quill = CrdtQuillBinding(controller);
    binding = CrdtEditorBinding<List<RichTextSpan>, RichTextDelta>(
      onRemoteDelta: quill.onRemoteDelta,
      onReset: quill.onReset,
      verifyProjection: check == Check.off ? null : quill.verifyProjection,
    );
    quill.binding = binding;
    binding.attach(document, 'page');
  }

  final CRDTDocument document = CRDTDocument();
  late final CRDTFugueRichTextHandler handler;
  final QuillController controller = QuillController.basic();
  late final CrdtQuillBinding quill;
  late final CrdtEditorBinding<List<RichTextSpan>, RichTextDelta> binding;

  void dispose() {
    binding.dispose();
    quill.dispose();
    controller.dispose();
    document.dispose();
  }
}

abstract class ProjectionCheckBenchmark extends AsyncFixedCycleTimedBenchmark {
  ProjectionCheckBenchmark(String what, this.size, this.check)
    : super(
        '$what, $size runes, check ${check.name}',
        measuredCycles: _measuredCycles,
      );

  final int size;

  final Check check;

  Editor? editor;

  @override
  Future<void> setup() async {
    editor?.dispose();
    editor = Editor(size, check);
    // The opening reset comes a microtask later; until then every event
    // waits behind it.
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> teardown() async {
    editor?.dispose();
    editor = null;
  }
}

class LocalKeystrokeBenchmark extends ProjectionCheckBenchmark {
  LocalKeystrokeBenchmark(int size, Check check)
    : super('Local keystroke', size, check);

  @override
  Future<void> run() async {
    final controller = editor!.controller;
    controller.replaceText(controller.document.length ~/ 2, 0, 'x', null);
  }
}

class RemoteDeltaBenchmark extends ProjectionCheckBenchmark {
  RemoteDeltaBenchmark(int size, Check check)
    : super('Remote insert', size, check);

  late CRDTDocument _peer;
  late CRDTFugueRichTextHandler _peerPage;

  @override
  Future<void> setup() async {
    await super.setup();
    _peer = CRDTDocument();
    _peerPage = CRDTFugueRichTextHandler(_peer, 'page');
    _peer.importChanges(editor!.document.exportChanges());
  }

  @override
  Future<void> teardown() async {
    await super.teardown();
    _peer.dispose();
  }

  @override
  Future<void> run() async {
    final document = editor!.document;
    _peerPage.insert(_peerPage.length ~/ 2, 'y');
    document.importChanges(
      _peer.exportChanges(fromVersionVector: document.getVersionVector()),
    );
  }
}

void main() {
  const timeout = Timeout(Duration(minutes: 20));

  tearDown(() => debugVerifyCrdtQuillProjection = true);

  for (final (name, create) in [
    ('local keystroke', LocalKeystrokeBenchmark.new),
    ('remote insert', RemoteDeltaBenchmark.new),
  ]) {
    test(name, () async {
      for (final size in [1000, 10000, 50000]) {
        for (final check in Check.values) {
          debugVerifyCrdtQuillProjection = check == Check.full;
          await create(size, check).report();
        }
      }
    }, timeout: timeout);
  }
}
