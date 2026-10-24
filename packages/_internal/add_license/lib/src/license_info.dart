// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:add_license/src/spdx_license.dart';
import 'package:path/path.dart' as path;

/// What a package's `LICENSE` file says: the family, and who holds the
/// copyright and since when.
class LicenseInfo {
  /// Creates the parsed info of a `LICENSE` file.
  const LicenseInfo({
    required this.family,
    required this.holder,
    required this.year,
  });

  /// The license family the file declares.
  final SpdxLicenseFamily family;

  /// The copyright holder, for example `Mattia Pispisa`.
  final String holder;

  /// The copyright year, or year range, as written in the file.
  final String year;
}

/// Reads and parses the `LICENSE` file of [packageRoot].
///
/// Throws a [FormatException] when the file is missing, its family is not
/// one of [SpdxLicenseFamily], or it has no `Copyright <year> <holder>`
/// line to read the header's year and holder from.
LicenseInfo readLicenseInfo(Directory packageRoot) {
  final file = File(path.join(packageRoot.path, 'LICENSE'));
  if (!file.existsSync()) {
    throw FormatException('No LICENSE file in ${packageRoot.path}');
  }

  final text = file.readAsStringSync();

  final family = detectSpdxLicenseFamily(text);
  if (family == null) {
    throw FormatException('Unrecognized license family in ${file.path}');
  }

  final match = _copyrightLine.firstMatch(text);
  if (match == null) {
    throw FormatException(
      'No "Copyright <year> <holder>" line found in ${file.path}',
    );
  }

  return LicenseInfo(
    family: family,
    holder: _stripTrailer(match.group(2)!),
    year: match.group(1)!,
  );
}

final _copyrightLine =
    RegExp(r'Copyright\s*(?:\(c\)\s*)?(\d{4}(?:-\d{4})?)\s+(.+)');

/// Drops the BSD-style `All rights reserved.` trailer some `LICENSE` files
/// add after the holder's name.
String _stripTrailer(String holder) {
  return holder.replaceAll(RegExp(r'\s*All rights reserved\.?\s*$'), '').trim();
}
