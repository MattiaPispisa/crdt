// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sameRuneAttributes compares the embeds too', () {
    List<RichTextSpan> spans(RichTextSpan embed) =>
        [RichTextSpan('ab'), embed, RichTextSpan('c')];
    final image = RichTextSpan.embed({'image': 'a.png'});

    expect(
      sameRuneAttributes(
        spans(image),
        spans(RichTextSpan.embed({'image': 'a.png'})),
      ),
      isTrue,
    );
    expect(
      sameRuneAttributes(
        spans(image),
        spans(RichTextSpan.embed({'image': 'b.png'})),
      ),
      isFalse,
    );
    expect(
      sameRuneAttributes(spans(image), spans(RichTextSpan('￼'))),
      isFalse,
    );
  });
}
