import 'package:crdt_lf/crdt_lf.dart';
import 'package:drift/drift.dart';

/// Type converter for [PeerId] objects.
///
/// This converter handles serialization and deserialization of [PeerId] objects
/// for Drift database storage.
class PeerIdConverter extends TypeConverter<PeerId, String> {
  const PeerIdConverter();

  @override
  PeerId fromSql(String fromDb) {
    return PeerId.parse(fromDb);
  }

  @override
  String toSql(PeerId value) {
    return value.id;
  }
} 