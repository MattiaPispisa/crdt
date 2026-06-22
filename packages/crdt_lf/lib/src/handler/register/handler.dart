import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';

part 'operation.dart';

/// # CRDT Register (last-writer-wins)
///
/// ## Description
/// A single-value CRDT: it holds one value of type `T` resolved with
/// **last-writer-wins** semantics (the write with the highest Hybrid Logical
/// Clock wins). It is the scalar counterpart of the collection handlers — use
/// it for a standalone mergeable value (a flag, a number, a short string that
/// is *not* collaboratively edited) instead of abusing a single-key map.
///
/// Compared to [CRDTFugueTextHandler]/[CRDTTextHandler] (which merge text at
/// the character level), a `CRDTRegisterHandler<String>` treats the value as
/// atomic: concurrent writes do not merge, one wins.
///
/// ## Example
/// ```dart
/// final doc = CRDTDocument();
/// final done = CRDTRegisterHandler<bool>(doc, 'done');
/// done.set(true);
/// print(done.value); // true
/// ```
class CRDTRegisterHandler<T> extends Handler<T> {
  /// Creates a new register with the given document and ID.
  ///
  /// [valueCodec] encodes/decodes `T` to bytes; default is [JsonValueCodec].
  CRDTRegisterHandler(
    super.doc,
    this._id, {
    ValueCodec<T>? valueCodec,
  }) : _valueCodec = valueCodec ?? JsonValueCodec<T>();

  final String _id;
  final ValueCodec<T> _valueCodec;

  @override
  String get id => _id;

  @override
  late final OperationFactory operationFactory =
      _RegisterOperationFactory<T>(this).fromBytes;

  /// Sets the register to [value] (last-writer-wins by HLC).
  void set(T value) {
    doc.registerOperation(
      _RegisterSetOperation<T>.fromHandler(this, value: value),
    );
  }

  /// The current value, or `null` if it was never set.
  T? get value {
    final cached = cachedState;
    if (cached != null) {
      return cached;
    }
    final computed = _computeValue();
    // The "unset" state (null) is not cached: recomputing it is trivial and a
    // non-nullable cache cannot represent it.
    if (computed != null) {
      updateCachedState(computed);
    }
    return computed;
  }

  T? _computeValue() {
    var current = _initialValue();
    // Operations are replayed in clock order, so the last one wins (LWW).
    for (final operation in operations()) {
      if (operation is _RegisterSetOperation<T>) {
        current = operation.value;
      }
    }
    return current;
  }

  @override
  T? incrementCachedState({
    required Operation operation,
    required T state,
  }) {
    // Only local writes reach the incremental path, and a local write is the
    // latest in clock order, so it wins.
    if (operation is _RegisterSetOperation<T>) {
      return operation.value;
    }
    return state;
  }

  @override
  Uint8List getSnapshotState() {
    final out = BytesBuilder(copy: false);
    final current = value;
    if (current == null) {
      out.addByte(0); // unset
      return out.toBytes();
    }
    out.addByte(1); // set
    final valueBytes = _valueCodec.encode(current);
    UVarint.write(valueBytes.length, out);
    out.add(valueBytes);
    return out.toBytes();
  }

  T? _initialValue() {
    final snapshot = lastSnapshot();
    if (snapshot == null || snapshot.isEmpty || snapshot[0] == 0) {
      return null;
    }
    final lenRec = UVarint.read(snapshot, offset: 1);
    final end = lenRec.nextOffset + lenRec.value;
    if (end > snapshot.length) {
      throw const FormatException('Truncated register snapshot value');
    }
    return _valueCodec.decode(
      Uint8List.sublistView(snapshot, lenRec.nextOffset, end),
    );
  }

  /// Returns a string representation of this register.
  @override
  String toString() => 'CRDTRegisterHandler($_id, $value)';
}
