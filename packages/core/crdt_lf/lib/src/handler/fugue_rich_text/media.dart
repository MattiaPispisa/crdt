// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/utils/embed_data.dart';

/// The key of embed data that names its kind, such as `'image'`.
///
/// The convention for every embed, app-defined ones included: a reader
/// switches on it, and treats an unknown kind as a generic embed.
const String richTextEmbedTypeKey = 'type';

/// The mark that holds the displayed width of a media embed, in logical px.
///
/// A mark, so concurrent resizes resolve like formats. The displayed height
/// follows the intrinsic ratio.
const String richTextDisplayWidthKey = 'displayWidth';

/// An image embed of a [CRDTFugueRichTextHandler].
///
/// {@template rich_text_media}
/// The facts of the file live in the embed data, replaced as a whole with
/// [CRDTFugueRichTextHandler.updateEmbed]. What a user changes later lives in
/// marks: the displayed width ([richTextDisplayWidthKey]), and the `align` of
/// the `'\n'` of a block item. Keep the file outside the document and give its
/// address: [src] is a URL or an address the app resolves, such as
/// `sha256:…`.
/// {@endtemplate}
///
/// [fromEmbed] and [toEmbed] convert from and to embed data. Keys this class
/// does not know are kept, so data another app wrote survives a [copyWith].
final class RichTextImage {
  /// Creates an image.
  ///
  /// Throws an [ArgumentError] for an empty [src], a `data:` URI, or a
  /// [width] and [height] that are not both set above 0.
  factory RichTextImage({
    required Uri src,
    String? alt,
    String? title,
    int? width,
    int? height,
    String? mime,
  }) =>
      RichTextImage._(
        src: src,
        srcText: src.toString(),
        alt: alt,
        title: title,
        width: width,
        height: height,
        mime: mime,
        extra: const {},
      );

  RichTextImage._({
    required this.src,
    required String srcText,
    required this.alt,
    required this.title,
    required this.width,
    required this.height,
    required this.mime,
    required Map<String, Object?> extra,
  })  : _srcText = srcText,
        _extra = extra {
    _checkUri(srcText, src, 'src');
    _checkSize(width, height);
  }

  /// The [richTextEmbedTypeKey] value of an image.
  static const String type = 'image';

  static const Set<String> _keys = {
    richTextEmbedTypeKey,
    'src',
    'alt',
    'title',
    'width',
    'height',
    'mime',
  };

  /// The image from the embed data [embed], or `null` when it is not a valid
  /// image.
  ///
  /// Never throws. A known key with a value of the wrong type, `null`
  /// included, gives `null`: in the data, a field that is not given has no
  /// key.
  static RichTextImage? fromEmbed(Map<String, Object?> embed) {
    if (embed[richTextEmbedTypeKey] != type) {
      return null;
    }
    final read = _Reader(embed);
    final src = read.uri('src');
    final alt = read.string('alt');
    final title = read.string('title');
    final width = read.size('width');
    final height = read.size('height');
    final mime = read.string('mime');
    if (!read.valid || src == null || !_validSize(width, height)) {
      return null;
    }
    return RichTextImage._(
      src: src.uri,
      srcText: src.text,
      alt: alt,
      title: title,
      width: width,
      height: height,
      mime: mime,
      extra: read.extra(_keys),
    );
  }

  /// The address of the image.
  final Uri src;
  final String _srcText;

  /// The text alternative; `''` for a decorative image, `null` when not
  /// given.
  final String? alt;

  /// The title of the image; `null` when not given.
  final String? title;

  /// The intrinsic width in px, set together with [height]; `null` when not
  /// given.
  final int? width;

  /// The intrinsic height in px, set together with [width]; `null` when not
  /// given.
  final int? height;

  /// The media type, such as `image/png`; `null` when not given.
  final String? mime;

  final Map<String, Object?> _extra;

