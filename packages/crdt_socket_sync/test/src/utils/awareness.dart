import 'package:crdt_socket_sync/client.dart';
import 'package:test/test.dart';

/// Matcher for DocumentAwareness
class DocumentAwarenessMatcher extends Matcher {
  /// Matcher for DocumentAwareness
  ///
  /// [documentAwareness] is the expected DocumentAwareness
  DocumentAwarenessMatcher({
    required this.documentAwareness,
  });

  final DocumentAwareness documentAwareness;

  @override
  Description describe(Description description) {
    return description.addDescriptionOf(
      'DocumentAwareness(documentId: ${documentAwareness.documentId}, '
      'states: ${documentAwareness.states})',
    );
  }

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is! DocumentAwareness) {
      return false;
    }

    if (item.documentId != documentAwareness.documentId) {
      return false;
    }

    for (final entry in item.states.entries) {
      final matcher = ClientAwarenessMatcher(clientAwareness: entry.value);
      if (!matcher.matches(
        documentAwareness.states[entry.key],
        matchState,
      )) {
        return false;
      }
    }

    return true;
  }
}

/// Matcher for ClientAwareness
class ClientAwarenessMatcher extends Matcher {
  /// Matcher for ClientAwareness
  ///
  /// [clientAwareness] is the expected ClientAwareness
  ClientAwarenessMatcher({
    required this.clientAwareness,
  });

  final ClientAwareness clientAwareness;

  @override
  Description describe(Description description) {
    return description.addDescriptionOf(
      'ClientAwareness(clientId: ${clientAwareness.clientId}, '
      'metadata: ${clientAwareness.metadata})',
    );
  }

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is! ClientAwareness) {
      return false;
    }

    if (item.clientId != clientAwareness.clientId) {
      return false;
    }

    for (final key in item.metadata.entries) {
      if (clientAwareness.metadata[key.key] != key.value) {
        return false;
      }
    }

    return true;
  }
}
