// Checks the agent skills the packages ship in `skills/<name>/SKILL.md`.
//
// `skills_lint` checks each skill against the Agent Skills specification and
// the naming rule of `package:skills`, and checks that `dart pub publish` puts
// the skill in the archive.
//
// A skill names the API and links the docs site instead of explaining them, so
// two rules of this repository check what can go stale without a compiler to
// notice:
//
// - a link to `https://mattiapispisa.it/crdt/docs/...` must name a page of
//   `docs/docs`, and its `#anchor` a heading of that page;
// - a name in backticks that looks like Dart API (`CRDTReplica.open`,
//   `onStorageError`) must be declared in the `lib/` of a package of this
//   repository.
//
// The code blocks are left out: they come from the recipes, and
// `recipes_check` checks them.
import 'dart:io' as io;

import 'package:path/path.dart' as path;
import 'package:skills_lint/skills_lint.dart';

import 'logs.dart';
import 'process.dart';

const _pagesDir = 'docs/docs';

/// Names of Flutter, Dart and third-party packages that a skill may quote.
/// Each one is checked by hand: keep the list short.
const _external = {
  'StreamBuilder',
  'setState',
};

final _link = RegExp(
  r'https://mattiapispisa\.it/crdt/docs/([^)\s#>"]*)(?:#([^)\s>"]+))?',
);
final _fence = RegExp('^```.*?^```', multiLine: true, dotAll: true);
final _codeSpan = RegExp('`([^`\n]+)`');
final _apiName = RegExp(
  r'^(?:[A-Z][A-Za-z0-9]*[a-z][A-Za-z0-9]*(?:\.[a-z][A-Za-z0-9]*)?'
  r'|[a-z]+[A-Z][A-Za-z0-9]*)(?:\(\))?$',
);
final _frontMatter = RegExp(r'^---\n(.*?)\n---\n', dotAll: true);
final _slug = RegExp(r'^slug:\s*(\S+)\s*$', multiLine: true);
final _heading = RegExp(r'^#{1,6}\s+(.+?)\s*$', multiLine: true);
final _headingId = RegExp(r'\{#([\w-]+)\}\s*$');
final _identifier = RegExp(r'\b[A-Za-z_]\w*\b');

Future<void> main() async {
  final root = io.Directory.current.path;
  final directories = _skillDirectories(root);
  if (directories.isEmpty) {
    logger.info('No package ships skills.');
    return;
  }

  final valid = await validateSkills(
    skillDirPaths: directories,
    resolvedRuleConfigs: {
      'published-skill-name': const RuleConfigPatch(
        severity: AnalysisSeverity.error,
      ),
      'pub-archive-includes-skill': const RuleConfigPatch(
        severity: AnalysisSeverity.error,
      ),
      'check-relative-paths': RuleConfigPatch(
        severity: AnalysisSeverity.error,
        parameters: CustomRuleParameters(const {'within-skill': true}),
      ),
      'check-trailing-whitespace': const RuleConfigPatch(
        severity: AnalysisSeverity.error,
      ),
    },
    customRules: [_DocsLinkRule(root), _ApiNameRule(root)],
  );
  if (!valid) {
    io.stderr.writeln('The skills have errors.');
    badExit();
  }
  logger.info('Every skill passes ✅');
}

/// A link to the docs site names a page of `docs/docs`, and its anchor a
/// heading of that page.
///
/// ```markdown
/// <!-- Passes: the page and its heading "Which adapter" exist. -->
/// [Adapters](https://mattiapispisa.it/crdt/docs/connectors/persistence#which-adapter)
///
/// <!-- Fails: No page "connectors/replicas" in docs/docs. -->
/// [Replica](https://mattiapispisa.it/crdt/docs/connectors/replicas)
///
/// <!-- Fails: The page "document" has no heading "#undo". -->
/// [Undo](https://mattiapispisa.it/crdt/docs/document#undo)
/// ```
class _DocsLinkRule extends SkillRule {
  _DocsLinkRule(String root) : _pages = _readPages(root);

  final Map<String, Set<String>> _pages;

  @override
  String get name => 'docs-link';

  @override
  AnalysisSeverity get severity => AnalysisSeverity.error;

  @override
  Future<List<ValidationError>> validate(SkillContext context) async {
    final errors = <ValidationError>[];
    final text = context.rawContent;
    for (final match in _link.allMatches(text)) {
      final route = _trimSlashes(match[1]!);
      final anchors = _pages[route];
      final anchor = match[2];
      final String message;
      if (anchors == null) {
        message = 'No page "$route" in $_pagesDir.';
      } else if (anchor != null && !anchors.contains(anchor)) {
        message = 'The page "$route" has no heading "#$anchor".';
      } else {
        continue;
      }
      errors.add(_error(this, context, match, message));
    }
    return errors;
  }
}

