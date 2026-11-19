// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:convert';

// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/bridge_event.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:flutter/foundation.dart';

/// A [CrdtLfBridge] on the documents of this isolate, for tests and the
/// demo.
///
/// It is always [connected] and [available], and never [paused]. Listening
/// to [events] takes the single `DevToolsBridge.onEvent` slot until the
/// last listener leaves.
class InProcessBridge implements CrdtLfBridge {
  InProcessBridge()
    : _events = StreamController<BridgeEvent>.broadcast(),
      _connected = ValueNotifier<bool>(true),
      _available = ValueNotifier<bool>(true),
      _paused = ValueNotifier<bool>(false) {
    _events
      ..onListen = _listen
      ..onCancel = _cancel;
  }

  final StreamController<BridgeEvent> _events;

  final ValueNotifier<bool> _connected;

  final ValueNotifier<bool> _available;

  final ValueNotifier<bool> _paused;

  @override
  Future<Json> call(String method, [Map<String, String> params = const {}]) {
    final Json result;
    try {
      result = DevToolsBridge.call(method, {...params, 'method': method});
    } on Object catch (e) {
      return Future.error(BridgeCallException(method, '$e'));
    }
    // Through JSON, as over the VM service: a value it cannot encode fails
    // here too.
    return Future.value(jsonDecode(jsonEncode(result)) as Json);
  }

  @override
  Stream<BridgeEvent> get events => _events.stream;

  @override
  ValueListenable<bool> get connected => _connected;

  @override
  ValueListenable<bool> get available => _available;

  @override
  ValueListenable<bool> get paused => _paused;

  void _listen() {
    DevToolsBridge.onEvent =
        (kind, data) => _events.add(
          BridgeEvent(
            kind: kind,
            data: jsonDecode(jsonEncode(data)) as Json,
            time: DateTime.now(),
          ),
        );
  }

  void _cancel() {
    DevToolsBridge.onEvent = null;
  }

  @override
  void dispose() {
    _cancel();
    unawaited(_events.close());
    _connected.dispose();
    _available.dispose();
    _paused.dispose();
  }
}
