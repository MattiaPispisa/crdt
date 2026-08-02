import 'package:markdown/markdown.dart' as md;

import 'package:greyhound_markdown_client/src/config.dart';

/// Renders [markdown] as a standalone HTML page titled [title].
///
/// Everything the page needs is inside it — the style sheet is inline and no
/// script runs — so the file opens from disk with no network at all. Images
/// keep their original URLs, so remote ones still need a connection.
String markdownToHtmlDocument(String markdown, {required String title}) {
  final body = md.markdownToHtml(
    markdown,
    extensionSet: kMarkdownExtensionSet,
  );
  return '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="generator" content="$kAppName">
<title>${_escape(title)}</title>
<style>
$_kStyle</style>
</head>
<body>
<main>
$body</main>
</body>
</html>
''';
}

/// Escapes the characters that would break out of HTML text.
String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// The page style: a readable column, and the same constructs the preview
/// renders (headings, quotes, code, tables, images). Follows the reader's
/// light/dark preference.
const String _kStyle = '''
:root { color-scheme: light dark; --fg: #1a1c1e; --bg: #ffffff;
  --muted: #5f6368; --line: #d7dbdf; --code-bg: #f4f6f8; }
@media (prefers-color-scheme: dark) {
  :root { --fg: #e3e2e6; --bg: #131416; --muted: #9aa0a6;
    --line: #33363a; --code-bg: #1c1f22; }
}
body { margin: 0; background: var(--bg); color: var(--fg);
  font: 16px/1.6 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
main { max-width: 46rem; margin: 0 auto; padding: 3rem 1.25rem 5rem; }
h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 2rem 0 .75rem; }
h1 { font-size: 2rem; }
h2 { font-size: 1.5rem; border-bottom: 1px solid var(--line);
  padding-bottom: .3rem; }
h3 { font-size: 1.25rem; }
p, ul, ol, table, pre, blockquote { margin: 0 0 1rem; }
a { color: #00695c; }
@media (prefers-color-scheme: dark) { a { color: #4db6ac; } }
img { max-width: 100%; height: auto; }
hr { border: 0; border-top: 1px solid var(--line); margin: 2rem 0; }
blockquote { margin-left: 0; padding: .25rem 0 .25rem 1rem;
  border-left: 4px solid var(--line); color: var(--muted); }
code, pre { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas,
  monospace; font-size: .9em; }
code { background: var(--code-bg); padding: .15em .35em; border-radius: 4px; }
pre { background: var(--code-bg); padding: 1rem; border-radius: 8px;
  overflow-x: auto; }
pre code { background: none; padding: 0; }
table { border-collapse: collapse; width: 100%; display: block;
  overflow-x: auto; }
th, td { border: 1px solid var(--line); padding: .5rem .75rem; }
th { background: var(--code-bg); }
''';
