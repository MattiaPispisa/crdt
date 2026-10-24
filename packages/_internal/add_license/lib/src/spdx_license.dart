// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

/// The license families this package recognizes, mirroring the `-l` flag
/// of [`google/addlicense`](https://github.com/google/addlicense): `apache`,
/// `bsd`, `mit`, `mpl`.
enum SpdxLicenseFamily {
  /// Apache License 2.0.
  apache2,

  /// A BSD-style license. Mapped to the 3-clause variant: `addlicense`'s own
  /// `bsd` template is a generic BSD-style notice, not tied to a specific
  /// clause count.
  bsd3,

  /// MIT License.
  mit,

  /// Mozilla Public License 2.0.
  mpl2,
}

/// Where [SpdxLicenseFamily] gets its SPDX identifier from.
extension SpdxLicenseFamilyId on SpdxLicenseFamily {
  /// The SPDX identifier used in a license header, for example in
  /// `SPDX-License-Identifier: MIT`.
  String get spdxId => switch (this) {
        SpdxLicenseFamily.apache2 => 'Apache-2.0',
        SpdxLicenseFamily.bsd3 => 'BSD-3-Clause',
        SpdxLicenseFamily.mit => 'MIT',
        SpdxLicenseFamily.mpl2 => 'MPL-2.0',
      };
}

/// The phrase every family's `LICENSE` file opens with.
const _familyMarkers = {
  'Apache License': SpdxLicenseFamily.apache2,
  'MIT License': SpdxLicenseFamily.mit,
  'BSD': SpdxLicenseFamily.bsd3,
  'Mozilla Public License': SpdxLicenseFamily.mpl2,
};

/// Finds the license family a package's `LICENSE` file declares.
///
/// Matches the first marker in [_familyMarkers] found anywhere in [text].
/// Returns `null` when none matches, so a package with an unrecognized
/// `LICENSE` is reported rather than guessed at.
SpdxLicenseFamily? detectSpdxLicenseFamily(String text) {
  for (final entry in _familyMarkers.entries) {
    if (text.contains(entry.key)) {
      return entry.value;
    }
  }
  return null;
}
