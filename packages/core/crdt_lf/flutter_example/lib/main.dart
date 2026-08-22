import 'package:crdt_lf_flutter_example/shared/network.dart';
import 'package:flutter/material.dart';

import 'routing.dart';

const _kTitle = 'CRDT LF Examples';

/// Primary brand red, matching the documentation site (`--ifm-color-primary`).
const _kPrimary = Color(0xFFD04848);

void main() {
  runApp(const CrdtMaterialApp());
}

class CrdtMaterialApp extends StatelessWidget {
  const CrdtMaterialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return NetworkProvider(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: _kTitle,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: _kPrimary,
            primary: _kPrimary,
          ),
          listTileTheme: const ListTileThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
          scaffoldBackgroundColor: Colors.white,
          appBarTheme: const AppBarTheme(
            backgroundColor: _kPrimary,
            foregroundColor: Colors.white,
          ),
          tabBarTheme: const TabBarThemeData(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
          ),
        ),
        initialRoute: '/',
        routes: kRoutes,
      ),
    );
  }
}
