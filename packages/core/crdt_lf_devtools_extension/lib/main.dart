// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/vm_service_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/screen.dart';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/widgets.dart';

void main() {
  runApp(DevToolsExtension(child: CrdtLfScreen(bridge: VmServiceBridge())));
}
