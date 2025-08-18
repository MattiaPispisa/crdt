import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:en_logger/en_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_example/_logger.dart';
import 'package:provider/provider.dart';

class UserState extends ChangeNotifier {
  UserState({
    required PeerId userId,
    required String username,
    required String surname,
    required String url,
    required EnLogger logger,
  }) : _surname = surname,
       _username = username,
       _userId = userId,
       _url = url,
       _logger = logger;

  factory UserState.random({required String url, required EnLogger logger}) {
    return UserState(
      userId: PeerId.generate(),
      username: '${Random().nextInt(1000000)}_user',
      surname: '${Random().nextInt(1000000)}_surname',
      logger: logger,
      url: url,
    );
  }

  String _username;
  String _surname;
  String _url;
  final PeerId _userId;
  final EnLogger _logger;

  String get username => _username;
  String get surname => _surname;
  String get url => _url;
  PeerId get userId => _userId;

  void setUsername(String username) {
    _username = username;
    _logger.info('Username set to $username');
    notifyListeners();
  }

  void setSurname(String surname) {
    _surname = surname;
    _logger.info('Surname set to $surname');
    notifyListeners();
  }

  void setUrl(String url) {
    _url = url;
    _logger.info('Url set to $url');
    notifyListeners();
  }
}

class UserProvider extends StatelessWidget {
  const UserProvider({super.key, required this.url, required this.child});

  final String url;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<UserState>(
      create:
          (context) => UserState.random(
            url: url,
            logger: context.loggerInstance('UserState'),
          ),
      child: child,
    );
  }
}

extension UserStateProviderHelper on BuildContext {
  UserState get user => Provider.of<UserState>(this);
}
