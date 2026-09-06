import 'dart:convert';

/// The box name of [documentId] under [prefix].
///
/// Hive names a box by a string and this adapter gives every document a box of
/// its own, so the document id ends up in that name. It cannot go in as it is:
/// Hive lower-cases every box name and asserts it is ASCII and at most 255
/// characters (`hive_impl.dart`). Left alone, `Note` and `note` would share
/// one box and merge into one document, and any id with an accent or an emoji
/// would trip the assert.
///
/// So the id is escaped. Everything outside `a-z`, `0-9` and `-` becomes `~`
/// plus the two hex digits of the byte, over the UTF-8 bytes of the id. That
/// makes the mapping one-to-one — two different ids can never give one name —
/// and reversible, which matters when reading a box list by hand.
///
/// **An id that was already safe is left exactly as it was**: lower-case
/// ASCII letters, digits and `-` map to themselves. A store written by an
/// earlier version of this adapter therefore keeps working unchanged for those
/// ids, and only the ones that were already ambiguous or already broken move.
///
/// `_` is escaped as well, because [prefix] is joined with one: without that,
/// document `b` under a prefix of `changes_a` and document `a_b` under
/// `changes` would name the same box.
String documentBoxNameFor(String prefix, String documentId) {
  return '${prefix}_${escapeForBoxName(documentId)}';
}

/// The escaped form of [documentId]. See [documentBoxNameFor].
///
/// A lone surrogate in [documentId] becomes U+FFFD, the way `utf8.encode`
/// leaves it. Two ids that differ only there would collide; a document id is
/// not text a user types, so that is a limit rather than a risk.
String escapeForBoxName(String documentId) {
  final out = StringBuffer();

  for (final byte in utf8.encode(documentId)) {
    final safe = (byte >= 0x61 && byte <= 0x7a) || // a-z
        (byte >= 0x30 && byte <= 0x39) || // 0-9
        byte == 0x2d; // -
    if (safe) {
      out.writeCharCode(byte);
    } else {
      out
        ..write('~')
        ..write(byte.toRadixString(16).padLeft(2, '0'));
    }
  }

  return out.toString();
}
