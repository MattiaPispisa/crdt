import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:en_logger/en_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_example/_logger.dart';
import 'package:flutter_example/_persistence.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kUsernameKey = 'username';
const _kSurnameKey = 'surname';
const _kUrlKey = 'url';

class UserState extends ChangeNotifier {
  UserState._({
    required PeerId userId,
    required String username,
    required String surname,
    required String url,
    required EnLogger logger,
    required SharedPreferences preferences,
  }) : _surname = surname,
       _username = username,
       _userId = userId,
       _url = url,
       _logger = logger,
       _preferences = preferences;

  factory UserState({
    required EnLogger logger,
    required SharedPreferences preferences,
    required String defaultUrl,
    required String defaultUsername,
    required String defaultSurname,
  }) {
    final username = preferences.getString(_kUsernameKey) ?? defaultUsername;
    final surname = preferences.getString(_kSurnameKey) ?? defaultSurname;
    final url = preferences.getString(_kUrlKey) ?? defaultUrl;
    return UserState._(
      userId: PeerId.generate(),
      username: username,
      surname: surname,
      url: url,
      logger: logger,
      preferences: preferences,
    );
  }

  String _username;
  String _surname;
  String _url;
  final PeerId _userId;
  final EnLogger _logger;
  final SharedPreferences _preferences;

  String get username => _username;
  String get surname => _surname;
  String get url => _url;
  PeerId get userId => _userId;

  void setUsername(String username) {
    _username = username;
    _logger.info('Username set to $username');
    _preferences.setString(_kUsernameKey, username);
    notifyListeners();
  }

  void setSurname(String surname) {
    _surname = surname;
    _logger.info('Surname set to $surname');
    _preferences.setString(_kSurnameKey, surname);
    notifyListeners();
  }

  void setUrl(String url) {
    _url = url;
    _logger.info('Url set to $url');
    _preferences.setString(_kUrlKey, url);
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
          (context) => UserState(
            logger: context.loggerInstance('UserState'),
            preferences: context.preferences(),
            defaultUrl: url,
            defaultUsername: '${Random().nextInt(1000000)}_user',
            defaultSurname: '${Random().nextInt(1000000)}_surname',
          ),
      child: child,
    );
  }
}

extension UserStateProviderHelper on BuildContext {
  UserState get user => Provider.of<UserState>(this);
}
