// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/in_process_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';

/// Answers [slow] calls 50 ms after the app ran them, as a busy VM service.
class SlowBridge extends InProcessBridge {
  String? slow;

  @override
  Future<Json> call(
    String method, [
    Map<String, String> params = const {},
  ]) async {
    final answer = await super.call(method, params);
    if (method == slow) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return answer;
  }
}
