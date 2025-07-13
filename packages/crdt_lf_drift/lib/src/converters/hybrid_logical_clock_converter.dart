import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Type converter for [HybridLogicalClock] objects.
///
/// This converter handles serialization and deserialization of [HybridLogicalClock] objects
/// for Drift database storage.
class HybridLogicalClockConverter extends TypeConverter<HybridLogicalClock, String> {
  const HybridLogicalClockConverter();

  @override
  HybridLogicalClock fromSql(String fromDb) {
    final Map<String, dynamic> data = json.decode(fromDb);
    return HybridLogicalClock(
      l: data['l'] as int,
      c: data['c'] as int,
    );
  }

  @override
  String toSql(HybridLogicalClock value) {
    return json.encode({
      'l': value.l,
      'c': value.c,
    });
  }
} 