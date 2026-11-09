// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

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
        onDocument: (document) => seen.add(
          document.exportChanges().isEmpty ? 'empty' : 'already restored',
        ),
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

  group('CRDTStorageBackend.documentAt', () {
    test('reads the document of a given id as it was at a version', () async {
      final backend = InMemoryStorageBackend();
      final opened = await backend.openDocument(
        'doc',
        writeDelay: Duration.zero,
      );
      final text = CRDTFugueTextHandler(opened.document, 'text')
        ..insert(0, 'a');
      final afterA = opened.document.getVersionVector();
      text.insert(1, 'b');
      await opened.persistence.dispose();

      final before = await backend.documentAt('doc', afterA);
      expect(CRDTFugueTextHandler(before, 'text').value, 'a');

      late CRDTFugueTextHandler registered;
      final now = await backend.documentAt(
        'doc',
        opened.document.getVersionVector(),
        peerId: opened.document.peerId,
        onDocument: (document) =>
            registered = CRDTFugueTextHandler(document, 'text'),
      );
      expect(registered.value, 'ab');
      expect(now.peerId, opened.document.peerId);
    });

    test('closes the storage it opened', () async {
      final backend = _CountingBackend();

      await backend.documentAt('doc', VersionVector({}));

      expect(backend.closed, backend.opened);
    });
  });

  group('CRDTStorageBackend.readDocument', () {
    test('reads the document of a given id', () async {
      final backend = InMemoryStorageBackend();
      final opened = await backend.openDocument(
        'doc',
        writeDelay: Duration.zero,
      );
      CRDTFugueTextHandler(opened.document, 'text').insert(0, 'a🌍');
      await opened.persistence.dispose();

      late CRDTFugueTextHandler registered;
      final read = await backend.readDocument(
        'doc',
        peerId: opened.document.peerId,
        onDocument: (document) =>
            registered = CRDTFugueTextHandler(document, 'text'),
      );

      expect(registered.value, 'a🌍');
      expect(read.peerId, opened.document.peerId);
    });

    for (final suspends in [false, true]) {
      test(
          'closes the storage it opened, after a read that fails too '
          '(suspends: $suspends)', () async {
        final backend = _CountingBackend(suspends: suspends);
        await backend.readDocument('doc');

        final broken = _CountingBackend(suspends: suspends, unreadable: true);
        await expectLater(
          Future.sync(() => broken.readDocument('doc')),
          throwsA(isA<StateError>()),
        );

        expect(backend.opened, 1);
        expect(backend.closed, 1);
        expect(broken.opened, 1);
        expect(broken.closed, 1);
      });
    }
  });

  group('CRDTStorageBackend.copyDocumentTo', () {
    test('carries the document and its identity to the other backend',
        () async {
      final backend = InMemoryStorageBackend();
      final opened = await backend.openDocument(
        'doc',
        writeDelay: Duration.zero,
      );
      CRDTFugueTextHandler(opened.document, 'text').insert(0, 'a🌍');
      await opened.persistence.dispose();

      final other = InMemoryStorageBackend();
      await backend.copyDocumentTo(other, 'doc');

      expect(other.documentIds, contains('doc'));
      expect(
        other.peerIdStorageForDocument('doc').getPeerId(),
        opened.document.peerId,
        reason: 'it is the same document, in another place',
      );
      final copied = await other.readDocument('doc');
      expect(CRDTFugueTextHandler(copied, 'text').value, 'a🌍');
    });

    test('closes the two storages it opened', () async {
      final from = _CountingBackend();
      final to = _CountingBackend();

      await from.copyDocumentTo(to, 'doc');

      expect([from.opened, from.closed, to.opened, to.closed], [1, 1, 1, 1]);
    });
  });
}

/// A backend that counts the storages it hands out and the ones closed.
///
/// [suspends] makes every change read answer with a [Future], and
/// [unreadable] makes it throw.
class _CountingBackend implements CRDTStorageBackend {
  _CountingBackend({this.suspends = false, this.unreadable = false});

  final bool suspends;
  final bool unreadable;

  int opened = 0;
  int closed = 0;

  @override
  CRDTDocumentStorage storageForDocument(String documentId) {
    opened++;
    return _CountingStorage(
      documentId,
      _SuspendingChangeStorage(
        unreadable
            ? _UnreadableChangeStorage(documentId)
            : InMemoryChangeStorage(documentId),
        suspends: suspends,
      ),
      onClose: () => closed++,
    );
  }

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

/// A storage that reports its [close], which answers with a [Future].
class _CountingStorage extends CRDTDocumentStorage {
  _CountingStorage(
    String documentId,
    CRDTChangeStorage changes, {
    required void Function() onClose,
  })  : _onClose = onClose,
        super(
          changes: changes,
          snapshots: InMemorySnapshotStorage(documentId),
        );

  final void Function() _onClose;

  @override
  Future<void> close() async => _onClose();
}

/// A change storage whose reads answer with a [Future] when [suspends].
class _SuspendingChangeStorage implements CRDTChangeStorage {
  _SuspendingChangeStorage(this._inner, {required this.suspends});

  final InMemoryChangeStorage _inner;

  final bool suspends;

  @override
  String get documentId => _inner.documentId;

  @override
  FutureOr<List<Change>> getChanges({
    VersionVector? newerThan,
    VersionVector? upTo,
  }) {
    if (suspends) {
      return Future(() => _inner.getChanges(newerThan: newerThan, upTo: upTo));
    }
    return _inner.getChanges(newerThan: newerThan, upTo: upTo);
  }

  @override
  void saveChange(Change change) => _inner.saveChange(change);

  @override
  void saveChanges(List<Change> changes) => _inner.saveChanges(changes);

  @override
  bool deleteChange(Change change) => _inner.deleteChange(change);

  @override
  int deleteChanges(List<Change> changes) => _inner.deleteChanges(changes);

  @override
  void clear() => _inner.clear();

  @override
  int get count => _inner.count;
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
