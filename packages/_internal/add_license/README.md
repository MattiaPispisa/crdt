# add_license

Private, unpublished package (`publish_to: none`) that stamps or checks the
SPDX license header on every `.dart` file of the workspace.

## What it does

For a package root, it:

1. Reads the package's own `LICENSE` file.
2. Works out the license family (`Apache-2.0`, `BSD-3-Clause`, `MIT`,
   `MPL-2.0`) and the copyright holder and year from it.
3. Walks every `.dart` file under the root — skipping `.dart_tool`,
   `build`, generated files, and any nested package (`example/`,
   `flutter_example/`, ...) — and either stamps the missing header
   (`applyLicense`) or reports it (`checkLicense`), without touching a
   file that already has one.

The header is two lines:

```dart
// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT
```

A package's license can change over time: since the family comes from the
`LICENSE` file, not a hardcoded value, swapping that file is enough to
change the header the next run writes.

## Usage

From a package's own folder:

```shell
dart run ../../_internal/add_license/bin/add_license.dart          # stamp
dart run ../../_internal/add_license/bin/add_license.dart --check  # verify
```

`melos run add_license` and `melos run add_license_check` run this across
every package of the workspace.

## Credits

The SPDX-only header and the license-family set (`apache`, `bsd`, `mit`,
`mpl`) follow [`google/addlicense`](https://github.com/google/addlicense)
(Apache-2.0), which does the same for several other ecosystems. This
package does not vendor its code — it is a small, Dart-native
implementation for this workspace's single convention (one SPDX-only
header, no full license text per file).
