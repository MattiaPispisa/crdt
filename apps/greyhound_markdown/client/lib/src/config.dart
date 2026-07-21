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

/// Named route of the about/settings page.
const String kSettingsRoute = '/settings';

/// Author, reused across the credit line and the legalese so the name lives
/// in exactly one place.
const String kAuthor = 'Mattia Pispisa';

/// Display name of the application (title bars, about/licenses pages).
const String kAppName = 'Greyhound Markdown';

/// One-line description shown on the about/settings page.
const String kAppTagline =
    'A real-time collaborative markdown editor built on crdt_lf.';

/// Footer/about credit line.
const String kCreditLine = 'Powered by crdt_lf · created by $kAuthor';

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
///
/// Override at build time with
/// `--dart-define=GREYHOUND_WS=wss://your-worker.example.com`.
const String kServerUrl = String.fromEnvironment(
  'GREYHOUND_WS',
  defaultValue: 'ws://localhost:8787',
);
