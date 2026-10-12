part of 'document.dart';

/// The [CRDTUndoManager]s recording a document, and what the document tells
/// all of them.
final class _UndoHub {
  /// `null`, not an empty list, when there is none, so that a document nobody
  /// undoes pays one comparison per local write.
  List<CRDTUndoManager>? _managers;

  Iterable<CRDTUndoManager> get managers =>
      _managers ?? const <CRDTUndoManager>[];

  void add(CRDTUndoManager manager) {
    (_managers ??= <CRDTUndoManager>[]).add(manager);
  }

  void remove(CRDTUndoManager manager) {
    final managers = _managers;
    if (managers == null) {
      return;
    }
    managers.removeWhere((m) => identical(m, manager));
    if (managers.isEmpty) {
      _managers = null;
    }
  }

  /// Offers [operation] to every manager, before [handler] folds it in.
  void capture(Handler<dynamic> handler, Operation operation) {
    final managers = _managers;
    if (managers == null) {
      return;
    }
    for (final manager in managers) {
      manager._capture(handler, operation);
    }
  }

  /// Closes the undo steps a committed transaction filled.
  void closeEntries() {
    final managers = _managers;
    if (managers == null) {
      return;
    }
    for (final manager in managers) {
      manager._closeEntry();
    }
  }

  /// Drops the steps of the deleted handlers [ids].
  void forget(Set<String> ids) {
    for (final manager in managers) {
      manager._forget(ids);
    }
  }

  /// Drops what an undo is anchored to: the stacks of every manager, and the
  /// rebuilt-identity chains of [handlers].
  void dropHistory(Iterable<Handler<dynamic>> handlers) {
    for (final manager in managers) {
      manager.clear();
    }
    for (final handler in handlers) {
      // A cast, not a promotion: the analyzer will not narrow a [Handler] to
      // a mixin it merely applies.
      if (handler is RebuiltIdentities<Object>) {
        (handler as RebuiltIdentities<Object>).clearRebuiltIdentities();
      }
    }
  }

  void dispose() {
    for (final manager in [...managers]) {
      manager.dispose();
    }
    _managers = null;
  }
}
