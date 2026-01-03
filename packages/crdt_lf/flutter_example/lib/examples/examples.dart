import 'package:flutter/material.dart';

import '../routing.dart';

class Examples extends StatelessWidget {
  const Examples({super.key});

  Widget _listTile(BuildContext context, RouteData route) {
    return ListTile(
      title: Text(route.name),
      onTap: () => Navigator.of(context).pushNamed(route.path),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const SizedBox(),
        title: const Text('CRDT LF Examples'),
      ),
      body: ListView.builder(
        itemCount: kExampleRoutes.length,
        itemBuilder:
            (context, index) => _listTile(context, kExampleRoutes[index]),
      ),
    );
  }
}
