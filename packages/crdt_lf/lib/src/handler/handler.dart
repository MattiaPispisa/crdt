import 'package:crdt_lf/crdt_lf.dart';

abstract class Handler with SnapshotProvider {
  Handler(CRDTDocument doc) {
    doc.registerHandler(this);
  }

  /// The ID of the handler
  String get id;
}
