import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/client.dart';
import 'package:crdt_socket_sync/replica.dart';
import 'package:persistence_conformance/persistence_conformance.dart';
import 'package:test/test.dart';

import '../../utils/mock_socket_client.dart';

/// Storages that outlive the replicas opening them, and a log of what gets
/// closed.
class _Backend extends InMemoryStorageBackend {
  _Backend(this.log);

  final List<String> log;

  final Map<String, _Storage> _storages = <String, _Storage>{};

  /// Fails the open after the document is built, as a restore that fails.
  bool fails = false;

  @override
  _Storage storageForDocument(String documentId) {
    if (fails) {
      throw StateError('corrupt');
    }
    return _storages.putIfAbsent(documentId, () => _Storage(documentId, log));
  }

  @override
  void close() => log.add('backend');
}

/// A storage that says, when it is closed, whether anything reached it.
class _Storage extends InMemoryDocumentStorage {
  _Storage(super.documentId, this.log);

  final List<String> log;

  // `this.` on purpose: without it `isNotEmpty` is the matcher of
  // package:test, which wins over an inherited getter.
  @override
  void close() {
    log.add(this.isNotEmpty ? 'storage (written)' : 'storage (empty)');
  }
}

class _Client extends MockCRDTSocketClient {
  _Client(CRDTDocument document, this.log)
      : super(document: document, author: document.peerId);

  final List<String> log;

  @override
  void dispose() {
    log.add('client');
    super.dispose();
  }
}

CRDTFugueTextHandler _textOf(CRDTDocument document) {
  return document.handler(CRDTFugueTextHandler.spec, 'text');
}

void main() {
  group('CRDTReplica', () {
    late List<String> log;
    late _Backend backend;

    setUp(() {
      log = <String>[];
      backend = _Backend(log);
    });

    test('keeps a document without storage or sync in memory', () async {
      CRDTDocument? opened;
      final replica = await CRDTReplica.open(
        documentId: 'doc',
        onDocument: (document) => opened = document,
      );

      expect(opened, same(replica.document));
      expect(replica.document.documentId, 'doc');
      expect(replica.persistence, isNull);
      expect(replica.client, isNull);

      await replica.close();
      expect(replica.document.isDisposed, isTrue);
    });

    test('restores the last edit of an earlier replica, under its peer id',
        () async {
      final first = await CRDTReplica.open(
        documentId: 'doc',
        storage: () => backend,
        ownsStorage: false,
      );
      _textOf(first.document).insert(0, 'hello');
      // Right after the edit, well inside the write delay: only the flush of
      // `close` can have written it.
      await first.close();

      final second = await CRDTReplica.open(
        documentId: 'doc',
        storage: () => backend,
        ownsStorage: false,
        // A handler opened before the restore still shows what it restored.
        onDocument: _textOf,
      );

      expect(_textOf(second.document).value, 'hello');
      expect(second.document.peerId, first.document.peerId);

      await second.close();
      expect(log, isNot(contains('backend')));
    });

    test('builds the client on the restored document, then connects it',
        () async {
      final seed = await CRDTReplica.open(
        documentId: 'doc',
        storage: () => backend,
        ownsStorage: false,
      );
      _textOf(seed.document).insert(0, 'written offline');
      await seed.close();

      String? textSeenByClient;
      final replica = await CRDTReplica.open(
        documentId: 'doc',
        storage: () => backend,
        sync: (document) {
          textSeenByClient = _textOf(document).value;
          return _Client(document, log);
        },
      );
      await pumpEventQueue();

      expect(textSeenByClient, 'written offline');
      expect(replica.client!.document, same(replica.document));
      expect(
        replica.client!.connectionStatusValue,
        ConnectionStatus.connected,
      );

      await replica.close();
    });

    test('closes the client, then writes, then closes the storage', () async {
      final replica = await CRDTReplica.open(
        documentId: 'doc',
        storage: () => backend,
        sync: (document) => _Client(document, log),
      );
      _textOf(replica.document).insert(0, 'last words');

      await Future.wait([replica.close(), replica.close()]);

      expect(log, ['client', 'storage (written)', 'backend']);
      expect(replica.document.isDisposed, isTrue);
      expect(replica.isClosed, isTrue);
    });

    test('goes on in memory when the storage fails and onStorageError is set',
        () async {
      final errors = <Object>[];
      final replica = await CRDTReplica.open(
        documentId: 'doc',
        storage: () => throw StateError('disk full'),
        onStorageError: (error, _) => errors.add(error),
      );

      expect(errors, [isA<StateError>()]);
      expect(replica.persistence, isNull);
      _textOf(replica.document).insert(0, 'still editable');
      expect(_textOf(replica.document).value, 'still editable');

      await replica.close();
    });

    test('runs onDocument again on the in-memory document of a failed restore',
        () async {
      backend.fails = true;
      final documents = <CRDTDocument>[];
      final replica = await CRDTReplica.open(
        documentId: 'doc',
        storage: () => backend,
        onDocument: documents.add,
        onStorageError: (_, __) {},
      );

      expect(documents, hasLength(2));
      expect(documents.first.isDisposed, isTrue);
      expect(documents.last, same(replica.document));

      await replica.close();
    });

    test('rethrows an error of onDocument, even with onStorageError', () async {
      final errors = <Object>[];
      await expectLater(
        CRDTReplica.open(
          documentId: 'doc',
          storage: () => backend,
          onDocument: (_) => throw ArgumentError('bad setup'),
          onStorageError: (error, _) => errors.add(error),
        ),
        throwsArgumentError,
      );

      expect(errors, isEmpty);
      expect(log, ['backend']);
    });

    test('rethrows a storage failure without onStorageError', () {
      expect(
        CRDTReplica.open(
          documentId: 'doc',
          storage: () => throw StateError('disk full'),
        ),
        throwsStateError,
      );
    });

    test('closes what it opened when the client cannot be built', () async {
      await expectLater(
        CRDTReplica.open(
          documentId: 'doc',
          storage: () => backend,
          sync: (_) => throw StateError('bad url'),
        ),
        throwsStateError,
      );

      expect(log, ['storage (empty)', 'backend']);
    });
  });
}
