import 'package:hlc/hlc.dart';

void main() {
  // Simulate two peers in a distributed system
  final peer1Clock = HybridLogicalClock.now();
  final peer2Clock = HybridLogicalClock.now();

  print('Initial clocks:');
  print('Peer 1: $peer1Clock');
  print('Peer 2: $peer2Clock\n');

  // Simulate local events on peer 1
  print('Peer 1 performs some local events:');
  peer1Clock.localEvent(DateTime.now().millisecondsSinceEpoch);
  print('After first event: $peer1Clock');
  peer1Clock.localEvent(DateTime.now().millisecondsSinceEpoch);
  print('After second event: $peer1Clock\n');

  // Simulate local events on peer 2
  print('Peer 2 performs some local events:');
  peer2Clock.localEvent(DateTime.now().millisecondsSinceEpoch);
  print('After first event: $peer2Clock');
  peer2Clock.localEvent(DateTime.now().millisecondsSinceEpoch);
  print('After second event: $peer2Clock\n');

  // Simulate message exchange between peers
  print('Peer 1 sends a message to Peer 2:');
  final peer1ClockCopy = peer1Clock.copy();
  peer2Clock.receiveEvent(
    DateTime.now().millisecondsSinceEpoch,
    peer1ClockCopy,
  );
  print('Peer 2 clock after receiving message: $peer2Clock');
  print('Peer 1 clock remains unchanged: $peer1Clock\n');

  // Demonstrate causality
  print('Demonstrating causality:');
  print('Peer 1 clock happened before Peer 2 clock: ${peer1Clock.happenedBefore(peer2Clock)}');
  print('Peer 2 clock happened before Peer 1 clock: ${peer2Clock.happenedBefore(peer1Clock)}');
  print('Clocks are concurrent: ${peer1Clock.isConcurrentWith(peer2Clock)}\n');

  // Demonstrate serialization
  print('Demonstrating serialization:');
  final serialized = peer1Clock.toInt64();
  print('Serialized Peer 1 clock: $serialized');
  final deserialized = HybridLogicalClock.fromInt64(serialized);
  print('Deserialized clock: $deserialized');
  print('Original and deserialized are equal: ${peer1Clock == deserialized}');
}
