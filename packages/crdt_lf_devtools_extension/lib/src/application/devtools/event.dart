import 'package:vm_service/vm_service.dart';

/// Extension on [Event] to check if it is a CRDT LF event
extension CrdtLfEvent on Event {
  bool get isDocumentCreatedEvent =>
      extensionKind == 'crdt_lf:documents:created';
  bool get isDocumentChangedEvent =>
      extensionKind == 'crdt_lf:document:changed';

  int get documentId {
    if (!isDocumentChangedEvent) {
      throw StateError('Event is not a document changed event');
    }
    return extensionData?.data['id'] as int;
  }
}
