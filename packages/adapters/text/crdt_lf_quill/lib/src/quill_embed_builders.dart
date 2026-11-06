// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart' show richTextEmbedTypeKey;
import 'package:crdt_lf_quill/src/quill_converters.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// Builds the widget of a [crdtQuillEmbedType] embed that no builder shows.
///
/// [embed] is the handler data of the embed.
typedef CrdtQuillEmbedFallback =
    Widget Function(BuildContext context, Map<String, Object?> embed);

/// [builders] plus a builder for [crdtQuillEmbedType] embeds, for
/// `QuillEditorConfig.embedBuilders`.
///
/// A [crdtQuillEmbedType] embed with a `String` `type` and `src` (an image
/// or a video of `crdt_lf`, or an app kind) is shown by the builder of its
/// `type`, as the Quill embed `{type: src}` with the same style, which holds
/// the displayed width. Without a `type`, the first key of its map that has a
/// builder shows it, as `{key: map[key]}`. That builder:
///
/// - gets that one value, not the other fields of the map;
/// - draws inline, whatever its `expanded`;
/// - gets a node outside the document, at offset `0`.
///
/// Without such a builder, [fallback] builds it; by default a small box.
///
/// Pair it with [crdtQuillUnknownEmbedBuilder]: a peer can write an embed of
/// any type, and an editor with no builder for it throws in its build.
///
/// ```dart
/// QuillEditor.basic(
///   controller: controller,
///   config: QuillEditorConfig(
///     embedBuilders: crdtQuillEmbedBuilders([MyImageEmbedBuilder()]),
///     unknownEmbedBuilder: crdtQuillUnknownEmbedBuilder(),
///   ),
/// );
/// ```
List<EmbedBuilder> crdtQuillEmbedBuilders(
  Iterable<EmbedBuilder> builders, {
  CrdtQuillEmbedFallback? fallback,
}) {
  final list = List<EmbedBuilder>.of(builders);
  return [...list, _WrappedEmbedBuilder(list, fallback ?? _defaultFallback)];
}

/// A builder for `QuillEditorConfig.unknownEmbedBuilder` that shows every
/// embed no other builder takes.
///
/// [fallback] builds it, as in [crdtQuillEmbedBuilders]. Alone, it is enough
/// for an editor that a peer's embed can never break:
///
/// ```dart
/// QuillEditorConfig(unknownEmbedBuilder: crdtQuillUnknownEmbedBuilder())
/// ```
EmbedBuilder crdtQuillUnknownEmbedBuilder({CrdtQuillEmbedFallback? fallback}) =>
    _UnknownEmbedBuilder(fallback ?? _defaultFallback);

class _UnknownEmbedBuilder extends EmbedBuilder {
  _UnknownEmbedBuilder(this._fallback);

  final CrdtQuillEmbedFallback _fallback;

  @override
  String get key => 'crdt_lf_unknown';

  // Inline fits both an inline and a block delegate.
  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final embed = embedContext.node.value;
    return _fallback(
      context,
      embed.type == crdtQuillEmbedType
          ? _wrapped(embed)
          : richTextEmbed({embed.type: embed.data}),
    );
  }
}

class _WrappedEmbedBuilder extends EmbedBuilder {
  _WrappedEmbedBuilder(this._builders, this._fallback);

  final List<EmbedBuilder> _builders;
  final CrdtQuillEmbedFallback _fallback;

  @override
  String get key => crdtQuillEmbedType;

  // Inline fits both an inline and a block delegate.
  @override
  bool get expanded => false;

  @override
  String toPlainText(Embed node) {
    final native = _native(node);
    return native == null
        ? super.toPlainText(node)
        : native.builder.toPlainText(native.node);
  }

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final native = _native(embedContext.node);
    if (native == null) {
      return _fallback(context, _wrapped(embedContext.node.value));
    }
    return native.builder.build(
      context,
      _NativeEmbedContext(embedContext, native.node),
    );
  }

  // The builder of the wrapped map's type, or else of its first key that has
  // one, and the node it shows.
  ({EmbedBuilder builder, Embed node})? _native(Embed node) {
    final wrapped = _wrapped(node.value);
    final type = wrapped[richTextEmbedTypeKey];
    if (type is String) {
      final src = wrapped[embedSrcKey];
      return src is String ? _delegate(node, type, src) : null;
    }
    for (final MapEntry(:key, :value) in wrapped.entries) {
      final native = _delegate(node, key, value);
      if (native != null) {
        return native;
      }
    }
    return null;
  }

  ({EmbedBuilder builder, Embed node})? _delegate(
    Embed node,
    String type,
    Object? value,
  ) {
    for (final builder in _builders) {
      if (builder.key == type) {
        final native = Embed(Embeddable(type, value))..applyStyle(node.style);
        return (builder: builder, node: native);
      }
    }
    return null;
  }
}

// The context of the wrapped embed, with the native node in its place.
class _NativeEmbedContext implements EmbedContext {
  _NativeEmbedContext(this._context, this.node);

  final EmbedContext _context;

  @override
  final Embed node;

  @override
  QuillController get controller => _context.controller;

  @override
  bool get readOnly => _context.readOnly;

  @override
  bool get inline => _context.inline;

  @override
  TextStyle get textStyle => _context.textStyle;
}

// The map a wrapped embed holds; never throws, whatever the data.
Map<String, Object?> _wrapped(Embeddable embed) => switch (embed.data) {
  final Map<dynamic, dynamic> map => {
    for (final entry in map.entries) '${entry.key}': entry.value,
  },
  final data => {embed.type: data},
};

Widget _defaultFallback(BuildContext context, Map<String, Object?> embed) {
  final color =
      DefaultTextStyle.of(context).style.color ?? const Color(0xFF9E9E9E);
  return Container(
    width: 16,
    height: 16,
    decoration: BoxDecoration(
      border: Border.all(color: color.withValues(alpha: 0.4)),
      borderRadius: BorderRadius.circular(3),
    ),
  );
}
