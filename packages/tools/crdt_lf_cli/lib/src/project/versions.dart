/// The version constraint a generated pubspec uses for each package.
///
/// The packages of this repository must allow the version in their own
/// pubspec, so a project generated today resolves against the latest
/// release. A test checks it.
const packageVersions = <String, String>{
  // Packages of this repository.
  'crdt_lf': '^5.0.0',
  'crdt_lf_drift': '^0.3.1',
  'crdt_lf_hive': '^0.5.1',
  'crdt_lf_persistence': '^0.1.1',
  'crdt_lf_sqlite': '^0.3.1',
  'crdt_socket_sync': '^0.9.0',

  // Other packages.
  'hive': '^2.0.0',
  'lints': '^6.0.0',
  'path': '^1.9.0',
  'test': '^1.24.0',
};

/// The packages of [packageVersions] that live in this repository.
const repositoryPackages = <String>{
  'crdt_lf',
  'crdt_lf_drift',
  'crdt_lf_hive',
  'crdt_lf_persistence',
  'crdt_lf_sqlite',
  'crdt_socket_sync',
};
