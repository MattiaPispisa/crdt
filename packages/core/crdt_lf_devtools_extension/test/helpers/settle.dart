// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:flutter_test/flutter_test.dart';

/// Runs the pending events, the zero-delay gates and the loads they start.
///
/// It counts turns of the event loop, not time, so a slow machine only makes
/// it longer.
Future<void> settle() => pumpEventQueue(times: 50);
