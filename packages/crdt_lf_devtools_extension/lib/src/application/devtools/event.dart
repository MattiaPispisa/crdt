import 'package:vm_service/vm_service.dart';

/// Extension on [Event] to check if it is a CRDT LF event
extension CrdtLfEvent on Event {
  bool get isDocumentCreatedEvent => extensionKind == 'crdt_lf:documents:created';
  bool get isDocumentChangedEvent => extensionKind == 'crdt_lf:document:changed';
}
