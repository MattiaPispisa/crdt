import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:crdt_socket_sync_client_example/generated.dart';
import 'package:crdt_socket_sync_client_example/gzip_compression.dart';
import 'package:crdt_socket_sync_client_example/socket_sync.dart';
import 'package:en_logger/en_logger.dart';
import 'package:factory_example/factory_example.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Default server URL; override at build time with
/// `--dart-define=SERVER_URL=wss://...`.
const _kDefaultUrl = String.fromEnvironment(
  'SERVER_URL',
  defaultValue: 'ws://localhost:8080',
);

/// Enable gzip compression at build time with
/// `--dart-define=USE_COMPRESSION=true`. The target server must run the
/// matching compressor (e.g. the `example` server started with `--compress`),
/// because compression is symmetric.
const _kUseCompression = bool.fromEnvironment('USE_COMPRESSION');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  CRDTHive.initialize();
  final settings = await Hive.openBox<String>('settings');

  runApp(
    ExampleApp(
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
      links: const AppBarLinks(
        docsUrl: 'https://mattiapispisa.github.io/crdt/',
        pubDevUrl: 'https://pub.dev/packages/crdt_socket_sync',
        pubTooltip: 'crdt_socket_sync on pub.dev',
      ),
      primaryColor: Colors.deepPurple,
      sync: SocketSync(
        settings: settings,
        defaultUrl: _kDefaultUrl,
        logger: EnLogger(defaultPrefixFormat: const PrefixFormat.snakeSquare())
          ..addHandler(PrinterHandler()),
        // The analyzer reads USE_COMPRESSION without its define.
        // ignore: avoid_redundant_argument_values
        compressor: _kUseCompression ? const GzipCompression() : null,
      ),
      storage: (peer) => CRDTHive.open(),
    ),
  );
}
