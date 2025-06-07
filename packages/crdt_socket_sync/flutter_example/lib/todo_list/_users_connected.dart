import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/material.dart';

class UsersConnected extends StatelessWidget {
  const UsersConnected({super.key, required this.users});

  final List<PeerId> users;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      scrollDirection: Axis.horizontal,
      itemCount: users.length,
      itemBuilder: (context, index) {
        return _user(context, users[index]);
      },
    );
  }

  Widget _user(BuildContext context, PeerId user) {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: CircleAvatar(
        backgroundColor: _getColorForUser(user),
        child: Text(
          user.id.substring(0, 2).toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Color _getColorForUser(PeerId user) {
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
    final int colorIndex = user.id.hashCode.abs() % vibrantColors.length;
    return vibrantColors[colorIndex];
  }
}
