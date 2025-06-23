import 'package:flutter/material.dart';

class UserConnectedItem {
  const UserConnectedItem({required this.username, required this.surname});

  final String username;
  final String surname;

  @override
  bool operator ==(Object other) {
    if (other is UserConnectedItem) {
      return username == other.username && surname == other.surname;
    }
    return false;
  }

  @override
  int get hashCode => username.hashCode ^ surname.hashCode;
}

class UsersConnected extends StatelessWidget {
  const UsersConnected({super.key, required this.users});

  final List<UserConnectedItem> users;

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

  Widget _user(BuildContext context, UserConnectedItem user) {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: CircleAvatar(
        backgroundColor: _getColorForUser(user),
        child: Text(
          '${user.username[0]}${user.surname[0]}'.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Color _getColorForUser(UserConnectedItem user) {
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
    final int colorIndex = user.hashCode.abs() % vibrantColors.length;
    return vibrantColors[colorIndex];
  }
}
