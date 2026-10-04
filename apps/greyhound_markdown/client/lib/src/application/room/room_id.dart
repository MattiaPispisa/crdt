import 'dart:math';

/// The characters a generated room id is drawn from. Lowercase and digits
/// only, so an id survives being copied out of a chat, typed by hand or read
/// aloud.
const _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

/// How many characters [generateRoomId] draws — 36^8, collisions are not a
/// concern at this scale.
const _generatedLength = 8;

/// The bounds a room id typed by hand has to fall within.
const _minLength = 3;
const _maxLength = 64;

/// Groups of letters and digits, optionally separated by single hyphens.
/// Hyphens are tolerated because people name their own rooms that way; nothing
/// this app generates contains one.
final _pattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

/// A fresh room id, drawn from a cryptographic source so two people creating a
/// room at the same moment do not land in the same one.
String generateRoomId() {
  final random = Random.secure();
  return String.fromCharCodes(
    List.generate(
      _generatedLength,
      (_) => _alphabet.codeUnitAt(random.nextInt(_alphabet.length)),
    ),
  );
}

/// [value] as a room id, or `null` when it cannot name a room.
///
/// Surrounding blanks and letter case are noise from copy/paste, so they are
/// normalized away rather than rejected: the id doubles as the CRDT
/// `documentId`, and two peers reaching the same room have to spell it
/// identically.
String? parseRoomId(String value) {
  final candidate = value.trim().toLowerCase();
  if (candidate.length < _minLength || candidate.length > _maxLength) {
    return null;
  }
  return _pattern.hasMatch(candidate) ? candidate : null;
}
