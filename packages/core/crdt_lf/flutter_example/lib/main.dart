import 'package:crdt_lf_flutter_example/generated.dart';
import 'package:crdt_lf_flutter_example/simulated/simulated_sync.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:factory_example/factory_example.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  CRDTHive.initialize();

  runApp(
    ExampleApp(
      title: 'CRDT LF Examples',
      logo: Image.asset('assets/images/logo.png', height: 120),
      versions: [
        PackageVersion(name: 'crdt_lf', version: crdt_lf_version),
        PackageVersion(
          name: 'crdt_lf_flutter',
          version: crdt_lf_flutter_version,
        ),
      ],
      links: const AppBarLinks(
        docsUrl: 'https://mattiapispisa.github.io/crdt/',
        pubDevUrl: 'https://pub.dev/packages/crdt_lf',
        pubTooltip: 'crdt_lf on pub.dev',
      ),
      // The brand red of the documentation site (`--ifm-color-primary`).
      primaryColor: const Color(0xFFD04848),
      sync: SimulatedSync(),
      // Each simulated peer keeps its own copy, as two devices would.
      storage:
          (peer) => CRDTHive.open(
            changesBoxName: '${peer.key}_changes',
            snapshotsBoxName: '${peer.key}_snapshots',
            peerIdsBoxName: '${peer.key}_peer_ids',
            registryBoxName: '${peer.key}_documents',
          ),
    ),
  );
}