  /// A copy of this image with the given fields replaced.
  ///
  /// A `null` argument keeps the field: build a new image to clear one.
  RichTextImage copyWith({
    Uri? src,
    String? alt,
    String? title,
    int? width,
    int? height,
    String? mime,
  }) =>
      RichTextImage._(
        src: src ?? this.src,
        srcText: src?.toString() ?? _srcText,
        alt: alt ?? this.alt,
        title: title ?? this.title,
        width: width ?? this.width,
        height: height ?? this.height,
        mime: mime ?? this.mime,
        extra: _extra,
      );

  /// The embed data of this image.
  ///
  /// `fromEmbed(data)!.toEmbed()` equals `data`.
  Map<String, Object?> toEmbed() => {
        richTextEmbedTypeKey: type,
        'src': _srcText,
        if (alt != null) 'alt': alt,
        if (title != null) 'title': title,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (mime != null) 'mime': mime,
        ..._extra,
      };

  @override
  bool operator ==(Object other) =>
      other is RichTextImage && sameEmbed(other.toEmbed(), toEmbed());

  @override
  int get hashCode => hashEmbed(toEmbed());

  @override
  String toString() => 'RichTextImage(${toEmbed()})';
}

/// A video embed of a [CRDTFugueRichTextHandler].
///
/// {@macro rich_text_media}
///
/// [fromEmbed] and [toEmbed] convert from and to embed data, as for
/// [RichTextImage].
final class RichTextVideo {
  /// Creates a video.
  ///
  /// Throws an [ArgumentError] for an empty [src] or [poster], a `data:` URI,
  /// or a [width] and [height] that are not both set above 0.
  factory RichTextVideo({
    required Uri src,
    Uri? poster,
    String? title,
    int? width,
    int? height,
    String? mime,
  }) =>
      RichTextVideo._(
        src: src,
        srcText: src.toString(),
        poster: poster,
        posterText: poster?.toString(),
        title: title,
        width: width,
        height: height,
        mime: mime,
        extra: const {},
      );

  RichTextVideo._({
    required this.src,
    required String srcText,
    required this.poster,
    required String? posterText,
    required this.title,
    required this.width,
    required this.height,
    required this.mime,
    required Map<String, Object?> extra,
  })  : _srcText = srcText,
        _posterText = posterText,
        _extra = extra {
    _checkUri(srcText, src, 'src');
    if (posterText != null) {
      _checkUri(posterText, poster!, 'poster');
    }
    _checkSize(width, height);
  }

  /// The [richTextEmbedTypeKey] value of a video.
  static const String type = 'video';

  static const Set<String> _keys = {
    richTextEmbedTypeKey,
    'src',
    'poster',
    'title',
    'width',
    'height',
    'mime',
  };

  /// The video from the embed data [embed], or `null` when it is not a valid
  /// video; never throws, as [RichTextImage.fromEmbed].
  static RichTextVideo? fromEmbed(Map<String, Object?> embed) {
    if (embed[richTextEmbedTypeKey] != type) {
      return null;
    }
    final read = _Reader(embed);
    final src = read.uri('src');
    final poster = read.uri('poster');
    final title = read.string('title');
    final width = read.size('width');
    final height = read.size('height');
    final mime = read.string('mime');
    if (!read.valid || src == null || !_validSize(width, height)) {
      return null;
    }
    return RichTextVideo._(
      src: src.uri,
      srcText: src.text,
      poster: poster?.uri,
      posterText: poster?.text,
      title: title,
      width: width,
      height: height,
      mime: mime,
      extra: read.extra(_keys),
    );
  }

  /// The address of the video.
  final Uri src;
  final String _srcText;

  /// The address of the image shown before the video plays; `null` when not
  /// given.
  final Uri? poster;
  final String? _posterText;

  /// The title of the video, its accessible name; `null` when not given.
  final String? title;

  /// The intrinsic width in px, set together with [height]; `null` when not
  /// given.
  final int? width;

