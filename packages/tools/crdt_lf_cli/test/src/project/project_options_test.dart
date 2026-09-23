import 'package:crdt_lf_cli/src/project/project_options.dart';
import 'package:test/test.dart';

void main() {
  ProjectOptions options({
    String name = 'notes',
    ServerKind server = ServerKind.plain,
    StorageKind serverStorage = StorageKind.sqlite,
  }) {
    return ProjectOptions(
      name: name,
      server: server,
      serverStorage: serverStorage,
      handler: HandlerKind.fugueText,
    );
  }

  group('ProjectOptions', () {
    test('accepts a snake_case name', () {
      expect(options(name: 'my_notes2').name, 'my_notes2');
    });

    test('rejects a name that is not a package name', () {
      for (final name in ['', 'Notes', '2notes', 'my-notes', '_notes']) {
        expect(() => options(name: name), throwsArgumentError, reason: name);
      }
    });

    test('rejects a project with nothing to generate', () {
      expect(
        () => options(server: ServerKind.none, serverStorage: StorageKind.none),
        throwsArgumentError,
      );
    });

    test('rejects a server that keeps its documents only in memory', () {
      expect(
        () => options(serverStorage: StorageKind.none),
        throwsArgumentError,
      );
    });
  });

  group('choiceFromFlag', () {
    test('finds the value written on the command line', () {
      expect(
        choiceFromFlag(HandlerKind.values, 'fugue_text'),
        HandlerKind.fugueText,
      );
    });

    test('throws on an unknown flag', () {
      expect(
        () => choiceFromFlag(StorageKind.values, 'mongo'),
        throwsArgumentError,
      );
    });
  });

  test('only the hand-written backend needs more code', () {
    expect(
      [
        for (final kind in StorageKind.values)
          if (!kind.isImplemented) kind,
      ],
      [StorageKind.infrastructure],
    );
  });
}
