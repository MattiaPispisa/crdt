// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

/// The local wall time `HH:mm:ss.SSS` of [time].
String wallTime(DateTime time) {
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
      '${t.millisecond.toString().padLeft(3, '0')}';
}