  /// The intrinsic height in px, set together with [width]; `null` when not
  /// given.
  final int? height;

  /// The media type, such as `video/mp4`; `null` when not given.
  final String? mime;

  final Map<String, Object?> _extra;

  /// A copy of this video with the given fields replaced.
  ///
  /// A `null` argument keeps the field: build a new video to clear one.
  RichTextVideo copyWith({
    Uri? src,
    Uri? poster,
    String? title,
    int? width,
    int? height,
    String? mime,
  }) =>
      RichTextVideo._(
        src: src ?? this.src,
        srcText: src?.toString() ?? _srcText,
        poster: poster ?? this.poster,
        posterText: poster?.toString() ?? _posterText,
        title: title ?? this.title,
        width: width ?? this.width,
        height: height ?? this.height,
        mime: mime ?? this.mime,
        extra: _extra,
      );

  /// The embed data of this video.
  ///
  /// `fromEmbed(data)!.toEmbed()` equals `data`.
  Map<String, Object?> toEmbed() => {
        richTextEmbedTypeKey: type,
        'src': _srcText,
        if (_posterText != null) 'poster': _posterText,
        if (title != null) 'title': title,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (mime != null) 'mime': mime,
        ..._extra,
      };

  @override
  bool operator ==(Object other) =>
      other is RichTextVideo && sameEmbed(other.toEmbed(), toEmbed());

  @override
  int get hashCode => hashEmbed(toEmbed());

  @override
  String toString() => 'RichTextVideo(${toEmbed()})';
}

/// Inserts media embeds into a [CRDTFugueRichTextHandler].
extension RichTextMediaInsert on CRDTFugueRichTextHandler {
  /// Inserts an image at [index], **in runes**, inline unless [block].
  ///
  /// {@template rich_text_insert_media}
  /// [displayWidth] is written as the [richTextDisplayWidthKey] mark.
  /// Inline, [attributes] and [inherit] work as in
  /// [CRDTFugueRichTextHandler.insertEmbed]. With [block], the embed gets its
  /// own `'\n'` right after it, which holds [attributes] as block attributes
  /// (such as `{'align': 'center'}`): one transaction, so one undo step.
  ///
  /// Throws before it writes: a [RangeError] for an [index] outside
  /// `0..length`, and an [ArgumentError] for the fields as the constructor
  /// does, or for a [displayWidth] that is not finite and above 0.
  /// {@endtemplate}
  ///
  /// ```dart
  /// text.insertImage(
  ///   0,
  ///   Uri.parse('https://example.com/cat.png'),
  ///   alt: 'A cat',
  ///   width: 1200,
  ///   height: 800,
  ///   displayWidth: 320,
  /// );
  /// ```
  void insertImage(
    int index,
    Uri src, {
    String? alt,
    String? title,
    int? width,
    int? height,
    String? mime,
    num? displayWidth,
    bool block = false,
    Map<String, Object?> attributes = const {},
    bool inherit = true,
  }) {
    final image = RichTextImage(
      src: src,
      alt: alt,
      title: title,
      width: width,
      height: height,
      mime: mime,
    );
    _insertMedia(
      index,
      image.toEmbed(),
      displayWidth: displayWidth,
      block: block,
      attributes: attributes,
      inherit: inherit,
    );
  }

  /// Inserts a video at [index], **in runes**, as a block unless [block] is
  /// `false`.
  ///
  /// {@macro rich_text_insert_media}
  void insertVideo(
    int index,
    Uri src, {
    Uri? poster,
    String? title,
    int? width,
    int? height,
    String? mime,
    num? displayWidth,
    bool block = true,
    Map<String, Object?> attributes = const {},
    bool inherit = true,
  }) {
    final video = RichTextVideo(
      src: src,
      poster: poster,
      title: title,
      width: width,
      height: height,
      mime: mime,
    );
    _insertMedia(
      index,
      video.toEmbed(),
      displayWidth: displayWidth,
      block: block,
      attributes: attributes,
      inherit: inherit,
    );
  }

