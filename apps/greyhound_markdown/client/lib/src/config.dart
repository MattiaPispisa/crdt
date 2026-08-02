import 'dart:ui' show Color;

import 'package:markdown/markdown.dart' as md;

/// The markdown dialect of the app: GitHub flavored, so tables, fenced code
/// and strikethrough all work.
///
/// It is the set `flutter_markdown_plus` falls back to in the preview. The
/// exporters parse with the same one, so an exported file says what the
/// preview showed.
final md.ExtensionSet kMarkdownExtensionSet = md.ExtensionSet.gitHubFlavored;

/// The single fugue text handler shared by every client of a room.
/// Must be identical across peers for the Fugue merge to converge.
const String kHandlerId = 'content';

/// Welcome document shown while a room is still empty: the raw markdown as the
/// editor's grey hint, and the rendered version as the preview's empty state.
///
/// Purely visual — it is **never** written into the CRDT document (which is
/// shared across every peer of the room, so seeding it would duplicate on each
/// joiner). It doubles as a live showcase of the supported markdown features.
const String kPlaceholderMarkdown = '''
# Greyhound Markdown

**Greyhound Markdown** is a *real-time collaborative* editor built on
[`crdt_lf`](https://mattiapispisa.it/crdt/). Copy the **room link** from the
top bar and share it — everyone edits the same document live.

![crdt_lf](https://raw.githubusercontent.com/MattiaPispisa/crdt/main/assets/images/logo.png)

## Formatting
Toolbar or plain Markdown: **bold**, *italic*, ~~strikethrough~~ and
`inline code`. Headings run from `#` to `###`.

## Lists
- Bullet points
- with items
  1. and nested
  2. ordered steps

> CRDTs let everyone type at once and still converge — no locks, no conflicts.

## Code
Fenced blocks are highlighted per language:

```dart
void main() {
  final doc = CRDTDocument();
  final text = CRDTFugueTextHandler(doc, 'content');
  text.insert(0, 'Hello, collaborative world!');
  print(text.value);
}
```

## Tables
| Feature       | Supported |
| ------------- | :-------: |
| Live cursors  |    yes    |
| Offline edits |    yes    |
| Conflict-free |    yes    |

---
Start typing to make it yours — this welcome text disappears as soon as the
document has any content.
''';

/// Asset path of the app logo (home screen, about page, licenses page).
const String kLogoAsset = 'assets/images/greyhound_markdown_logo.png';

/// Monospace font family used by the editor and the rendered code blocks.
const String kMonospaceFontFamily = 'monospace';

/// Fallback display name for a peer that did not pick one.
const String kDefaultUserName = 'anonymous';

/// The colors a peer can pick as its identity — used for the avatar dot on the
/// home screen and for the remote cursors in the editor. Kept saturated and
/// far apart so two peers are told apart at a glance.
const List<Color> kAvatarPalette = [
  Color(0xFFE53935),
  Color(0xFF8E24AA),
  Color(0xFF3949AB),
  Color(0xFF039BE5),
  Color(0xFF00897B),
  Color(0xFF7CB342),
  Color(0xFFFB8C00),
  Color(0xFF6D4C41),
];

/// Named route of the about/settings page.
const String kSettingsRoute = '/settings';

/// Named route of the changelog page.
const String kChangelogRoute = '/changelog';

/// Asset path of the app changelog, rendered on the changelog page.
const String kChangelogAsset = 'CHANGELOG.md';

/// Author, reused across the credit line and the legalese so the name lives
/// in exactly one place.
const String kAuthor = 'Mattia Pispisa';

/// The author's personal site, linked from the credit line.
const String kAuthorUrl = 'https://mattiapispisa.it';

/// Display name of the application (title bars, about/licenses pages).
const String kAppName = 'Greyhound Markdown';

/// One-line description shown on the about/settings page.
const String kAppTagline =
    'A real-time collaborative markdown editor built on crdt_lf.';

/// Footer/about credit line, up to the author's name — [kAuthor] follows it as
/// a link to [kAuthorUrl], so the line is a widget rather than a single string.
const String kCreditPrefix = 'Powered by crdt_lf · created by ';

/// Legal line shown on the about/settings and licenses pages.
const String kAppLegalese = '© $kAuthor';

/// A labelled external link.
typedef ProjectLink = ({String label, String url});

/// Project and documentation links, shared by the footer and the about page.
const List<ProjectLink> kProjectLinks = [
  (label: 'GitHub', url: kRepoUrl),
  (label: 'App source', url: kAppSourceUrl),
  (label: 'crdt_lf docs', url: kDocsUrl),
];

/// Project and documentation link targets.
const String kRepoUrl = 'https://github.com/MattiaPispisa/crdt';
const String kAppSourceUrl =
    'https://github.com/MattiaPispisa/crdt/tree/main/apps/greyhound_markdown';
const String kDocsUrl = 'https://mattiapispisa.it/crdt/';

/// WebSocket endpoint of the signaling server.
/// WebSocket endpoint of the relay server.
///
/// Override at build time with
/// `--dart-define=GREYHOUND_WS=wss://your-worker.example.com`.
const String kServerUrl = String.fromEnvironment(
  'GREYHOUND_WS',
  defaultValue: 'ws://localhost:8787',
);

/// The WebSocket URL of a room on the relay server.
///
/// Appends the `/room/<id>` path and normalizes http(s) schemes to ws(s).
String roomUrl(String serverUrl, String roomId) {
  final uri = Uri.parse('$serverUrl/room/$roomId');
  return uri
      .replace(
        scheme: switch (uri.scheme) {
          'https' => 'wss',
          'http' => 'ws',
          _ => uri.scheme,
        },
      )
      .toString();
}
