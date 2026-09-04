import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:highlight/languages/all.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:greyhound_markdown_client/src/config.dart';

/// The class markdown puts on a fenced code block: `language-<name>`.
const String _kLanguageClassPrefix = 'language-';

/// Common fence-language shorthands mapped to the canonical grammar names
/// registered by `highlight` (which knows no aliases of its own). Anything not
/// listed is looked up verbatim.
const Map<String, String> kLanguageAliases = {
  'js': 'javascript',
  'jsx': 'javascript',
  'mjs': 'javascript',
  'cjs': 'javascript',
  'node': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'py': 'python',
  'py3': 'python',
  'rb': 'ruby',
  'sh': 'bash',
  'zsh': 'bash',
  'console': 'shell',
  'yml': 'yaml',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'rs': 'rust',
  'golang': 'go',
  'c#': 'cs',
  'csharp': 'cs',
  'c++': 'cpp',
  'cxx': 'cpp',
  'cc': 'cpp',
  'hpp': 'cpp',
  'objc': 'objectivec',
  'obj-c': 'objectivec',
  'html': 'xml',
  'htm': 'xml',
  'svg': 'xml',
  'docker': 'dockerfile',
  'ps': 'powershell',
  'ps1': 'powershell',
  'proto': 'protobuf',
  'gql': 'graphql',
  'txt': 'plaintext',
  'text': 'plaintext',
  'plain': 'plaintext',
};

/// Resolves a fenced-code language token to a grammar registered in
/// [allLanguages], applying [kLanguageAliases]; returns `null` when unknown.
String? resolveHighlightLanguage(String token) {
  final lower = token.toLowerCase();
  final canonical = kLanguageAliases[lower] ?? lower;
  return allLanguages.containsKey(canonical) ? canonical : null;
}

/// The highlight palette [CodeElementBuilder] paints with for [brightness].
Map<String, TextStyle> highlightTheme(Brightness brightness) =>
    brightness == Brightness.dark ? atomOneDarkTheme : atomOneLightTheme;

/// The background [HighlightView] fills a code block with, for [brightness].
///
/// The block sits in a container the style sheet decorates. Reading the colour
/// from the palette keeps the two from fighting: the container can round the
/// corners without a strip of another colour showing through.
Color? highlightBackground(Brightness brightness) =>
    highlightTheme(brightness)['root']?.backgroundColor;

/// Builds the `highlight` grammar table ahead of time, off the critical path.
///
/// `package:highlight`'s global instance registers all ~190 grammars the first
/// time anything touches it — about 30 ms on the Dart VM, more on web, on the
/// UI thread. Importing fewer grammars does not help: the global pins
/// [allLanguages] itself, so they are in the bundle either way. What we can
/// choose is *when* the bill lands. Left alone it lands on the frame that
/// first paints a code block; call this after the first frame instead, so it
/// falls in idle time.
///
/// Parsing a `dart` snippet also compiles that grammar's regexes, which is the
/// language the welcome text uses.
void warmUpHighlight() {
  highlight.parse('void main() {}', language: 'dart');
}

/// Renders fenced code blocks with language-aware syntax highlighting.
///
/// A fenced block (```` ```dart ````) reaches the markdown `code` element with
/// a `language-<name>` class; this builder colorizes it with
/// [HighlightView]. Inline `` `code` `` and blocks with an unknown or missing
/// language carry no usable class, so they fall through (`null`) to the
/// default renderer.
class CodeElementBuilder extends MarkdownElementBuilder {
  /// Create a code element builder for the given [brightness] (picks a light
  /// or dark highlight theme).
  CodeElementBuilder(this.brightness);

  /// The ambient theme brightness, used to pick the highlight palette.
  final Brightness brightness;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final className = element.attributes['class'] ?? '';
    if (!className.startsWith(_kLanguageClassPrefix)) {
      return null; // inline code -> default rendering
    }
    final token = className.substring(_kLanguageClassPrefix.length);
    final language = resolveHighlightLanguage(token);
    if (language == null) {
      return null; // unknown language -> default rendering
    }
    return HighlightView(
      element.textContent,
      language: language,
      theme: highlightTheme(brightness),
      padding: const EdgeInsets.all(12),
      textStyle: const TextStyle(
        fontFamily: kMonospaceFontFamily,
        fontSize: 13,
      ),
    );
  }
}
