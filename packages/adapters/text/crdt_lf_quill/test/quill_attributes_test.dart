// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_quill/crdt_lf_quill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only inline keys other than link grow after their end', () {
    expect(quillMarkExpand('bold'), MarkExpand.after);
    expect(quillMarkExpand('color'), MarkExpand.after);
    expect(quillMarkExpand('my-custom-key'), MarkExpand.after);
    expect(quillMarkExpand('link'), MarkExpand.none);
    expect(quillMarkExpand('header'), MarkExpand.none);
    expect(quillMarkExpand('list'), MarkExpand.none);
  });

  test('scoped attributes keep block keys on a newline only', () {
    const attributes = {'bold': true, 'header': 1};

    expect(quillScopedAttributes(attributes, newline: true), {'header': 1});
    expect(quillScopedAttributes(attributes, newline: false), {'bold': true});
  });
}
