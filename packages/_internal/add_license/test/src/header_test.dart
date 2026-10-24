// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:add_license/src/header.dart';
import 'package:add_license/src/license_info.dart';
import 'package:add_license/src/spdx_license.dart';
import 'package:test/test.dart';

void main() {
  const info = LicenseInfo(
    family: SpdxLicenseFamily.mit,
    holder: 'Mattia Pispisa',
    year: '2025',
  );

  test('buildHeader writes the copyright and SPDX lines', () {
    expect(
      buildHeader(info),
      '// Copyright 2025 Mattia Pispisa\n'
      '// SPDX-License-Identifier: MIT',
    );
  });

  group('hasHeader', () {
    test('is false for a file with no header', () {
      expect(hasHeader('void main() {}\n'), isFalse);
    });

    test('is true right after applyHeader', () {
      expect(hasHeader(applyHeader('void main() {}\n', info)), isTrue);
    });

    test('only looks at the start of the file', () {
      final farAway = '${'x' * 300}SPDX-License-Identifier: MIT';
      expect(hasHeader(farAway), isFalse);
    });
  });

  group('applyHeader', () {
    test('prepends the header before the content', () {
      expect(
        applyHeader('void main() {}\n', info),
        '// Copyright 2025 Mattia Pispisa\n'
        '// SPDX-License-Identifier: MIT\n'
        '\n'
        'void main() {}\n',
      );
    });

    test('is a no-op when the content already has a header', () {
      const content = '// SPDX-License-Identifier: MIT\n\nvoid main() {}\n';
      expect(applyHeader(content, info), content);
    });

    test('leaves ignore_for_file directives first among the comments', () {
      const content = '// ignore_for_file: avoid_print\n\nvoid main() {}\n';
      final result = applyHeader(content, info);
      expect(result, startsWith('// Copyright'));
      expect(result, contains('// ignore_for_file: avoid_print'));
    });
  });
}
