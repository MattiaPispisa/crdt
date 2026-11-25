// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:devtools_app_shared/service.dart';
import 'package:devtools_extensions/devtools_extensions.dart';

/// Keeps the wasm build valid; call it once, when the VM service connects.
void dart2wasmWorkaround() {
  final service = serviceManager.service;
  if (service == null) return;
  // dart2wasm (Dart 3.13 and 3.14) writes an invalid module for the
  // `EvalOnDartLibrary` constructor when no caller in the program passes
  // `isolate`, and `devtools_app_shared` itself never does. To check if it
  // is still needed: remove the call and run `melos run devtools_build`.
  EvalOnDartLibrary(
    'dart:core',
    service,
    serviceManager: serviceManager,
    isolate: serviceManager.isolateManager.mainIsolate,
  ).dispose();
}
