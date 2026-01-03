import 'package:crdt_lf_flutter_example/shared/network.dart';
import 'package:flutter/material.dart';

import 'routing.dart';

const _kTitle = 'CRDT LF Examples';

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
        theme: ThemeData(primarySwatch: Colors.blue),
        initialRoute: '/',
        routes: kRoutes,
      ),
    );
  }
}
