// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'document.dart';

/// What a snapshot holds, before its capabilities record: its `data`, the
/// handlers it wrote a fresh blob for (`written`), the types of the blobs it
/// copied (`copiedTypes`), and whether it copied a blob of unknown type
/// (`copiedUntyped`).
typedef _SnapshotDraft = ({
  Map<String, Uint8List> data,
  List<Handler<dynamic>> written,
  Set<String> copiedTypes,
  bool copiedUntyped,
});

/// Writes the data of a snapshot of a document: the state of every handler
/// the document holds data for, open or not.
final class _SnapshotWriter {
  _SnapshotWriter(this._document);

  final CRDTDocument _document;

  /// The data of a snapshot taken now.
  _SnapshotDraft write() {
    final registry = _document._registry;
    final previous = _document._lastSnapshot;
    final previousIds = SnapshotRecords.handlerIdsOf(previous);
    final previousEntries = SnapshotRecords.unfoldedEntriesOf(previous);
    final previousManifest = _HandlerRegistry.manifestOf(previous);

    final data = <String, Uint8List>{};
    final manifest = <String, String>{};
    final written = <Handler<dynamic>>[];
    final unfolded = <String, Uint8List>{};
    final copiedTypes = <String>{};
    var copiedUntyped = false;
    var hasContainers = false;

    void write(Handler<dynamic> handler, Uint8List blob) {
      data[handler.id] = blob;
      manifest[handler.id] = handler.handlerType;
      written.add(handler);
      if (handler is ContainerHandler) {
        hasContainers = true;
      }
    }

    void copy(String id, String? type) {
      final blob = previous?.data[id];
      if (blob == null) {
        return;
      }
      data[id] = blob;
      if (type == null) {
        copiedUntyped = true;
      } else {
        copiedTypes.add(type);
      }
    }

    for (final handler in registry.values.toList()) {
      write(handler, handler.getSnapshotState());
    }

    final closed = {...previousIds, ..._document._log.handlerIds}
      ..removeWhere((id) => registry[id] != null || _document.isDeleted(id));

    for (final id in closed) {
      // The changes after the blob and its unfolded entry, or every change
      // when the previous snapshot holds nothing for this handler.
      final held = previousIds.contains(id);
      final entry = previousEntries[id];
      final fresh = _document._log.changesForHandler(
        id,
        fromVersionVector: held ? previous?.versionVector : null,
      );
      final type = previousManifest[id] ??
          _HandlerRegistry.typeIn(
            [...fresh, ..._document._readableUnfoldedChanges(id)],
          );
      if (type != null) {
        manifest[id] = type;
      }

      // Nothing since the blob was written: it is the state at the new cut too.
      if (entry == null && fresh.isEmpty) {
        copy(id, type);
        continue;
      }

      // A handler replays only what comes after the snapshot, so changes the
      // previous snapshot covers without holding them can only be carried.
      final buildable = held ||
          previous == null ||
          fresh.every(
            (change) =>
                !previous.versionVector.hasSeen(change.author, change.hlc),
          );
      final built = buildable && type != null ? _build(id, type) : null;
      if (built != null) {
        write(built.handler, built.blob);
        continue;
      }

      // No one here can fold these changes: they ride on top of the old blob
      // until a peer that knows the kind takes its own snapshot.
      copy(id, type);
      if (fresh.isEmpty) {
        // Passed on as it is: an entry this build may not even read.
        unfolded[id] = entry!;
        continue;
      }
      final List<Change> carried;
      try {
        carried = SnapshotRecords.unfoldedChangesFor(previous, id) ?? const [];
      } on FormatException catch (error) {
        throw FormatException(
          'Handler $id has new changes on top of unfolded changes this build '
          'cannot read, so no snapshot can hold both: ${error.message}',
        );
      }
      unfolded[id] = SnapshotRecords.encodeUnfoldedEntry(
        [...carried, ...fresh].sorted(),
      );
    }

    if (unfolded.isNotEmpty) {
      data[SnapshotRecords.unfoldedKey] =
          SnapshotRecords.encodeUnfolded(unfolded);
    }
    if ((hasContainers || previousManifest.isNotEmpty || closed.isNotEmpty) &&
        manifest.isNotEmpty) {
      data[SnapshotRecords.manifestKey] =
          SnapshotRecords.encodeManifest(manifest);
    }
    return (
      data: data,
      written: written,
      copiedTypes: copiedTypes,
      copiedUntyped: copiedUntyped,
    );
  }

  /// The blob of the closed handler [id] built for the time of the snapshot;
  /// `null` when this document cannot build or read a [type].
  ({Handler<dynamic> handler, Uint8List blob})? _build(String id, String type) {
    try {
      return _document._readClosed(
        id,
        type,
        (handler) => (handler: handler, blob: handler.getSnapshotState()),
      );
    } on Exception {
      // Data this build cannot read, such as events of a newer version: the
      // caller carries its changes rather than lose them.
      return null;
    }
  }
}
