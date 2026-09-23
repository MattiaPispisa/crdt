import 'package:crdt_lf_cli/src/bundles/bundles.dart';
import 'package:crdt_lf_cli/src/project/project_options.dart';
import 'package:crdt_lf_cli/src/project/project_plan.dart';
import 'package:mason/mason.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Every project the options allow today.
final _allOptions = [
  for (final storage in StorageKind.values)
    if (storage != StorageKind.none)
      for (final handler in HandlerKind.values)
        ProjectOptions(
          name: 'notes',
          server: ServerKind.plain,
          serverStorage: storage,
          handler: handler,
        ),
];

void main() {
  test('every brick of every plan has a bundle', () {
    for (final options in _allOptions) {
      for (final run in planProject(options)) {
        expect(bundles, contains(run.brick), reason: '$run');
      }
    }
  });

  // The bricks compose because each one owns its own files. Two bricks that
  // write the same path would overwrite each other.
  test('no two bricks of a plan write the same file', () {
    for (final options in _allOptions) {
      final owners = <String, String>{};
      for (final run in planProject(options)) {
        for (final file in bundles[run.brick]!.files) {
          final path = p.normalize(
            p.join(run.directory, file.path.render(run.vars)),
          );
          final owner = owners[path];
          expect(
            owner,
            isNull,
            reason: '$path is written by $owner and ${run.brick}',
          );
          owners[path] = run.brick;
        }
      }
    }
  });

  test('a sqlite server depends on its adapter, sorted and once each', () {
    final plan = planProject(
      ProjectOptions(
        name: 'notes',
        server: ServerKind.plain,
        serverStorage: StorageKind.sqlite,
        handler: HandlerKind.none,
      ),
    );

    final server = plan.singleWhere((run) => run.brick == 'server_plain');
    expect(server.directory, 'notes_server');
    expect(
      server.vars['dependencies'],
      '  crdt_lf: "^5.0.0"\n'
      '  crdt_lf_persistence: "^0.1.1"\n'
      '  crdt_lf_sqlite: "^0.3.1"\n'
      '  crdt_socket_sync: "^0.9.0"\n'
      '  path: "^1.9.0"',
    );
    expect(server.vars['storage_implemented'], isTrue);

    final storage = plan.singleWhere((run) => run.brick == 'storage_sqlite');
    expect(storage.directory, 'notes_server');

    final workspace = plan.singleWhere((run) => run.brick == 'workspace');
    expect(workspace.vars['members'], '  - notes_shared\n  - notes_server');
  });

  test('a hand-written backend skips the server test', () {
    final plan = planProject(
      ProjectOptions(
        name: 'notes',
        server: ServerKind.plain,
        serverStorage: StorageKind.infrastructure,
        handler: HandlerKind.none,
      ),
    );

    final server = plan.singleWhere((run) => run.brick == 'server_plain');
    expect(server.vars['storage_implemented'], isFalse);
  });
}
