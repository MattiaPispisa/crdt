// Writes the recipe regions into the README quick starts.
//
// A README marks a block with
//
//   <!-- recipe:<recipe id>/<file label>#<region> -->
//   ```dart
//   ...
//   ```
//   <!-- /recipe -->
//
// and this script rewrites what is between the two markers with the region of
// `packages/_internal/crdt_lf_recipes`, where a test runs it. `#<region>` may
// be left out to take the whole file, or list several regions
// (`#imports,open,close`), joined by a blank line. With `--check` it writes
// nothing, and fails when a README differs from its recipe: CI runs it that
// way.
//
// The docs site reads the same regions in `docs/plugins/recipes/source.ts`:
// the two parsers follow the same rules.
import 'dart:io' as io;

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart' as yaml;

import 'logs.dart';
import 'process.dart';

const _recipesDir = 'packages/_internal/crdt_lf_recipes/recipes';

final _block = RegExp(
  r'<!-- recipe:([\w-]+)/([^#\s]+)(?:#([\w,-]+))? -->\n.*?<!-- /recipe -->',
  dotAll: true,
);
final _marker = RegExp(r'^\s*//\s*#(docregion|enddocregion)\s+(\S+)\s*$');
final _licenseLine = RegExp('^// (Copyright|SPDX-License-Identifier)');

void main(List<String> args) {
  final check = args.contains('--check');
  final root = io.Directory.current.path;

  try {
    final recipes = _loadRecipes(root);
    final changed = <String>[];

    for (final readme in _readmes(root)) {
      final before = readme.readAsStringSync();
      final after = before.replaceAllMapped(_block, (match) {
        final id = match[1]!;
        final file = match[2]!;
        final region = match[3];
        final source = recipes[id]?[file];
        if (source == null) {
          throw _RecipeError(
            '${path.relative(readme.path)}: no file "$file" in recipe "$id".',
          );
        }
        final code = region == null
            ? source.code
            : region.split(',').map((name) {
                final code = source.regions[name];
                if (code == null) {
                  throw _RecipeError(
                    '${path.relative(readme.path)}: recipe "$id", file '
                    '"$file" has no region "$name".',
                  );
                }
                return code;
              }).join('\n\n');
        final marker = region == null ? '$id/$file' : '$id/$file#$region';
        return '<!-- recipe:$marker -->\n'
            '```${source.language}\n$code\n```\n'
            '<!-- /recipe -->';
      });
      if (after != before) {
        changed.add(path.relative(readme.path, from: root));
        if (!check) {
          readme.writeAsStringSync(after);
        }
      }
    }

    if (changed.isEmpty) {
      logger.info('Every README matches its recipes ✅');
      return;
    }
    if (check) {
      // Straight to stderr: the logger writes asynchronously, and the exit
      // would drop the message.
      io.stderr.writeln(
        'These READMEs differ from their recipes. '
        'Run `melos run recipes_sync`:\n${changed.join('\n')}',
      );
      badExit();
    }
    logger.info('Updated:\n${changed.join('\n')}');
  } on _RecipeError catch (error) {
    io.stderr.writeln(error.message);
    badExit();
  }
}

/// A recipe file, or a README marker, that does not hold together.
class _RecipeError implements Exception {
  _RecipeError(this.message);

  final String message;
}

class _Source {
  _Source(this.language, this.code, this.regions);

  final String language;
  final String code;
  final Map<String, String> regions;
}

/// The files of every recipe, by recipe id and then by file label and path.
Map<String, Map<String, _Source>> _loadRecipes(String root) {
  final recipes = <String, Map<String, _Source>>{};
  final manifests = io.Directory(path.join(root, _recipesDir))
      .listSync()
      .whereType<io.File>()
      .where((file) => file.path.endsWith('.yaml'));

  for (final manifest in manifests) {
    final map = yaml.loadYaml(manifest.readAsStringSync()) as yaml.YamlMap;
    final files = <String, _Source>{};
    for (final entry in (map['files'] as yaml.YamlList).cast<yaml.YamlMap>()) {
      final filePath = entry['path'] as String;
      final source = _readSource(
        io.File(path.join(root, filePath)).readAsStringSync(),
        language: path.extension(filePath).replaceFirst('.', ''),
        name: filePath,
      );
      final label = entry['label'] as String? ?? path.basename(filePath);
      files[label] = source;
      files[filePath] = source;
    }
    recipes[map['id'] as String] = files;
  }
  return recipes;
}

/// Every README of the repository, outside build and tool folders.
Iterable<io.File> _readmes(String root) {
  const skipped = {'build', 'node_modules', '.dart_tool', '.git', '.fvm'};
  return io.Directory(root)
      .listSync(recursive: true, followLinks: false)
      .whereType<io.File>()
      .where((file) => path.basename(file.path) == 'README.md')
      .where(
        (file) => !path
            .split(path.relative(file.path, from: root))
            .any((part) => skipped.contains(part) || part == '.claude'),
      );
}

_Source _readSource(
  String text, {
  required String language,
  required String name,
}) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  var start = 0;
  while (start < lines.length && _licenseLine.hasMatch(lines[start])) {
    start++;
  }

  final code = <String>[];
  final open = <String, List<String>>{};
  final regions = <String, String>{};

  for (final line in lines.skip(start)) {
    final match = _marker.firstMatch(line);
    if (match != null) {
      final regionName = match[2]!;
      if (match[1] == 'docregion') {
        if (open.containsKey(regionName) || regions.containsKey(regionName)) {
          throw _RecipeError('$name: region "$regionName" opens twice.');
        }
        open[regionName] = [];
      } else {
        final body = open.remove(regionName);
        if (body == null) {
          throw _RecipeError('$name: region "$regionName" never opened.');
        }
        regions[regionName] = _dedent(_trimBlank(body));
      }
      continue;
    }
    code.add(line);
    for (final body in open.values) {
      body.add(line);
    }
  }
  if (open.isNotEmpty) {
    throw _RecipeError('$name: region "${open.keys.first}" never closes.');
  }
  return _Source(language, _trimBlank(code).join('\n'), regions);
}

List<String> _trimBlank(List<String> lines) {
  var start = 0;
  var end = lines.length;
  while (start < end && lines[start].trim().isEmpty) {
    start++;
  }
  while (end > start && lines[end - 1].trim().isEmpty) {
    end--;
  }
  return lines.sublist(start, end);
}

String _dedent(List<String> lines) {
  final indents = lines
      .where((line) => line.trim().isNotEmpty)
      .map((line) => line.length - line.trimLeft().length);
  final cut = indents.isEmpty ? 0 : indents.reduce((a, b) => a < b ? a : b);
  return lines
      .map((line) => line.length < cut ? '' : line.substring(cut))
      .join('\n');
}
