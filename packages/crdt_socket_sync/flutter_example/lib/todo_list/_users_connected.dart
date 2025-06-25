import 'package:flutter/material.dart';
import 'package:flutter_example/todo_list/_user_connected_item.dart';

class AvatarUsersConnected extends StatelessWidget {
  const AvatarUsersConnected({super.key, required this.users});

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
        backgroundColor: user.color,
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
}