/// A name in backticks that looks like Dart API is declared in the `lib/` of
/// a package of this repository.
///
/// ```markdown
/// <!-- Passes: both names are declared in crdt_socket_sync. -->
/// Open the document with `CRDTReplica.open`.
///
/// <!-- Passes: not API-like (no capital letter), so not checked. -->
/// Add `crdt_lf_hive` to the app.
///
/// <!-- Fails: `CRDTReplica.openLater` is declared in no package of the
///      repository (openLater). -->
/// Open it with `CRDTReplica.openLater`.
///
/// <!-- Passes: `connect` is declared, on another class. -->
/// Then call `CRDTReplica.connect`.
/// ```
///
/// Each part of a dotted name is checked on its own: the rule finds a name
/// that does not exist, not a member on the wrong class.
class _ApiNameRule extends SkillRule {
  _ApiNameRule(String root) : _names = _declaredNames(root);

  final Set<String> _names;

  @override
  String get name => 'api-name';

  @override
  AnalysisSeverity get severity => AnalysisSeverity.error;

  @override
  Future<List<ValidationError>> validate(SkillContext context) async {
    final errors = <ValidationError>[];
    final text = context.rawContent;
    final fences = _fence.allMatches(text).toList();
    for (final match in _codeSpan.allMatches(text)) {
      if (fences.any((f) => f.start <= match.start && match.end <= f.end)) {
        continue;
      }
      final quoted = match[1]!;
      if (!_apiName.hasMatch(quoted) || _external.contains(quoted)) {
        continue;
      }
      final missing = quoted
          .replaceAll('()', '')
          .split('.')
          .where((part) => !_names.contains(part));
      if (missing.isNotEmpty) {
        errors.add(
          _error(
            this,
            context,
            match,
            '`$quoted` is declared in no package of the repository '
            '(${missing.join(', ')}).',
          ),
        );
      }
    }
    return errors;
  }
}

ValidationError _error(
  SkillRule rule,
  SkillContext context,
  Match match,
  String message,
) {
  return ValidationError(
    ruleId: rule.name,
    severity: rule.severity,
    file: SkillContext.skillFileName,
    subject: match[0],
    message: message,
    region: SourceRegion(startLine: context.offsetToLine(match.start)),
  );
}

/// The `skills/` folder of every package that has one.
List<String> _skillDirectories(String root) {
  return io.Directory(path.join(root, 'packages'))
      .listSync(recursive: true, followLinks: false)
      .whereType<io.Directory>()
      .where((dir) => path.basename(dir.path) == 'skills')
      .where((dir) {
        final package = dir.parent.path;
        final parts = path.split(path.relative(package, from: root));
        return io.File(path.join(package, 'pubspec.yaml')).existsSync() &&
            !parts.any((part) => part.startsWith('.') || part == 'build');
      })
      .map((dir) => dir.path)
      .toList()
    ..sort();
}

/// The route of every page of the docs site, relative to `/docs/`, with the
/// anchors of its headings.
Map<String, Set<String>> _readPages(String root) {
  final dir = path.join(root, _pagesDir);
  final pages = <String, Set<String>>{};
  final files = io.Directory(dir)
      .listSync(recursive: true)
      .whereType<io.File>()
      .where((file) => file.path.endsWith('.md') || file.path.endsWith('.mdx'))
      // A file that starts with `_` is a partial, not a page.
      .where((file) => !path.basename(file.path).startsWith('_'));

  for (final file in files) {
    final text = file.readAsStringSync();
    final slug = _slug.firstMatch(_frontMatter.firstMatch(text)?[1] ?? '');
    final String route;
    if (slug != null) {
      route = _trimSlashes(slug[1]!);
    } else {
      final relative =
          path.withoutExtension(path.relative(file.path, from: dir));
      final segments = path.split(relative);
      if (segments.last == 'index') {
        segments.removeLast();
      }
      route = segments.join('/');
    }
    pages[route] = {
      for (final heading in _heading.allMatches(text.replaceAll(_fence, '')))
        _anchor(heading[1]!),
    };
  }
  return pages;
}

/// The anchor Docusaurus gives a heading: an explicit `{#id}`, or the text in
/// lower case, with the punctuation dropped and the spaces turned into `-`.
String _anchor(String heading) {
  final id = _headingId.firstMatch(heading);
  if (id != null) {
    return id[1]!;
  }
  return heading
      .replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1')
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s_-]', unicode: true), '')
      .trim()
      .replaceAll(RegExp(r'\s'), '-');
}

/// Every identifier in the `lib/` of the packages that are published or
/// shown in the docs.
Set<String> _declaredNames(String root) {
  final names = <String>{};
  final libs = io.Directory(path.join(root, 'packages'))
      .listSync(recursive: true, followLinks: false)
      .whereType<io.File>()
      .where((file) => file.path.endsWith('.dart'))
      .where((file) {
    final parts = path.split(path.relative(file.path, from: root));
    return parts.contains('lib') &&
        !parts.contains('_internal') &&
        !parts.any((part) => part.startsWith('.') || part == 'build');
  });
  for (final file in libs) {
    names.addAll(
      _identifier.allMatches(file.readAsStringSync()).map((m) => m[0]!),
    );
  }
  return names;
}

String _trimSlashes(String route) => route.replaceAll(RegExp(r'^/+|/+$'), '');
