// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/bridge_event.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:devtools_app_shared/service.dart';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/foundation.dart';
import 'package:vm_service/vm_service.dart';

/// A [CrdtLfBridge] on the main isolate of the app DevTools is connected
/// to.
class VmServiceBridge implements CrdtLfBridge {
  VmServiceBridge()
    : _events = StreamController<BridgeEvent>.broadcast(),
      _paused = ValueNotifier<bool>(false) {
    _events
      ..onListen = _listen
      ..onCancel = _cancel;
  }

  /// The service extension the app registers.
  static const String extensionName = 'ext.crdt_lf.devtools';

  static const String _eventPrefix = 'crdt_lf:devtools:';

  final StreamController<BridgeEvent> _events;

  final ValueNotifier<bool> _paused;

  StreamSubscription<Event>? _subscription;

  IsolateState? _isolate;

  bool _watchingIsolate = false;

  @override
  Future<Json> call(
    String method, [
    Map<String, String> params = const {},
  ]) async {
    try {
      final response = await serviceManager.callServiceExtensionOnMainIsolate(
        extensionName,
        args: {...params, 'method': method},
      );
      return {...?response.json};
    } on RPCError catch (e) {
      throw BridgeCallException(method, '${e.data?['details'] ?? e.message}');
    }
  }

  @override
  Stream<BridgeEvent> get events => _events.stream;

  @override
  ValueListenable<bool> get available =>
      serviceManager.serviceExtensionManager.hasServiceExtension(extensionName);

  @override
  ValueListenable<bool> get paused {
    if (!_watchingIsolate) {
      _watchingIsolate = true;
      serviceManager.isolateManager.mainIsolate.addListener(_onIsolate);
      _onIsolate();
    }
    return _paused;
  }

  void _onIsolate() {
    _isolate?.isPaused.removeListener(_onPaused);
    _isolate = serviceManager.isolateManager.mainIsolateState;
    _isolate?.isPaused.addListener(_onPaused);
    _onPaused();
  }

  void _onPaused() {
    _paused.value = _isolate?.isPaused.value ?? false;
  }

  void _listen() {
    serviceManager.connectedState.addListener(_subscribe);
    _subscribe();
  }

  // A new connection brings a new service, with its own event stream.
  void _subscribe() {
    unawaited(_subscription?.cancel());
    _subscription = serviceManager.service?.onExtensionEvent.listen((event) {
      final kind = event.extensionKind;
      if (kind == null || !kind.startsWith(_eventPrefix)) return;
      _events.add(
        BridgeEvent(
          kind: kind,
          data: {...?event.extensionData?.data},
          time: DateTime.now(),
        ),
      );
    });
  }

  void _cancel() {
    serviceManager.connectedState.removeListener(_subscribe);
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  @override
  void dispose() {
    _cancel();
    if (_watchingIsolate) {
      serviceManager.isolateManager.mainIsolate.removeListener(_onIsolate);
      _isolate?.isPaused.removeListener(_onPaused);
    }
    unawaited(_events.close());
    _paused.dispose();
  }
}
