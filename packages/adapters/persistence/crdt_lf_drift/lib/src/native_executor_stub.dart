// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:drift/drift.dart';

/// Throws an [UnsupportedError]: this platform has no `dart:ffi`.
QueryExecutor fileExecutor(File file) => throw _unsupported();

/// Throws an [UnsupportedError]: this platform has no `dart:ffi`.
QueryExecutor memoryExecutor() => throw _unsupported();

UnsupportedError _unsupported() => UnsupportedError(
      'CRDTDrift.open and CRDTDrift.memory need dart:ffi, which this platform '
      'does not have. On the web, open a WasmDatabase from '
      'package:drift/wasm.dart and pass it to CRDTDrift.fromDatabase: '
      'CRDTDrift.fromDatabase(CRDTDriftDatabase(executor)).',
    );
