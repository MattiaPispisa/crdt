// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:flutter/painting.dart';

const List<Color> _okabeIto = [
  Color(0xFFE69F00),
  Color(0xFF56B4E9),
  Color(0xFF009E73),
  Color(0xFFF0E442),
  Color(0xFF0072B2),
  Color(0xFFD55E00),
  Color(0xFFCC79A7),
  Color(0xFF999999),
];

/// The color of [peerId], the same everywhere in the tool.
///
/// It is one of the eight Okabe–Ito colors, readable with color blindness.
Color peerColor(String peerId) => _okabeIto[_fnv1a(peerId) % _okabeIto.length];

// 32-bit FNV-1a over the UTF-16 code units. The multiply by the prime
// 0x01000193 is split in two, so that no step passes 2^53 on the web.
int _fnv1a(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x193 + ((hash << 24) & 0xFFFFFFFF)) & 0xFFFFFFFF;
  }
  return hash;
}
