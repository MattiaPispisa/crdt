import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/snapshot/blob_version.dart';

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
base class CRDTRegisterHandler<T> extends Handler<T>
    with DeltaProvider<T?, RegisterDelta<T>> {
  /// Creates a new register with the given document and ID.
  ///
  /// [valueCodec] encodes/decodes `T` to bytes; default is [JsonValueCodec].
  CRDTRegisterHandler(
    super.doc,
    this._id, {
    ValueCodec<T>? valueCodec,
    super.handlerType,
  }) : _valueCodec = valueCodec ?? JsonValueCodec<T>();

  final String _id;
  final ValueCodec<T> _valueCodec;

  @override
  String get id => _id;

  @override
  late final OperationDecoders operationDecoders = {
    OperationType.kindInsert: (body) =>
        _RegisterSetOperation<T>.fromBodyBytes(this, body),
  };

  /// Sets the register to [value] (last-writer-wins by HLC).
  ///
  /// Consecutive writes performed inside a [CRDTDocument.runInTransaction] are
  /// compacted into a single set of the last value.
  void set(T value) {
    doc.registerOperation(
      _RegisterSetOperation<T>.fromHandler(this, value: value),
    );
  }

  /// The current value, or `null` if it was never set.
  @override
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
  Operation? compound(Operation accumulator, Operation current) {
    // Consecutive writes collapse to the last one (last-writer-wins), which is
    // exactly what a single set of the latest value replays to.
    if (accumulator is _RegisterSetOperation<T> &&
        current is _RegisterSetOperation<T>) {
      return current;
    }
    return null;
  }

  @override
  T? incrementCachedState({
    required Operation operation,
    required T state,
    DeltaSink<Object?>? sink,
  }) {
    if (operation is! _RegisterSetOperation<T>) {
      // The register has one operation kind, so a change carrying any other
      // kind is refused before it gets here: [operationDecoders] cannot decode
      // it. Only an operation built by hand under this handler's id reaches
      // this line, and a recompute skips it the same way [_computeValue] does.
      // Writing nothing to [sink] is how "nothing moved" is said — the hub
      // then publishes no event at all.
      return state;
    }
    // Only an operation that is the latest in clock order reaches this: a
    // local write, or a remote change newer than everything folded in so far.
    // Last-writer-wins then makes the new value the whole answer.
    sink?.add(RegisterDelta<T>(previous: state, current: operation.value));
    return operation.value;
  }

  /// The version of the snapshot blob this build writes and reads.
  ///
  /// Layout: `version: u8`, `present: u8`, then, when present,
  /// `valueLen: uvarint`, `value: bytes`.
  static const int _snapshotVersion = 1;

  @override
  Uint8List getSnapshotState() {
    final out = BytesBuilder(copy: false)..addByte(_snapshotVersion);
    final current = value;
    if (current == null) {
      out.addByte(0); // unset
      return out.toBytes();
    }
    out.addByte(1); // set
    UVarint.writeBytes(_valueCodec.encode(current), out);
    return out.toBytes();
  }

  T? _initialValue() {
    final snapshot = lastSnapshot();
    if (snapshot == null) {
      return null;
    }
    final offset = SnapshotBlob.read(
      snapshot,
      version: _snapshotVersion,
      name: 'register',
    );
    if (offset >= snapshot.length) {
      throw const FormatException('Truncated register snapshot');
    }
    if (snapshot[offset] == 0) {
      return null;
    }
    return _valueCodec.decode(
      UVarint.readBytes(
        snapshot,
        offset: offset + 1,
        what: 'register snapshot value',
      ).value,
    );
  }

  /// Returns a string representation of this register.
  @override
  T? applyDelta(T? base, RegisterDelta<T> delta) => delta.apply(base);

  @override
  String toString() => 'CRDTRegisterHandler($_id, $value)';
}
