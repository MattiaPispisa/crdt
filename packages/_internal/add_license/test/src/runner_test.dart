// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

@TestOn('vm')
library;

import 'dart:io';

import 'package:add_license/src/runner.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('add_license_runner_test');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  void writeLicense({String holder = 'Mattia Pispisa', String year = '2025'}) {
    File(path.join(root.path, 'LICENSE')).writeAsStringSync(
      'MIT License\n\nCopyright (c) $year $holder\n',
    );
  }

  File writeDart(String relativePath, String content) {
    final file = File(path.join(root.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  group('dartFilesOf', () {
    test('finds every .dart file, sorted', () {
      writeDart('lib/b.dart', '');
      writeDart('lib/a.dart', '');
      writeDart('test/a_test.dart', '');

      final files = dartFilesOf(root).map((f) => f.path).toList();

      expect(files, [
        path.join(root.path, 'lib/a.dart'),
        path.join(root.path, 'lib/b.dart'),
        path.join(root.path, 'test/a_test.dart'),
      ]);
    });

    test('skips excluded directories', () {
      writeDart('.dart_tool/x.dart', '');
      writeDart('build/x.dart', '');
      writeDart('.dart_frog/x.dart', '');
      writeDart('lib/a.dart', '');

      expect(dartFilesOf(root).map((f) => f.path), [
        path.join(root.path, 'lib/a.dart'),
      ]);
    });

    test('skips generated files', () {
      writeDart('lib/model.g.dart', '');
      writeDart('lib/model.freezed.dart', '');
      writeDart('lib/model.mocks.dart', '');
      writeDart('lib/generated.dart', '');
      writeDart('lib/model.dart', '');

      expect(dartFilesOf(root).map((f) => f.path), [
        path.join(root.path, 'lib/model.dart'),
      ]);
    });

    test('does not descend into a nested package', () {
      writeDart('lib/a.dart', '');
      final nested = Directory(path.join(root.path, 'example'))..createSync();
      File(path.join(nested.path, 'pubspec.yaml')).writeAsStringSync('');
      writeDart('example/main.dart', '');

      expect(dartFilesOf(root).map((f) => f.path), [
        path.join(root.path, 'lib/a.dart'),
      ]);
    });
  });

  group('applyLicense', () {
    test('stamps every file missing the header', () {
      writeLicense();
      final file = writeDart('lib/a.dart', 'void main() {}\n');

      final report = applyLicense(root);

      expect(report.added.map((f) => f.path), [file.path]);
      expect(file.readAsStringSync(), contains('SPDX-License-Identifier'));
    });

    test('leaves an already-stamped file untouched', () {
      writeLicense();
      const content = '// SPDX-License-Identifier: MIT\n\nvoid main() {}\n';
      writeDart('lib/a.dart', content);

      final report = applyLicense(root);

      expect(report.added, isEmpty);
    });

    test('throws when the LICENSE is missing', () {
      writeDart('lib/a.dart', 'void main() {}\n');
      expect(() => applyLicense(root), throwsFormatException);
    });
  });

  group('checkLicense', () {
    test('reports files missing the header without changing them', () {
      writeLicense();
      final file = writeDart('lib/a.dart', 'void main() {}\n');

      final report = checkLicense(root);

      expect(report.isComplete, isFalse);
      expect(report.missing.map((f) => f.path), [file.path]);
      expect(file.readAsStringSync(), 'void main() {}\n');
    });

    test('is complete when every file already has a header', () {
      writeLicense();
      const content = '// SPDX-License-Identifier: MIT\n\nvoid main() {}\n';
      writeDart('lib/a.dart', content);

      expect(checkLicense(root).isComplete, isTrue);
    });
  });
}
