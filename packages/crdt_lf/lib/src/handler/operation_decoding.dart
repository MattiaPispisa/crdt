import 'dart:typed_data';

import 'package:crdt_lf/src/binary/operation_codec.dart';
import 'package:crdt_lf/src/exceptions/exceptions.dart';
import 'package:crdt_lf/src/operation/operation.dart';

/// A per-kind decoder, keyed by [OperationEnvelope.kind].
///
/// Not exported by the package: each built-in handler's `operation.dart` is
/// its own library (a `part of` its own `handler.dart`, not of this one), so
/// this has to be a public name to be reusable across them, even though it
/// is not part of the public API.
typedef OperationDecoders = Map<int, Operation Function(Uint8List body)>;

/// Looks up [envelope]'s kind in [decoders] and returns what it decodes to.
///
/// Every built-in handler's `OperationFactory` does the same two things once
/// `Handler._operationFromChange` has already confirmed the envelope
/// addresses it: a lookup on [OperationEnvelope.kind], and the same failure
/// ([UnknownOperationKindException]) when the kind is not one of its own.
/// Only [decoders] varies from one handler to the next.
Operation decodeOperation(
  OperationEnvelope envelope,
  Uint8List body,
  OperationDecoders decoders,
) {
  final decode = decoders[envelope.kind];
  if (decode == null) {
    throw UnknownOperationKindException(
      handlerType: envelope.handlerType,
      handlerId: envelope.handlerId,
      kind: envelope.kind,
    );
  }
  return decode(body);
}
