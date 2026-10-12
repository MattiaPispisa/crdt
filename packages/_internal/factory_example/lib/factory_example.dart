/// The whole example app of the CRDT packages, built from a sync and a
/// storage.
///
/// An app passes an [ExampleSync] and an [ExampleStorage] to [ExampleApp];
/// the screens, the documents and their lifecycle come from here.
library;

import 'package:factory_example/app/example_app.dart';
import 'package:factory_example/app/example_sync.dart';

export 'app/example_app.dart';
export 'app/example_sync.dart';
export 'examples/examples_home.dart' show PackageVersion;
export 'shared/app_bar_links.dart';
export 'shared/peer_colors.dart';
export 'shared/text_cursor_presence.dart';
