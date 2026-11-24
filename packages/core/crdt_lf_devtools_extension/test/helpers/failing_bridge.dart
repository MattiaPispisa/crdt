// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/in_process_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';

/// Fails the calls to [failing] with a [BridgeCallException]; `null` lets
/// every call through.
class FailingBridge extends InProcessBridge {
  String? failing;

  @override
  Future<Json> call(String method, [Map<String, String> params = const {}]) {
    if (method == failing) {
      return Future.error(BridgeCallException(method, 'boom'));
    }
    return super.call(method, params);
  }
}
