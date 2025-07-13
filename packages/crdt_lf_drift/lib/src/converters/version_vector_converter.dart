import 'dart:convert';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:drift/drift.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Type converter for [VersionVector] objects.
///
/// This converter handles serialization and deserialization of [VersionVector] objects
/// for Drift database storage.
class VersionVectorConverter extends TypeConverter<VersionVector, String> {
  const VersionVectorConverter();

  @override
  VersionVector fromSql(String fromDb) {
    final Map<String, dynamic> data = json.decode(fromDb) as Map<String, dynamic>;
    final Map<PeerId, HybridLogicalClock> vector = {};
    
    for (final entry in data.entries) {
      final peerId = PeerId.parse(entry.key);
      final hlcData = entry.value as Map<String, dynamic>;
      final hlc = HybridLogicalClock(
        l: hlcData['l'] as int,
        c: hlcData['c'] as int,
      );
      vector[peerId] = hlc;
    }
    
    return VersionVector(vector);
  }

  @override
  String toSql(VersionVector value) {
    final Map<String, dynamic> data = {};
    
    for (final entry in value.entries) {
      data[entry.key.id] = {
        'l': entry.value.l,
        'c': entry.value.c,
      };
    }
    
    return json.encode(data);
  }
} 