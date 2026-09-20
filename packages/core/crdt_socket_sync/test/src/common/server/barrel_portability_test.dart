@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `server.dart` and `relay_server.dart` are the entry points an embedder
/// imports to host the protocol on a transport of its own — Dart Frog, shelf,
/// a worker runtime. The moment one of them pulls in `dart:io`, that stops
/// working, and it stops working at compile time in someone else's package,
/// far from whatever import caused it.
///
/// So: walk what each barrel reaches **inside this package** and check.
/// Other packages are out of scope — this is the invariant we control.
void main() {
  group('transport-free barrels', () {
    for (final barrel in ['lib/server.dart', 'lib/relay_server.dart']) {
      test('$barrel does not reach dart:io', () {
        final offenders = _filesImportingDartIo(barrel);

        expect(
          offenders,
          isEmpty,
          reason: '$barrel transitively imports dart:io through:\n'
              '${offenders.join('\n')}\n'
              'Keep `dart:io` behind the web_socket_*.dart barrels.',
        );
      });
    }

    test('the dart:io barrels still reach it, so the check can fail', () {
      // A guard on the guard: if the walker silently stopped resolving
      // imports, every barrel would look clean and the tests above would
      // pass for the wrong reason.
      expect(_filesImportingDartIo('lib/web_socket_server.dart'), isNotEmpty);
      expect(
        _filesImportingDartIo('lib/web_socket_relay_server.dart'),
        isNotEmpty,
      );
    });
  });
}

final _directive = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// Files reachable from [entry] (within this package) that import `dart:io`.
List<String> _filesImportingDartIo(String entry) {
  final offenders = <String>[];
  final seen = <String>{};
  final queue = <String>[p.normalize(entry)];

  while (queue.isNotEmpty) {
    final path = queue.removeLast();
    if (!seen.add(path)) {
      continue;
    }

    final file = File(path);
    if (!file.existsSync()) {
      continue;
    }

    for (final match in _directive.allMatches(file.readAsStringSync())) {
      final uri = match.group(1)!;

      if (uri == 'dart:io') {
        offenders.add(path);
        continue;
      }

      final resolved = _resolve(uri, from: path);
      if (resolved != null) {
        queue.add(resolved);
      }
    }
  }

  return offenders;
}

/// Maps a directive [uri] to a path in this package, or `null` when it points
/// somewhere we do not walk (another package, or the SDK).
String? _resolve(String uri, {required String from}) {
  const selfPrefix = 'package:crdt_socket_sync/';

  if (uri.startsWith(selfPrefix)) {
    return p.normalize(p.join('lib', uri.substring(selfPrefix.length)));
  }

  if (uri.startsWith('dart:') || uri.startsWith('package:')) {
    return null;
  }

  return p.normalize(p.join(p.dirname(from), uri));
}
