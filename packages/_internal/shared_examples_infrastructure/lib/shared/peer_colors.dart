import 'dart:ui';

/// Deterministic vibrant color from a peer id.
///
/// Shared by every presence rendering (mouse-style awareness cursors and
/// in-field text cursors), so the same peer gets the same color everywhere.
Color peerColorFor(String id) {
  const colors = [
    Color(0xFFE53935),
    Color(0xFFD81B60),
    Color(0xFF8E24AA),
    Color(0xFF5E35B1),
    Color(0xFF3949AB),
    Color(0xFF1E88E5),
    Color(0xFF00897B),
    Color(0xFF43A047),
    Color(0xFFF4511E),
    Color(0xFF6D4C41),
    Color(0xFF00ACC1),
    Color(0xFFFB8C00),
  ];
  return colors[id.hashCode.abs() % colors.length];
}
