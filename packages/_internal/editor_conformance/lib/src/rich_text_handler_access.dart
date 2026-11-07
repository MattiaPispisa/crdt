// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:editor_conformance/src/harness.dart';

/// A [CRDTFugueRichTextHandler] seen by the suite.
class RichTextHandlerAccess implements ConformanceHandler {
  /// Wraps [handler].
  RichTextHandlerAccess(this.handler);

  /// The wrapped handler.
  final CRDTFugueRichTextHandler handler;

  @override
  Handler<dynamic> get raw => handler;

  @override
  String get text => handler.text;

  @override
  int get length => handler.length;

  @override
  void insert(int index, String text) => handler.insert(index, text);

  @override
  void delete(int index, int count) => handler.delete(index, count);

  @override
  void insertEmbed(int index, Map<String, Object?> embed) =>
      handler.insertEmbed(index, embed);

  @override
  void updateEmbed(int index, Map<String, Object?> embed) =>
      handler.updateEmbed(index, embed);

  @override
  Map<String, Object?>? embedAt(int index) {
    var at = 0;
    for (final span in handler.value) {
      at += RuneOffsets.length(span.text);
      if (index < at) {
        return span.embed;
      }
    }
    return null;
  }

  @override
  void format(int index, int count, String key, Object? value) =>
      handler.format(index, count, key, value);

  @override
  Map<String, Object?> attributesAt(int index) => handler.attributesAt(index);

  @override
  Stream<Object?> watch() => handler.watch();

  @override
  FugueElementID stablePositionAt(int index) => handler.stablePositionAt(index);

  @override
  int? indexOfStablePosition(FugueElementID position) =>
      handler.indexOfStablePosition(position);
}
