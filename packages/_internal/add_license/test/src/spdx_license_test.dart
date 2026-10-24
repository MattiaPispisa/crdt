// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:add_license/src/spdx_license.dart';
import 'package:test/test.dart';

void main() {
  group('detectSpdxLicenseFamily', () {
    test('recognizes MIT', () {
      expect(
        detectSpdxLicenseFamily('MIT License\n\nCopyright (c) 2025 X'),
        SpdxLicenseFamily.mit,
      );
    });

    test('recognizes Apache-2.0', () {
      expect(
        detectSpdxLicenseFamily('                Apache License\n'),
        SpdxLicenseFamily.apache2,
      );
    });

    test('recognizes a BSD license', () {
      expect(
        detectSpdxLicenseFamily('BSD 3-Clause License\n'),
        SpdxLicenseFamily.bsd3,
      );
    });

    test('recognizes MPL-2.0', () {
      expect(
        detectSpdxLicenseFamily('Mozilla Public License, v. 2.0\n'),
        SpdxLicenseFamily.mpl2,
      );
    });

    test('returns null for an unrecognized license', () {
      expect(detectSpdxLicenseFamily('Some other license text'), isNull);
    });
  });

  group('SpdxLicenseFamilyId', () {
    test('maps every family to its SPDX identifier', () {
      expect(SpdxLicenseFamily.apache2.spdxId, 'Apache-2.0');
      expect(SpdxLicenseFamily.bsd3.spdxId, 'BSD-3-Clause');
      expect(SpdxLicenseFamily.mit.spdxId, 'MIT');
      expect(SpdxLicenseFamily.mpl2.spdxId, 'MPL-2.0');
    });
  });
}
