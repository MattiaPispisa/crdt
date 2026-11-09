// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

/// The query executors that need `dart:ffi`, or stubs that throw where it is
/// missing.
library;

export 'native_executor_stub.dart'
    if (dart.library.ffi) 'native_executor_ffi.dart';
