/// A [CRDTDocumentStorage] backed by one plain file, for a local-first app
/// that wants no database.
///
/// Needs `dart:io`, which is why it is not in the main library.
library;

import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

export 'src/io/file_storage.dart';
