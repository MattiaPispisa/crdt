import 'package:crdt_lf/crdt_lf.dart';

/// One operation kind a peer cannot decode.
///
/// Returned by [SyncCapabilities.missingFrom] to name the concrete reason a
/// build is refused, instead of a bare "not supported".
class MissingOperationKind {
  /// Constructor
  const MissingOperationKind({
    required this.handlerType,
    required this.kind,
  });

  /// The `Handler.handlerType` of the handler that owns the kind.
  final String handlerType;

  /// The kind byte (`OperationEnvelope.kind`) that cannot be decoded.
  final int kind;

  @override
  bool operator ==(Object other) =>
      other is MissingOperationKind &&
      other.handlerType == handlerType &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(handlerType, kind);

  @override
  String toString() => '$handlerType(kind $kind)';
}

/// The operation kinds a build can decode, keyed by `Handler.handlerType`.
///
/// An operation kind is defined by the handler that owns it. 
/// What a build can state is the set it knows, which is exactly the keys of
/// `Handler.operationDecoders`.
///
/// The client sends this in the handshake. The server compares it with its own
/// and refuses a client that would receive operations it cannot read — see
/// [missingFrom].
class SyncCapabilities {
  /// Creates capabilities from an explicit map.
  SyncCapabilities(Map<String, Set<int>> operationKinds)
      : operationKinds = Map.unmodifiable(
          operationKinds.map(
            (type, kinds) => MapEntry(type, Set<int>.unmodifiable(kinds)),
          ),
        );

  /// Reads the capabilities of [document] from the handlers registered on it.

  factory SyncCapabilities.of(CRDTDocument document) {
    final kinds = <String, Set<int>>{};

    for (final handler in document.registeredHandlers.values) {
      kinds
          .putIfAbsent(handler.handlerType, () => <int>{})
          .addAll(handler.operationDecoders.keys);
    }

    return SyncCapabilities(kinds);
  }

  /// Reads capabilities from the JSON form written by [toJson].
  factory SyncCapabilities.fromJson(Map<String, dynamic> json) {
    return SyncCapabilities(
      json.map(
        (type, kinds) => MapEntry(
          type,
          (kinds as List<dynamic>).map((k) => k as int).toSet(),
        ),
      ),
    );
  }

  /// The decodable kinds, keyed by `Handler.handlerType`. Unmodifiable.
  final Map<String, Set<int>> operationKinds;

  /// The kinds [other] can decode and this build cannot.
  ///
  /// Only handler types **both** sides declare are compared. A handler type
  /// missing here is not a fault: a peer legitimately syncs a document whose
  /// handlers it never opens, and lazy registration means it may not have
  /// opened them yet.
  ///
  /// An empty result means every operation [other] can write for a shared
  /// handler type is readable here.
  List<MissingOperationKind> missingFrom(SyncCapabilities other) {
    final missing = <MissingOperationKind>[];

    for (final entry in other.operationKinds.entries) {
      final mine = operationKinds[entry.key];
      if (mine == null) {
        continue;
      }
      for (final kind in entry.value) {
        if (!mine.contains(kind)) {
          missing.add(
            MissingOperationKind(handlerType: entry.key, kind: kind),
          );
        }
      }
    }

    return missing;
  }

  /// The JSON form: `{"CRDTFugueTextHandler": [0, 1, 2], ...}`.
  ///
  /// Kinds are sorted so the same capabilities always encode to the same JSON.
  Map<String, dynamic> toJson() {
    return operationKinds.map(
      (type, kinds) => MapEntry(type, kinds.toList()..sort()),
    );
  }

  @override
  String toString() => 'SyncCapabilities(${toJson()})';
}
