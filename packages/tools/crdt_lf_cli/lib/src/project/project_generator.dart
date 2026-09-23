import 'dart:io';

import 'package:crdt_lf_cli/src/bundles/bundles.dart';
import 'package:crdt_lf_cli/src/project/project_options.dart';
import 'package:crdt_lf_cli/src/project/project_plan.dart';
import 'package:mason/mason.dart';
import 'package:path/path.dart' as p;

/// Builds a [MasonGenerator] from a [MasonBundle].
typedef GeneratorFromBundle = Future<MasonGenerator> Function(
  MasonBundle bundle,
);

/// Writes the files of a project, brick by brick.
class ProjectGenerator {
  /// Creates a generator that reports to [logger].
  ///
  /// [generatorFromBundle] and [bundleByName] replace the real bricks in
  /// tests.
  ProjectGenerator({
    required Logger logger,
    GeneratorFromBundle? generatorFromBundle,
    Map<String, MasonBundle>? bundleByName,
  })  : _logger = logger,
        _generatorFromBundle = generatorFromBundle ?? MasonGenerator.fromBundle,
        _bundles = bundleByName ?? bundles;

  final Logger _logger;
  final GeneratorFromBundle _generatorFromBundle;
  final Map<String, MasonBundle> _bundles;

  /// Generates the project [options] describes inside [root].
  ///
  /// Runs every brick of [planProject] in its own directory and returns the
  /// files written. Each brick owns different files, so the result is the
  /// same whatever the order.
  Future<List<GeneratedFile>> generate(
    ProjectOptions options,
    Directory root,
  ) async {
    final files = <GeneratedFile>[];
    for (final run in planProject(options)) {
      final bundle = _bundles[run.brick];
      if (bundle == null) {
        throw StateError('No bundle for the brick "${run.brick}".');
      }
      final generator = await _generatorFromBundle(bundle);
      final target = DirectoryGeneratorTarget(
        Directory(p.normalize(p.join(root.path, run.directory))),
      );
      files.addAll(
        await generator.generate(
          target,
          vars: run.vars,
          logger: _logger,
          fileConflictResolution: FileConflictResolution.overwrite,
        ),
      );
    }
    return files;
  }
}
