// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:add_license/src/license_info.dart';
import 'package:add_license/src/spdx_license.dart';

/// The marker [hasHeader] looks for. Matches `google/addlicense`'s own check,
/// so a file it already stamped is left alone.
const spdxMarker = 'SPDX-License-Identifier';

/// How far into a file [hasHeader] looks for [spdxMarker].
const _searchWindow = 200;

/// Builds the two-line `//` header for [info]: a copyright line and an
/// [spdxMarker] line.
String buildHeader(LicenseInfo info) =>
    '// Copyright ${info.year} ${info.holder}\n'
    '// $spdxMarker: ${info.family.spdxId}';

/// Whether [content] already carries a license header.
bool hasHeader(String content) {
  final window = content.length > _searchWindow
      ? content.substring(0, _searchWindow)
      : content;
  return window.contains(spdxMarker);
}

/// Returns [content] with [info]'s header prepended, or [content] itself
/// when [hasHeader] is already true.
String applyHeader(String content, LicenseInfo info) {
  if (hasHeader(content)) {
    return content;
  }
  return '${buildHeader(info)}\n\n$content';
}
