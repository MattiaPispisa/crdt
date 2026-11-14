// Writes the recipe regions into the README quick starts, and the recipe
// files into the package examples that copy them.
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
// (`#imports,open,close`), joined by a blank line.
//
// A file of a manifest may also name a `copyTo` path: this script writes the
// whole file there, without the region markers. That is how the `example/`
// of a package shows a recipe on pub.dev.
//
// With `--check` it writes nothing, and fails when a README or a copy differs
// from its recipe: CI runs it that way.
//
// The docs site reads the same regions in `docs/plugins/recipes/source.ts`:
// the two parsers follow the same rules. Each run also checks that every
// `<Recipe>` and `<RecipeSnippet>` of a page in `docs/docs` names a recipe, a
// file and a region that exist: the site build fails on them too, but it runs
// only on a deploy.
import 'dart:io' as io;

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart' as yaml;

import 'logs.dart';
import 'process.dart';

const _recipesDir = 'packages/_internal/crdt_lf_recipes/recipes';
const _pagesDir = 'docs/docs';

final _block = RegExp(
  r'<!-- recipe:([\w-]+)/([^#\s]+)(?:#([\w,-]+))? -->\n.*?<!-- /recipe -->',
  dotAll: true,
);
final _snippetTag = RegExp(r'<RecipeSnippet\b([^>]*)>', dotAll: true);
final _recipeTag = RegExp(r'<Recipe\s+id="([^"]+)"');
final _attribute = RegExp(r'(\w+)="([^"]*)"');
final _marker = RegExp(r'^\s*//\s*#(docregion|enddocregion)\s+(\S+)\s*$');
final _licenseLine = RegExp('^// (Copyright|SPDX-License-Identifier)');

void main(List<String> args) {
  final check = args.contains('--check');
  final root = io.Directory.current.path;

  try {
    final loaded = _loadRecipes(root);
    final recipes = loaded.files;
    final changed = <String>[];

    _checkPages(root, recipes);

    void write(io.File file, String after) {
      final before = file.existsSync() ? file.readAsStringSync() : null;
      if (after == before) {
        return;
      }
      changed.add(path.relative(file.path, from: root));
      if (!check) {
        file.writeAsStringSync(after);
      }
    }

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
      write(readme, after);
    }

    for (final copy in loaded.copies.entries) {
      write(io.File(path.join(root, copy.key)), copy.value);
    }

    if (changed.isEmpty) {
      logger.info('Every README and copy matches its recipes ✅');
      return;
    }
    if (check) {
      // Straight to stderr: the logger writes asynchronously, and the exit
      // would drop the message.
      io.stderr.writeln(
        'These files differ from their recipes. '
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
  _Source(this.language, this.header, this.code, this.regions);

  final String language;

  /// The license lines the file starts with.
  final List<String> header;

  final String code;
  final Map<String, String> regions;
}

class _Recipes {
  _Recipes(this.files, this.copies);

  /// The files of every recipe, by recipe id and then by label and path.
  final Map<String, Map<String, _Source>> files;

  /// The content of every `copyTo` file, by its path.
  final Map<String, String> copies;
}

_Recipes _loadRecipes(String root) {
  final recipes = <String, Map<String, _Source>>{};
  final copies = <String, String>{};
  final variants = <String, String>{};
  final labelled = <String>{};
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

      final copyTo = entry['copyTo'] as String?;
      if (copyTo != null) {
        copies[copyTo] = [
          ...source.header,
          '',
          '// A copy of a recipe, written by `melos run recipes_sync`.',
          '// Edit the recipe, then run it again:',
          '// $filePath',
          '',
          source.code,
          '',
        ].join('\n');
      }
    }
    recipes[map['id'] as String] = files;
    final variantOf = map['variantOf'] as String?;
    if (variantOf != null) {
      variants[map['id'] as String] = variantOf;
    }
    if (map['variant'] != null) {
      labelled.add(map['id'] as String);
    }
  }

  // A variant is a tab on the page of another recipe: that recipe exists, is
  // not a variant itself, and both have a label for their tab.
  for (final variant in variants.entries) {
    final id = variant.key;
    final page = variant.value;
    if (!recipes.containsKey(page)) {
      throw _RecipeError('Recipe "$id": no recipe "$page" to be a variant of.');
    }
    if (variants.containsKey(page)) {
      throw _RecipeError('Recipe "$id": "$page" is a variant itself.');
    }
    for (final recipe in [id, page]) {
      if (!labelled.contains(recipe)) {
        throw _RecipeError('Recipe "$recipe": a variant needs a "variant".');
      }
    }
  }
  return _Recipes(recipes, copies);
}

/// Fails when a page of the docs site shows a recipe, a file or a region that
/// does not exist.
void _checkPages(String root, Map<String, Map<String, _Source>> recipes) {
  final problems = <String>[];
  final pages = io.Directory(path.join(root, _pagesDir))
      .listSync(recursive: true)
      .whereType<io.File>()
      .where((file) => file.path.endsWith('.mdx'));

  for (final page in pages) {
    final text = page.readAsStringSync();
    final name = path.relative(page.path, from: root);

    for (final match in _recipeTag.allMatches(text)) {
      if (!recipes.containsKey(match[1])) {
        problems.add('$name: no recipe "${match[1]}".');
      }
    }

    for (final match in _snippetTag.allMatches(text)) {
      final attributes = {
        for (final attribute in _attribute.allMatches(match[1]!))
          attribute[1]!: attribute[2]!,
      };
      final id = attributes['id'];
      final file = attributes['file'];
      final source = recipes[id]?[file];
      if (source == null) {
        problems.add('$name: no file "$file" in recipe "$id".');
        continue;
      }
      for (final region in attributes['region']?.split(',') ?? <String>[]) {
        if (!source.regions.containsKey(region.trim())) {
          problems.add(
            '$name: recipe "$id", file "$file" has no region '
            '"${region.trim()}".',
          );
        }
      }
    }
  }

  if (problems.isNotEmpty) {
    throw _RecipeError(problems.join('\n'));
  }
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
  final header = lines.sublist(0, start);

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
        regions[regionName] = _dedent(_trimBlank(_collapseBlank(body)));
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
  return _Source(
    language,
    header,
    _trimBlank(_collapseBlank(code)).join('\n'),
    regions,
  );
}

/// [lines] with every run of blank lines cut to one: a removed marker can
/// leave two blank lines next to each other.
List<String> _collapseBlank(List<String> lines) {
  final out = <String>[];
  for (final line in lines) {
    if (line.trim().isEmpty && out.isNotEmpty && out.last.trim().isEmpty) {
      continue;
    }
    out.add(line);
  }
  return out;
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
