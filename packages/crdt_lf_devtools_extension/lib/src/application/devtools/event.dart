import 'package:vm_service/vm_service.dart';

extension CrdtLfEvent on Event {
  bool get isDocumentCreatedEvent => kind == 'crdt_lf:documents:created';
  bool get isDocumentChangedEvent => kind == 'crdt_lf:document:changed';
}
