import 'dart:convert';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:drift/drift.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Type converter for [OperationId] objects.
///
/// This converter handles serialization and deserialization of [OperationId] objects
/// for Drift database storage.
class OperationIdConverter extends TypeConverter<OperationId, String> {
  const OperationIdConverter();

  @override
  OperationId fromSql(String fromDb) {
    final Map<String, dynamic> data = json.decode(fromDb) as Map<String, dynamic>;
    
    final peerIdStr = data['peerId'] as String;
    final hlcData = data['hlc'] as Map<String, dynamic>;
    
    final peerId = PeerId.parse(peerIdStr);
    final hlc = HybridLogicalClock(
      l: hlcData['l'] as int,
      c: hlcData['c'] as int,
    );
    
    return OperationId(peerId, hlc);
  }

  @override
  String toSql(OperationId value) {
    return json.encode({
      'peerId': value.peerId.id,
      'hlc': {
        'l': value.hlc.l,
        'c': value.hlc.c,
      },
    });
  }
} 