  void _insertMedia(
    int index,
    Map<String, Object?> embed, {
    required num? displayWidth,
    required bool block,
    required Map<String, Object?> attributes,
    required bool inherit,
  }) {
    if (displayWidth != null && !(displayWidth.isFinite && displayWidth > 0)) {
      throw ArgumentError.value(
        displayWidth,
        'displayWidth',
        'must be a finite number above 0',
      );
    }
    final size = {
      if (displayWidth != null) richTextDisplayWidthKey: displayWidth,
    };
    if (!block) {
      insertEmbed(
        index,
        embed,
        attributes: {...attributes, ...size},
        inherit: inherit,
      );
      return;
    }

    // The '\n' goes first: it checks the index and [attributes] before anything
    // is written, and the embed checked here then cannot throw.
    checkEmbed(embed);
    doc.runInTransaction(() {
      insert(index, '\n', attributes: attributes, inherit: inherit);
      insertEmbed(index, embed, attributes: size, inherit: inherit);
    });
  }
}

/// Reads media embeds from a [RichTextSpan].
extension RichTextMediaSpan on RichTextSpan {
  /// The image of this span, or `null` when it holds no valid image.
  RichTextImage? get image {
    final data = embed;
    return data == null ? null : RichTextImage.fromEmbed(data);
  }

  /// The video of this span, or `null` when it holds no valid video.
  RichTextVideo? get video {
    final data = embed;
    return data == null ? null : RichTextVideo.fromEmbed(data);
  }

  /// The [richTextDisplayWidthKey] mark of this span; `null` when unset.
  num? get displayWidth {
    final value = attributes[richTextDisplayWidthKey];
    return value is num ? value : null;
  }
}

String? _uriProblem(String text, Uri uri) {
  if (text.isEmpty) {
    return 'cannot be empty';
  }
  if (uri.isScheme('data')) {
    return 'cannot be a data: URI, which would stay in the history forever';
  }
  return null;
}

void _checkUri(String text, Uri uri, String name) {
  final problem = _uriProblem(text, uri);
  if (problem != null) {
    throw ArgumentError.value(text, name, problem);
  }
}

bool _validSize(int? width, int? height) =>
    (width == null) == (height == null) &&
    (width == null || (width > 0 && height! > 0));

void _checkSize(int? width, int? height) {
  if (!_validSize(width, height)) {
    throw ArgumentError(
      'width and height must be both null or both above 0, '
      'got $width and $height',
    );
  }
}

// Reads the known keys of embed data; [valid] turns false at the first key
// that holds a value of the wrong type.
final class _Reader {
  _Reader(this._embed);

  final Map<String, Object?> _embed;
  bool valid = true;

  String? string(String key) {
    if (!_embed.containsKey(key)) {
      return null;
    }
    final value = _embed[key];
    if (value is String) {
      return value;
    }
    valid = false;
    return null;
  }

  // On the web 12.0 is an int: a size is checked by value.
  int? size(String key) {
    if (!_embed.containsKey(key)) {
      return null;
    }
    final value = _embed[key];
    if (value is num &&
        value.abs() <= maxEmbedInt &&
        value == value.truncate()) {
      return value.toInt();
    }
    valid = false;
    return null;
  }

  ({Uri uri, String text})? uri(String key) {
    final text = string(key);
    if (text == null) {
      return null;
    }
    final uri = Uri.tryParse(text);
    if (uri == null || _uriProblem(text, uri) != null) {
      valid = false;
      return null;
    }
    return (uri: uri, text: text);
  }

  Map<String, Object?> extra(Set<String> known) => Map.unmodifiable({
        for (final entry in _embed.entries)
          if (!known.contains(entry.key)) entry.key: entry.value,
      });
}
