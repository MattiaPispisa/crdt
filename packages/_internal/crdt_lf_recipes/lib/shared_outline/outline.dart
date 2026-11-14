// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

// #docregion model
import 'package:crdt_lf/crdt_lf.dart';

/// Declares the kinds the outline is made of.
///
/// A peer rebuilds a chapter another peer wrote only when it knows its kinds.
void registerKinds(CRDTDocument document) {
  document
    ..register(CRDTListRefHandler.spec)
    ..register(CRDTMapRefHandler.spec)
    ..register(CRDTFugueTextHandler.spec);
}

/// The chapters of [document]: the root of the tree, under a fixed id.
CRDTListRefHandler chaptersOf(CRDTDocument document) {
  return document.handler(CRDTListRefHandler.spec, 'chapters');
}

/// Adds a chapter named [title] at the end of [chapters].
CRDTMapRefHandler addChapter(CRDTListRefHandler chapters, String title) {
  // One transaction: the other peers get the chapter with both its texts.
  return chapters.doc.runInTransaction(() {
    final chapter = chapters.insertChild(
      chapters.childRefs().length,
      CRDTMapRefHandler.spec,
    );
    chapter.child('title', CRDTFugueTextHandler.spec).insert(0, title);
    chapter.child('body', CRDTFugueTextHandler.spec);
    return chapter;
  });
}

/// The texts of one chapter, each merged character by character.
extension ChapterTexts on CRDTMapRefHandler {
  /// The title of the chapter.
  CRDTFugueTextHandler get title => child('title', CRDTFugueTextHandler.spec);

  /// The text of the chapter.
  CRDTFugueTextHandler get body => child('body', CRDTFugueTextHandler.spec);
}
// #enddocregion model
