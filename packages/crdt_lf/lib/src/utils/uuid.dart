import 'dart:math';

/// Cryptographically-secure source used to mint random identifiers.
final Random _random = Random.secure();

/// Generates a random RFC 4122 version 4 UUID string.
///
/// Used both by `PeerId` (peer identity) and for generic unique identifiers
/// that are *not* tied to a peer — e.g. document ids and dynamically-created
/// handler ids (`CRDTDocument.newHandlerId`).
String generateUuid() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));

  // Set version to 4 (random) and variant to 1 (RFC 4122).
  bytes[6] = (bytes[6] & 0x0F) | 0x40;
  bytes[8] = (bytes[8] & 0x3F) | 0x80;

  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
