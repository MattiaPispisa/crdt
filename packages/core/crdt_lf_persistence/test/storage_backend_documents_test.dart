import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:persistence_conformance/persistence_conformance.dart';
import 'package:test/test.dart';

void main() {
  group('CRDTStorageBackend.openDocument', () {
    late InMemoryStorageBackend backend;

    setUp(() {
      backend = InMemoryStorageBackend();
    });

    /// Opens the document, with its one handler registered by [onDocument].
    Future<({PersistentDocument opened, CRDTFugueTextHandler text})> open({
      PeerId? author,
    }) async {
      final opened = await backend.openDocument(
        'doc',
        author: author,
        writeDelay: Duration.zero,
      );
      // Built after the restore, which reads the same as building it before.
      return (
        opened: opened,
        text: CRDTFugueTextHandler(opened.document, 'text'),
      );
    }

    test('a reopened document is the same author, holding what it held',
        () async {
      final first = await open();
      first.text.insert(0, 'Hello 🌍');
      await first.opened.persistence.dispose();

      final second = await open();

      expect(second.opened.document.peerId, first.opened.document.peerId);
      expect(second.text.value, 'Hello 🌍');
      await second.opened.persistence.dispose();
    });

    test('an author seeds a document that has no identity, and never beats one',
        () async {
      final seed = PeerId.generate();

      final first = await open(author: seed);
      expect(first.opened.document.peerId, seed);
      await first.opened.persistence.dispose();

      final second = await open(author: PeerId.generate());
      expect(
        second.opened.document.peerId,
        seed,
        reason: 'the stored id is what the document already wrote under',
      );
      await second.opened.persistence.dispose();
    });

    test('onDocument runs before anything is restored into the document',
        () async {
      final first = await open();
      first.text.insert(0, 'a');
      await first.opened.persistence.dispose();

      final seen = <String>[];
      final second = await backend.openDocument(
        'doc',
        onDocument: (document) => seen.add(document.exportChanges().isEmpty
            ? 'empty'
            : 'already restored'),
        writeDelay: Duration.zero,
      );

      expect(seen, ['empty']);
      await second.persistence.dispose();
    });

    test('a restore that fails disposes the document it built', () async {
      CRDTDocument? built;

      await expectLater(
        _UnreadableBackend().openDocument(
          'doc',
          onDocument: (document) => built = document,
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        built!.isDisposed,
        isTrue,
        reason: 'a caller never gets half a document back',
      );
    });
  });
}

/// A backend whose documents cannot be read back.
class _UnreadableBackend implements CRDTStorageBackend {
  @override
  CRDTDocumentStorage storageForDocument(String documentId) =>
      _UnreadableStorage(documentId);

  @override
  CRDTPeerIdStorage peerIdStorageForDocument(String documentId) =>
      InMemoryPeerIdStorage(documentId, <String, PeerId>{});

  @override
  Set<String> get documentIds => <String>{};

  @override
  void deleteDocument(String documentId) {}

  @override
  void close() {}
}

/// A storage that cannot be read back.
class _UnreadableStorage extends CRDTDocumentStorage {
  _UnreadableStorage(String documentId)
      : super(
          changes: _UnreadableChangeStorage(documentId),
          snapshots: InMemorySnapshotStorage(documentId),
        );
}

class _UnreadableChangeStorage extends InMemoryChangeStorage {
  _UnreadableChangeStorage(super.documentId);

  @override
  List<Change> getChanges({VersionVector? newerThan, VersionVector? upTo}) {
    throw StateError('database is corrupt');
  }
}
