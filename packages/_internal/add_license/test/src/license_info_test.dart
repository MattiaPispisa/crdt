// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

@TestOn('vm')
library;

import 'dart:io';

import 'package:add_license/src/license_info.dart';
import 'package:add_license/src/spdx_license.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory packageRoot;

  setUp(() {
    packageRoot = Directory.systemTemp.createTempSync('license_info_test');
  });

  tearDown(() {
    packageRoot.deleteSync(recursive: true);
  });

  void writeLicense(String content) {
    File(path.join(packageRoot.path, 'LICENSE')).writeAsStringSync(content);
  }

  test('throws when there is no LICENSE file', () {
    expect(() => readLicenseInfo(packageRoot), throwsFormatException);
  });

  test('throws for an unrecognized license family', () {
    writeLicense('Some other license text');
    expect(() => readLicenseInfo(packageRoot), throwsFormatException);
  });

  test('throws when there is no copyright line', () {
    writeLicense('MIT License\n\nPermission is hereby granted...');
    expect(() => readLicenseInfo(packageRoot), throwsFormatException);
  });

  test('reads holder and year from a MIT LICENSE', () {
    writeLicense('MIT License\n\nCopyright (c) 2025 Mattia Pispisa\n');

    final info = readLicenseInfo(packageRoot);

    expect(info.family, SpdxLicenseFamily.mit);
    expect(info.year, '2025');
    expect(info.holder, 'Mattia Pispisa');
  });

  test('reads a year range', () {
    writeLicense('MIT License\n\nCopyright (c) 2023-2025 Mattia Pispisa\n');

    expect(readLicenseInfo(packageRoot).year, '2023-2025');
  });

  test('strips the BSD "All rights reserved." trailer', () {
    writeLicense(
      'BSD 3-Clause License\n\n'
      'Copyright (c) 2025 Mattia Pispisa All rights reserved.\n',
    );

    expect(readLicenseInfo(packageRoot).holder, 'Mattia Pispisa');
  });
}
