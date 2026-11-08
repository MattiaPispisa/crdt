// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// A native SQLite executor on [file].
QueryExecutor fileExecutor(File file) => NativeDatabase(file);

/// A native SQLite executor in memory.
QueryExecutor memoryExecutor() => NativeDatabase.memory();
