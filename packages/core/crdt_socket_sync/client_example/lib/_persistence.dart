import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PersistenceProvider extends StatelessWidget {
  const PersistenceProvider({
    required this.preferences,
    required this.child,
    super.key,
  });

  final SharedPreferences preferences;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Provider(create: (_) => preferences, child: child);
  }
}

extension PersistenceProviderHelper on BuildContext {
  SharedPreferences preferences() =>
      Provider.of<SharedPreferences>(this, listen: false);
}
