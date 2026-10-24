// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:add_license/add_license.dart';
import 'package:args/args.dart';
import 'package:en_logger/en_logger.dart';
import 'package:path/path.dart' as path;

final _logger = EnLogger(handlers: [PrintLogHandler()]);

final _parser = ArgParser()
  ..addFlag(
    'check',
    help: 'Report files missing the header instead of writing it.',
  )
  ..addOption(
    'root',
    help: 'The package root to scan. Defaults to the working directory.',
  );

/// Stamps (or, with `--check`, verifies) the SPDX license header on every
/// `.dart` file of a package, read from its own `LICENSE` file.
///
/// Usage: `dart run add_license:add_license [--check] [--root <path>]`.
void main(List<String> arguments) {
  final ArgResults args;
  try {
    args = _parser.parse(arguments);
  } on FormatException catch (error) {
    stderr
      ..writeln(error.message)
      ..writeln(_parser.usage);
    exitCode = 64;
    return;
  }

  final root = Directory(args['root'] as String? ?? Directory.current.path);
  final name = path.basename(root.path);
  final check = args['check'] as bool;

  LicenseReport report;
  try {
    report = check ? checkLicense(root) : applyLicense(root);
  } on FormatException catch (error) {
    _logger.error('$name: ${error.message}');
    exitCode = 1;
    return;
  }

  if (check) {
    if (report.isComplete) {
      _logger.info('$name: every .dart file has the license header.');
      return;
    }
    for (final file in report.missing) {
      _logger.error('Missing license header: ${file.path}');
    }
    exitCode = 1;
    return;
  }

  if (report.added.isEmpty) {
    _logger.info('$name: every .dart file already had the license header.');
    return;
  }
  for (final file in report.added) {
    _logger.info('Added license header: ${file.path}');
  }
}
