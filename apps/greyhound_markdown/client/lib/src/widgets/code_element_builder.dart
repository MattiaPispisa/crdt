import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
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
      theme: brightness == Brightness.dark
          ? atomOneDarkTheme
          : atomOneLightTheme,
      padding: const EdgeInsets.all(12),
      textStyle: const TextStyle(
        fontFamily: kMonospaceFontFamily,
        fontSize: 13,
      ),
    );
  }
}
