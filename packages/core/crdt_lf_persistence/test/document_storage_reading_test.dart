import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:persistence_conformance/persistence_conformance.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryStorageBackend backend;
  late InMemoryDocumentStorage storage;

  setUp(() {
    backend = InMemoryStorageBackend();
    storage = backend.storageForDocument('doc');
  });

  /// Writes [lines] through a persistence and returns the version after each.
  Future<List<VersionVector>> write(List<String> lines) async {
    final document = CRDTDocument(documentId: 'doc');
    final text = CRDTFugueTextHandler(document, 'text');
    final persistence = await CRDTDocumentPersistence.open(
      document,
      storage,
      writeDelay: Duration.zero,
    );

    final versions = <VersionVector>[];
    for (final line in lines) {
      text.insert(text.length, line);
      versions.add(document.getVersionVector());
    }

    await persistence.dispose();
    document.dispose();
    return versions;
  }

  group('CRDTDocumentStorage.readDocument', () {
    test('reads back what was stored', () async {
      await write(['hello ', '🌍']);

      final document = await storage.readDocument();

      expect(CRDTFugueTextHandler(document, 'text').value, 'hello 🌍');
    });

    test('an empty storage gives an empty document', () async {
      final document = await storage.readDocument();

      expect(document.exportChanges(), isEmpty);
      expect(document.documentId, 'doc');
    });

    test('the handlers are registered before anything is read into them',
        () async {
      await write(['hello']);

      late CRDTFugueTextHandler text;
      await storage.readDocument(
        onDocument: (document) => text = CRDTFugueTextHandler(document, 'text'),
      );

      expect(text.value, 'hello');
    });

    test('nothing keeps writing what it hands back', () async {
      await write(['hello']);
      final stored = await storage.changes.count;

      final document = await storage.readDocument();
      CRDTFugueTextHandler(document, 'text').insert(0, 'nope');
      await Future<void>.delayed(Duration.zero);

      expect(await storage.changes.count, stored);
    });

    test('a synchronous storage is read without suspending', () async {
      await write(['hello']);

      // A list of fifty notes is built inside one frame, not fifty futures.
      expect(storage.readDocument(), isA<CRDTDocument>());
    });

    test('the identity it writes under is the one handed in', () async {
      final peerId = PeerId.generate();

      final document = await storage.readDocument(peerId: peerId);

      expect(document.peerId, peerId);
    });
  });

  group('CRDTDocumentStorage.documentAt', () {
    test('gives the document as it stood at that version', () async {
      final versions = await write(['one ', 'two ', 'three']);

      final past = await storage.documentAt(versions[1]);

      expect(CRDTFugueTextHandler(past, 'text').value, 'one two ');
    });

    test('the newest version gives the whole document', () async {
      final versions = await write(['one ', 'two']);

      final now = await storage.documentAt(versions.last);

      expect(CRDTFugueTextHandler(now, 'text').value, 'one two');
    });

    test('a snapshot the version has not seen is left out', () async {
      final versions = await write(['one ', 'two']);
      // Taken now, so its version covers 'two'. Kept, so the log still
      // reaches back.
      final document = CRDTDocument(documentId: 'doc');
      CRDTFugueTextHandler(document, 'text');
      final persistence = await CRDTDocumentPersistence.open(
        document,
        storage,
        writeDelay: Duration.zero,
      );
      document.takeSnapshot(pruneHistory: false);
      await persistence.flush();
      await persistence.dispose();

      final past = await storage.documentAt(versions.first);

      expect(
        CRDTFugueTextHandler(past, 'text').value,
        'one ',
        reason: 'the snapshot describes a state that had not happened yet',
      );
    });

    test('a version whose history was pruned is refused, not answered empty',
        () async {
      final versions = await write(['one ', 'two']);

      final document = CRDTDocument(documentId: 'doc');
      CRDTFugueTextHandler(document, 'text');
      final persistence = await CRDTDocumentPersistence.open(
        document,
        storage,
        writeDelay: Duration.zero,
      );
      await persistence.compact();
      await persistence.dispose();

      expect(
        () => storage.documentAt(versions.first),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('CRDTDocumentStorage.copyTo', () {
    test('what the target already holds and the source does not is kept',
        () async {
      await write(['hello']);
      final other = backend.storageForDocument('other');
      final extra = CRDTDocument(documentId: 'other');
      CRDTFugueTextHandler(extra, 'text').insert(0, 'mine');
      other.changes.saveChanges(extra.exportChanges());

      await storage.copyTo(other);

      expect(
        await other.changes.count,
        (await storage.changes.count) + extra.exportChanges().length,
        reason: 'a copy is not a replace: clear the target for an exact one',
      );
    });

    test('the identity comes along when both peer id storages are given',
        () async {
      await write(['hello']);
      final peerId = PeerId.generate();
      backend.peerIdStorageForDocument('doc').savePeerId(peerId);

      final other = InMemoryStorageBackend();
      await storage.copyTo(
        other.storageForDocument('doc'),
        fromPeerIds: backend.peerIdStorageForDocument('doc'),
        toPeerIds: other.peerIdStorageForDocument('doc'),
      );

      expect(
        other.peerIdStorageForDocument('doc').getPeerId(),
        peerId,
        reason: 'the document is the same writer on the other side',
      );
    });

    test('without the peer id storages the copy is the content only', () async {
      await write(['hello']);
      backend.peerIdStorageForDocument('doc').savePeerId(PeerId.generate());

      final other = InMemoryStorageBackend();
      await storage.copyTo(other.storageForDocument('doc'));

      expect(other.peerIdStorageForDocument('doc').getPeerId(), isNull);
    });

    test('a transaction that refuses the copy leaves no identity behind',
        () async {
      await write(['hello']);
      backend.peerIdStorageForDocument('doc').savePeerId(PeerId.generate());

      final other = InMemoryStorageBackend();
      await expectLater(
        storage.copyTo(
          _RefusedTransaction(other.storageForDocument('doc')),
          fromPeerIds: backend.peerIdStorageForDocument('doc'),
          toPeerIds: other.peerIdStorageForDocument('doc'),
        ),
        throwsStateError,
      );

      expect(
        other.peerIdStorageForDocument('doc').getPeerId(),
        isNull,
        reason: 'the identity goes in with the content, or not at all',
      );
    });

    // A synchronous backend runs the whole body inside its open transaction.
    // An `async` body suspends there, and on a backend where one connection
    // serves every document another write can land inside the transaction and
    // be taken away by a rollback.
    test('the transaction body never suspends on a synchronous backend',
        () async {
      await write(['hello']);
      backend.peerIdStorageForDocument('doc').savePeerId(PeerId.generate());

      final other = InMemoryStorageBackend();
      final target = _WatchedTransaction(other.storageForDocument('doc'));

      await storage.copyTo(
        target,
        fromPeerIds: backend.peerIdStorageForDocument('doc'),
        toPeerIds: other.peerIdStorageForDocument('doc'),
      );

      expect(target.bodySuspended, isFalse);
      expect(await target.changes.count, await storage.changes.count);
      expect(other.peerIdStorageForDocument('doc').getPeerId(), isNotNull);
    });
  });
}

/// A storage whose transaction refuses the whole body, the way a rollback
/// leaves a backend that has one.
class _RefusedTransaction extends CRDTDocumentStorage {
  _RefusedTransaction(InMemoryDocumentStorage inner)
      : super(changes: inner.changes, snapshots: inner.snapshots);

  @override
  FutureOr<T> transaction<T>(FutureOr<T> Function() body) =>
      throw StateError('rolled back');
}

/// A storage that records whether the body of its transaction suspended.
class _WatchedTransaction extends CRDTDocumentStorage {
  _WatchedTransaction(InMemoryDocumentStorage inner)
      : super(changes: inner.changes, snapshots: inner.snapshots);

  /// Whether the last body handed back a [Future] instead of a value.
  bool bodySuspended = false;

  @override
  FutureOr<T> transaction<T>(FutureOr<T> Function() body) {
    final result = body();
    bodySuspended = result is Future<T>;
    return result;
  }
}
