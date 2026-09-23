/// A value the user picks with a command-line flag or a prompt.
abstract interface class ProjectChoice {
  /// The value as it is written on the command line.
  String get flag;

  /// What the value means, shown in the prompt and in `--help`.
  String get help;
}

/// The server a project gets.
enum ServerKind implements ProjectChoice {
  /// No server.
  none('none', 'No server.'),

  /// A `crdt_socket_sync` WebSocket server on `dart:io`.
  plain('plain', 'A WebSocket server on dart:io, with crdt_socket_sync.');

  const ServerKind(this.flag, this.help);

  @override
  final String flag;

  @override
  final String help;
}

/// Where a package keeps its documents.
enum StorageKind implements ProjectChoice {
  /// Only in memory: lost when the process ends.
  none('none', 'Only in memory.'),

  /// A backend written by hand, generated as a skeleton to fill in.
  infrastructure(
    'infrastructure',
    'A backend you write by hand. You get a skeleton to fill in.',
  ),

  /// `crdt_lf_hive`.
  hive('hive', 'Hive, with crdt_lf_hive.'),

  /// `crdt_lf_drift`.
  drift('drift', 'Drift, with crdt_lf_drift.'),

  /// `crdt_lf_sqlite`.
  sqlite('sqlite', 'SQLite, with crdt_lf_sqlite.');

  const StorageKind(this.flag, this.help);

  @override
  final String flag;

  @override
  final String help;

  /// Whether the generated backend works without more code.
  bool get isImplemented => this != infrastructure;
}

/// The handlers the document starts with.
enum HandlerKind implements ProjectChoice {
  /// No handler: the schema is empty.
  none('none', 'No handler yet.'),

  /// One `CRDTFugueTextHandler`.
  fugueText('fugue_text', 'One collaborative text (CRDTFugueTextHandler).');

  const HandlerKind(this.flag, this.help);

  @override
  final String flag;

  @override
  final String help;
}

/// Finds the value of [values] whose [ProjectChoice.flag] is [flag].
///
/// Throws [ArgumentError] when no value has that flag.
T choiceFromFlag<T extends ProjectChoice>(List<T> values, String flag) {
  for (final value in values) {
    if (value.flag == flag) {
      return value;
    }
  }
  throw ArgumentError.value(flag, 'flag', 'Unknown value');
}

/// What `crdt_lf create` generates.
class ProjectOptions {
  /// Creates the options of the project [name].
  ///
  /// Throws [ArgumentError] when [name] is not a valid package name, or when
  /// the options describe nothing to generate. See [validate].
  ProjectOptions({
    required this.name,
    required this.server,
    required this.serverStorage,
    required this.handler,
  }) {
    validate();
  }

  /// The project name. Every package is named after it.
  final String name;

  /// The server the project gets.
  final ServerKind server;

  /// Where the server keeps its documents. Ignored without a [server].
  final StorageKind serverStorage;

  /// The handlers the document starts with.
  final HandlerKind handler;

  /// Whether the project has a server.
  bool get hasServer => server != ServerKind.none;

  static final _packageName = RegExp(r'^[a-z][a-z0-9_]*$');

  /// Checks that these options describe a project that can be generated.
  ///
  /// Throws [ArgumentError] when [name] is not a lowercase snake_case
  /// identifier, when there is no server, or when the server keeps its
  /// documents only in memory.
  void validate() {
    if (!_packageName.hasMatch(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'Use lowercase letters, digits and underscores, starting with a '
            'letter',
      );
    }
    if (!hasServer) {
      throw ArgumentError('Pick a server: there is nothing to generate.');
    }
    if (serverStorage == StorageKind.none) {
      throw ArgumentError.value(
        serverStorage.flag,
        'serverStorage',
        'The server needs a storage',
      );
    }
  }
}
