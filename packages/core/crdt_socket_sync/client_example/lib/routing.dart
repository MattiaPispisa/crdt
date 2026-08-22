import 'package:flutter/material.dart';
import 'package:crdt_socket_sync_client_example/connect_page.dart';
import 'package:crdt_socket_sync_client_example/examples.dart';
import 'package:crdt_socket_sync_client_example/generated.dart';
import 'package:shared_examples_infrastructure/shared_examples_infrastructure.dart';

/// Application routes: the connect page, the shared examples home, and one
/// route per example (derived from [kExamples]).
final kRoutes = <String, WidgetBuilder>{
  '/': (context) => const ConnectPage(),
  '/examples':
      (context) => ExamplesHome(
        title: 'CRDT Socket Sync',
        logo: const Icon(Icons.sync_alt, size: 96),
        versions: [
          PackageVersion(
            name: 'crdt_socket_sync',
            version: crdt_socket_sync_version,
          ),
          PackageVersion(name: 'crdt_lf', version: crdt_lf_version),
          PackageVersion(
            name: 'crdt_lf_flutter',
            version: crdt_lf_flutter_version,
          ),
        ],
        examples: kExamples,
        actions: homeActions,
      ),
  for (final example in kExamples) example.path: example.builder,
};
