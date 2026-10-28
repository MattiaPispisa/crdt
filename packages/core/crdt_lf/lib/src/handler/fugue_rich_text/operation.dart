// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'handler.dart';

class _FugueRichTextMarkOperation extends Operation {
  _FugueRichTextMarkOperation({
    required this.key,
    required this.value,
    required this.start,
    required this.end,
    required super.id,
    required super.type,
  });

  factory _FugueRichTextMarkOperation.fromHandler(
    CRDTFugueRichTextHandler handler, {
    required String key,
    required Object? value,
    required _Anchor start,
    required _Anchor end,
  }) {
    return _FugueRichTextMarkOperation(
      id: handler.id,
      type: handler.markType,
      key: key,
      value: value,
      start: start,
      end: end,
    );
  }

  factory _FugueRichTextMarkOperation.fromBodyBytes(
    CRDTFugueRichTextHandler handler,
    Uint8List body,
  ) {
    final mark = _MarkBody.read(body, 0);
    return _FugueRichTextMarkOperation(
      id: handler.id,
      type: handler.markType,
      key: mark.key,
      value: mark.value,
      start: mark.start,
      end: mark.end,
    );
  }

  final String key;
  final Object? value;
  final _Anchor start;
  final _Anchor end;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    _MarkBody.write(out, key: key, value: value, start: start, end: end);
    return out.toBytes();
  }
}
