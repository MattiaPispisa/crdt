import 'package:crdt_socket_sync/client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_example/user/_state.dart';

class UserConnectedItem {
  const UserConnectedItem._({
    required this.username,
    required this.surname,
    required this.color,
    required this.position,
    required this.isMe,
  });

  factory UserConnectedItem({
    required String username,
    required String surname,
    required Offset? position,
    required bool isMe,
  }) {
    return UserConnectedItem._(
      username: username,
      surname: surname,
      color: _getColorForUser(username, surname),
      position: position,
      isMe: isMe,
    );
  }

  final String username;
  final String surname;
  final Color color;
  final Offset? position;
  final bool isMe;

  @override
  bool operator ==(Object other) {
    if (other is UserConnectedItem) {
      return username == other.username &&
          surname == other.surname &&
          position == other.position &&
          color == other.color;
    }
    return false;
  }

  @override
  int get hashCode => Object.hash(username, surname, position, color);
}

Color _getColorForUser(String username, String surname) {
  // List of vibrant colors
  final List<Color> vibrantColors = [
    Colors.red.shade600,
    Colors.pink.shade600,
    Colors.purple.shade600,
    Colors.deepPurple.shade600,
    Colors.indigo.shade600,
    Colors.blue.shade600,
    Colors.lightBlue.shade600,
    Colors.cyan.shade600,
    Colors.teal.shade600,
    Colors.green.shade600,
    Colors.lightGreen.shade600,
    Colors.lime.shade600,
    Colors.yellow.shade600,
    Colors.amber.shade600,
    Colors.orange.shade600,
    Colors.deepOrange.shade600,
    Colors.brown.shade600,
    Colors.blueGrey.shade600,
  ];

  // Use the hash of the user ID to consistently assign the same color
  final hash = Object.hash(username, surname);
  final int colorIndex = hash.abs() % vibrantColors.length;
  return vibrantColors[colorIndex];
}

class UsersConnectedBuilder {
  const UsersConnectedBuilder({required this.clients, required this.me});


  final Iterable<ClientAwareness> clients;
  final ClientAwareness? me;

  List<UserConnectedItem> build() {
    final items = <UserConnectedItem>[];
    for (final client in clients) {
      final username = client.metadata['username'] as String?;
      final surname = client.metadata['surname'] as String?;

      if (username == null || surname == null) {
        continue;
      }

      final isMe = me == client;

      final xPosition = client.metadata['positionX'] as double?;
      final yPosition = client.metadata['positionY'] as double?;

      Offset? position;
      if (xPosition != null && yPosition != null) {
        position = Offset(xPosition, yPosition);
      }

      items.add(
        UserConnectedItem(
          username: username,
          surname: surname,
          position: position,
          isMe: isMe,
        ),
      );
    }
    return items;
  }
}
