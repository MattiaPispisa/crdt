// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/models/bridge_event.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:flutter/foundation.dart';

/// The transport to the `crdt_lf` DevTools protocol of the debugged app.
abstract interface class CrdtLfBridge {
  /// Calls the protocol [method] with [params].
  ///
  /// Throws a [BridgeCallException] when the app refuses the call.
  Future<Json> call(String method, [Map<String, String> params]);

  /// The `crdt_lf:devtools:*` events posted by the app.
  Stream<BridgeEvent> get events;

  /// Whether DevTools is connected to an app.
  ValueListenable<bool> get connected;

  /// Whether the app registered the protocol: it does so with its first
  /// document.
  ValueListenable<bool> get available;

  /// Whether the main isolate is paused: the app answers no call then.
  ValueListenable<bool> get paused;

  /// Releases the listeners and closes [events].
  void dispose();
}

/// A protocol call the app refused, or could not answer.
class BridgeCallException implements Exception {
  const BridgeCallException(this.method, this.message);

  final String method;

  final String message;

  @override
  String toString() => 'BridgeCallException($method): $message';
}

/// The app has no time travel session with the id of a call: it ended it,
/// or a newer one replaced it.
class HistorySessionClosed extends BridgeCallException {
  const HistorySessionClosed(super.method, super.message);
}
