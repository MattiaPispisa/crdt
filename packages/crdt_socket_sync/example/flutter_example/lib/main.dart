import 'package:flutter/material.dart';
import 'package:flutter_example/_logger.dart';
import 'package:flutter_example/_router.dart';
import 'package:flutter_example/user/_state.dart';

const _kUrl = 'ws://0.0.0.0:8080';
const _kTitle = 'Flutter Client Example';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return LoggerProvider(
      child: UserProvider(
        url: _kUrl,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: _kTitle,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          ),
          routerConfig: router,
        ),
      ),
    );
  }
}
