import 'package:flutter/material.dart';
import 'package:crdt_socket_sync_client_example/connect_page.dart';
import 'package:crdt_socket_sync_client_example/examples.dart';
import 'package:shared_examples_infrastructure/shared_examples_infrastructure.dart';

/// Application routes: the connect page, the shared examples home, and one
/// route per example (derived from [kExamples]).
final kRoutes = <String, WidgetBuilder>{
  '/': (context) => const ConnectPage(),
  '/examples':
      (context) => ExamplesHome(
        title: 'CRDT Socket Sync',
        logo: const Icon(Icons.sync_alt, size: 96),
        versionLabel: 'crdt_socket_sync',
        examples: kExamples,
        actions: homeActions,
      ),
  for (final example in kExamples) example.path: example.builder,
};
