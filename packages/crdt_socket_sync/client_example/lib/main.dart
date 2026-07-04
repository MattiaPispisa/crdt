import 'package:flutter/material.dart';
import 'package:crdt_socket_sync_client_example/_logger.dart';
import 'package:crdt_socket_sync_client_example/_persistence.dart';
import 'package:crdt_socket_sync_client_example/routing.dart';
import 'package:crdt_socket_sync_client_example/user/_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Default server URL; override at build time with
/// `--dart-define=SERVER_URL=wss://...`.
const _kDefaultUrl = String.fromEnvironment(
  'SERVER_URL',
  defaultValue: 'ws://localhost:8080',
);
const _kTitle = 'CRDT Socket Sync — Client';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();

  runApp(MyApp(preferences: preferences));
}

/// Root widget of the socket client example.
class MyApp extends StatelessWidget {
  /// Creates the app with the resolved [preferences].
  const MyApp({super.key, required this.preferences});

  /// Persisted preferences (server URL, display name).
  final SharedPreferences preferences;

  @override
  Widget build(BuildContext context) {
    return PersistenceProvider(
      preferences: preferences,
      child: LoggerProvider(
        child: UserProvider(
          url: _kDefaultUrl,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            title: _kTitle,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            ),
            initialRoute: '/',
            routes: kRoutes,
          ),
        ),
      ),
    );
  }
}
