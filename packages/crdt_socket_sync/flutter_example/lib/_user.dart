import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class User extends ChangeNotifier {
  User({required this.userId});

  final PeerId userId;
}

class UserProvider extends StatelessWidget {
  const UserProvider({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<User>(
      create: (context) => User(userId: PeerId.generate()),
      child: child,
    );
  }
}

extension UserHelper on BuildContext {
  PeerId get user => watch<User>().userId;
}
