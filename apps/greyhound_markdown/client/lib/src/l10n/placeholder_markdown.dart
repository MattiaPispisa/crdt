import 'package:flutter/widgets.dart';

/// The welcome document for [locale], falling back to English for a language
/// it is not written in.
///
/// Written in English and Italian only, while the interface is translated
/// into more: this is long prose, and most of what it shows — the code fence,
/// the URLs, the markdown syntax itself — reads the same in every language.
/// A reader on a third language gets the English version, which is why the
/// fallback is the `_` branch rather than an error.
///
/// Kept in Dart rather than in the ARB files: the document embeds a Dart code
/// fence, and gen-l10n reads every `{` in a message as the start of an ICU
/// placeholder. Escaping each brace would make the markdown unreadable in the
/// one place where it is meant to be read as markdown.
String placeholderMarkdown(Locale locale) {
  return switch (locale.languageCode) {
    'it' => _kPlaceholderIt,
    _ => _kPlaceholderEn,
  };
}

/// Welcome document shown while a room is still empty: the raw markdown as the
/// editor's grey hint, and the rendered version as the preview's empty state.
///
/// Purely visual — it is **never** written into the CRDT document (which is
/// shared across every peer of the room, so seeding it would duplicate on each
/// joiner). It doubles as a live showcase of the supported markdown features.
const String _kPlaceholderEn = '''
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

/// The Italian [_kPlaceholderEn]. The code sample, the links and the `crdt_lf`
/// API names stay as they are: they are the same in every language.
const String _kPlaceholderIt = '''
# Greyhound Markdown

**Greyhound Markdown** è un editor *collaborativo in tempo reale* costruito su
[`crdt_lf`](https://mattiapispisa.it/crdt/). Copia il **link della stanza**
dalla barra in alto e condividilo — tutti scrivono sullo stesso documento, dal
vivo.

![crdt_lf](https://raw.githubusercontent.com/MattiaPispisa/crdt/main/assets/images/logo.png)

## Formattazione
Con la barra degli strumenti o in Markdown: **grassetto**, *corsivo*,
~~barrato~~ e `codice inline`. I titoli vanno da `#` a `###`.

## Elenchi
- Punti elenco
- con voci
  1. e passi numerati
  2. annidati

> I CRDT lasciano scrivere tutti insieme e il testo converge lo stesso — senza
> blocchi e senza conflitti.

## Codice
I blocchi di codice sono colorati in base al linguaggio:

```dart
void main() {
  final doc = CRDTDocument();
  final text = CRDTFugueTextHandler(doc, 'content');
  text.insert(0, 'Hello, collaborative world!');
  print(text.value);
}
```

## Tabelle
| Funzione            | Supportata |
| ------------------- | :--------: |
| Cursori dal vivo    |     sì     |
| Modifiche offline   |     sì     |
| Senza conflitti     |     sì     |

---
Inizia a scrivere per farlo tuo — questo testo di benvenuto sparisce appena il
documento ha del contenuto.
''';
