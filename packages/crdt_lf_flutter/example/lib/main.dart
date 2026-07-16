import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';

void main() => runApp(const CrdtApp());

// Handler ids — sub-widgets look handlers up by id from the ambient document.
const _counterId = 'counter';
const _todosId = 'todos';
const _settingsId = 'settings';
const _nicknameKey = 'nickname';
const _noteId = 'note';

/// Builds the single document shared by the whole app.
///
/// Handlers auto-register on construction, so we don't keep references: every
/// widget/callback resolves them by id from the ambient [CrdtProvider].
CRDTDocument _buildDocument() {
  final doc = CRDTDocument()..registerDefaultFactories();
  CRDTRegisterHandler<int>(doc, _counterId).set(0);
  CRDTListHandler<String>(doc, _todosId);
  // A container handler ("settings") holding a nested text handler.
  CRDTMapRefHandler(
    doc,
    _settingsId,
  ).setRef(_nicknameKey, CRDTFugueTextHandler(doc, doc.newHandlerId()));
  // A fixed id so the "Remote edit" throwaway peer can address the same
  // handler.
  CRDTFugueTextHandler(doc, _noteId).insert(0, 'hello');
  return doc;
}

/// Entry widget: a [MaterialApp] whose subtree is fed a single [CRDTDocument]
/// through [CrdtProvider] (which owns and disposes it).
class CrdtApp extends StatelessWidget {
  /// Creates the example app.
  const CrdtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'crdt_lf_flutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: CrdtProvider(
        create: (_) => _buildDocument(),
        child: const HomePage(),
      ),
    );
  }
}

/// The demo screen. Every card is independent: watch the "rebuilt ×N" badges to
/// see that editing one handler only re-renders the widgets that observe it.
class HomePage extends StatelessWidget {
  /// Creates the home page.
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('crdt_lf_flutter'),
        // Rebuilds on ANY document change (document-level baseline).
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(child: _DocumentSummary()),
          ),
        ],
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Legend(),
            SizedBox(height: 8),
            _DocumentSelectorCard(),
            _CounterCard(),
            _ListenerCard(),
            _TodosCard(),
            _SettingsCard(),
            _NoteCard(),
          ],
        ),
      ),
    );
  }
}

/// Short explanation shown at the top of the demo.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Each ⟳ badge counts how many times that region rebuilt. Edit one '
          'handler and notice only the widgets that observe it light up — that '
          'is the point of CrdtSelector / CrdtHandlerBuilder. The Listener '
          'card fires side effects without rebuilding, and the Note card '
          'binds a TextField to a text handler — including changes imported '
          'from a remote peer and a collaborator cursor drawn over the field.',
        ),
      ),
    );
  }
}

/// Document-level baseline: rebuilds on every change.
class _DocumentSummary extends StatelessWidget {
  const _DocumentSummary();

  @override
  Widget build(BuildContext context) {
    return CrdtBuilder(
      builder:
          (context, document) => _RebuildBadge(
            label: 'document',
            stretch: false,
            child: Text('${document.exportChanges().length} changes'),
          ),
    );
  }
}

/// A document-level derived scalar shown with [CrdtSelector]: rebuilds only
/// when the selected value changes, deduping every unrelated edit.
class _DocumentSelectorCard extends StatelessWidget {
  const _DocumentSelectorCard();

  @override
  Widget build(BuildContext context) {
    return _DemoCard(
      title: 'Document slice — CrdtSelector',
      description:
          'Selects document.registeredHandlers.length: every edit is '
          'deduplicated until "Add key" (Settings card) registers a new '
          'handler.',
      actions: const [],
      child: CrdtSelector<int>(
        selector: (context, document) => document.registeredHandlers.length,
        builder:
            (context, count) => _RebuildBadge(
              label: 'doc-handlers',
              child: Text(
                'registered handlers: $count',
                style: _valueStyle(context),
              ),
            ),
      ),
    );
  }
}

/// A `CRDTRegisterHandler<int>` shown reactively with a selector.
class _CounterCard extends StatelessWidget {
  const _CounterCard();

  @override
  Widget build(BuildContext context) {
    return _DemoCard(
      title: 'Counter — CrdtHandlerSelector',
      description: 'Rebuilds only when the counter value changes.',
      actions: [
        FilledButton.tonalIcon(
          onPressed: () {
            final counter = context.crdtHandler<CRDTRegisterHandler<int>>(
              _counterId,
            );
            counter.set((counter.value ?? 0) + 1);
          },
          icon: const Icon(Icons.add),
          label: const Text('Increment'),
        ),
      ],
      child: CrdtHandlerSelector<CRDTRegisterHandler<int>, int>(
        id: _counterId,
        selector: (context, handler) => handler.value ?? 0,
        builder:
            (context, value) => _RebuildBadge(
              label: 'counter',
              child: Text('value: $value', style: _valueStyle(context)),
            ),
      ),
    );
  }
}

/// A [CrdtHandlerListener]: fires a side effect (a SnackBar) when the counter
/// changes, while its child is never rebuilt.
class _ListenerCard extends StatelessWidget {
  const _ListenerCard();

  @override
  Widget build(BuildContext context) {
    return _DemoCard(
      title: 'Side effects — CrdtHandlerListener',
      description:
          'Shows a SnackBar whenever the counter changes (press "Increment" '
          'above); the child below never rebuilds.',
      actions: const [],
      child: CrdtHandlerListener<CRDTRegisterHandler<int>>(
        id: _counterId,
        listener:
            (context, handler) =>
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text('counter changed → ${handler.value}'),
                    ),
                  ),
        child: const _RebuildBadge(
          label: 'listener-child',
          child: Text('static child — the listener fires, I never rebuild'),
        ),
      ),
    );
  }
}

/// A `CRDTListHandler<String>` shown two ways: a length selector (rebuilds only
/// when the count changes) and a list builder (rebuilds on any list change).
class _TodosCard extends StatelessWidget {
  const _TodosCard();

  CRDTListHandler<String> _todos(BuildContext context) =>
      context.crdtHandler<CRDTListHandler<String>>(_todosId);

  @override
  Widget build(BuildContext context) {
    return _DemoCard(
      title: 'Todos — Selector (count) + HandlerBuilder (list)',
      description:
          'Add/remove changes the length (both rebuild). "Edit first" '
          'mutates an item in place: the list rebuilds, the count does not.',
      actions: [
        FilledButton.tonalIcon(
          onPressed: () {
            final todos = _todos(context);
            todos.insert(todos.length, 'Todo #${todos.length + 1}');
          },
          icon: const Icon(Icons.add),
          label: const Text('Add'),
        ),
        FilledButton.tonalIcon(
          onPressed: () {
            final todos = _todos(context);
            if (todos.length > 0) todos.delete(todos.length - 1, 1);
          },
          icon: const Icon(Icons.remove),
          label: const Text('Remove last'),
        ),
        FilledButton.tonalIcon(
          onPressed: () {
            final todos = _todos(context);
            if (todos.length > 0) {
              todos.update(0, '${todos.value.first} ✎');
            }
          },
          icon: const Icon(Icons.edit),
          label: const Text('Edit first'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CrdtHandlerSelector<CRDTListHandler<String>, int>(
            id: _todosId,
            selector: (context, handler) => handler.value.length,
            builder:
                (context, count) => _RebuildBadge(
                  label: 'todos-count',
                  child: Text('count: $count', style: _valueStyle(context)),
                ),
          ),
          const SizedBox(height: 8),
          CrdtHandlerBuilder<CRDTListHandler<String>>(
            id: _todosId,
            builder: (context, handler) {
              final todos = handler.value;
              return _RebuildBadge(
                label: 'todos-list',
                child:
                    todos.isEmpty
                        ? const Text('No todos yet')
                        : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < todos.length; i++)
                              ListTile(
                                dense: true,
                                // Neutral icon — todos aren't checkable.
                                leading: CircleAvatar(
                                  radius: 12,
                                  child: Text('${i + 1}'),
                                ),
                                title: Text(todos[i]),
                              ),
                          ],
                        ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A `CRDTMapRefHandler` (container) with a nested text child, rendered by two
/// `CrdtHandlerBuilder`s that differ only in `nested`.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard();

  CRDTMapRefHandler _settings(BuildContext context) =>
      context.crdtHandler<CRDTMapRefHandler>(_settingsId);

  @override
  Widget build(BuildContext context) {
    return _DemoCard(
      title: 'Settings (ref handler) — nested: false vs true',
      description:
          'Edit nickname changes a CHILD handler: only nested:true '
          'rebuilds. Add/remove key changes the container itself: both '
          'rebuild. Only keys added with "Add key" are removable (nickname '
          'stays): "Remove key" disables itself when none is left.',
      actions: [
        FilledButton.tonalIcon(
          onPressed: () {
            final settings = _settings(context);
            final nickname = settings.getRefAs<CRDTFugueTextHandler>(
              _nicknameKey,
            );
            if (nickname != null) {
              context.crdtDocument.runInTransaction(
                () => nickname.change('user-${Random().nextInt(20)}'),
              );
            }
          },
          icon: const Icon(Icons.edit),
          label: const Text('Edit nickname'),
        ),
        FilledButton.tonalIcon(
          onPressed: () {
            final doc = context.crdtDocument;
            final settings = _settings(context);
            // The map key can be reused after a delete, but handler ids are
            // never unregistered from the document — keep them unique.
            settings.setRef(
              'flag-${settings.value.length}',
              CRDTFugueTextHandler(doc, doc.newHandlerId())..insert(0, 'on'),
            );
          },
          icon: const Icon(Icons.add),
          label: const Text('Add key'),
        ),
        // Only the keys added with "Add key" are removable (nickname is the
        // nested demo): the button disables itself — reactively — when none
        // is left, instead of silently doing nothing.
        CrdtHandlerSelector<CRDTMapRefHandler, bool>(
          id: _settingsId,
          selector:
              (context, handler) =>
                  handler.value.keys.any((k) => k != _nicknameKey),
          builder: (context, hasExtra) {
            return FilledButton.tonalIcon(
              onPressed:
                  !hasExtra
                      ? null
                      : () {
                        final settings = _settings(context);
                        final extra =
                            settings.value.keys
                                .where((k) => k != _nicknameKey)
                                .toList();
                        if (extra.isNotEmpty) {
                          settings.delete(extra.last);
                        }
                      },
              icon: const Icon(Icons.remove),
              label: const Text('Remove key'),
            );
          },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CrdtHandlerBuilder<CRDTMapRefHandler>(
            id: _settingsId,
            builder: (context, handler) {
              return _RebuildBadge(
                label: 'settings-flat',
                child: Text(
                  'nested: false → ${handler.value.length} keys',
                  style: _valueStyle(context),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          CrdtHandlerBuilder<CRDTMapRefHandler>(
            id: _settingsId,
            nested: true,
            builder: (context, handler) {
              return _RebuildBadge(
                label: 'settings-nested',
                child: Text(
                  'nested: true → ${handler.resolved}',
                  style: _valueStyle(context),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A `CRDTFugueTextHandler` bound to a TextField through [CrdtTextFieldBuilder]
/// (local keystrokes diff into the handler, remote values are adopted with the
/// caret preserved), plus a naive remote peer simulated on demand and a fake
/// collaborator cursor drawn by [CrdtRemoteCursorsOverlay].
class _NoteCard extends StatefulWidget {
  const _NoteCard();

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  /// The fake collaborator's cursors. In a real app they come from a presence
  /// channel (e.g. crdt_socket_sync's awareness plugin); a ValueNotifier so
  /// updating them rebuilds only the overlay, not the CrdtTextFieldBuilder.
  final _cursors = ValueNotifier<List<CrdtRemoteCursor>>(const []);

  @override
  void dispose() {
    _cursors.dispose();
    super.dispose();
  }

  void _toggleCursor() {
    if (_cursors.value.isNotEmpty) {
      _cursors.value = const [];
      return;
    }
    final note = context.crdtHandler<CRDTFugueTextHandler>(_noteId);
    // A stable anchor mid-text: watch it follow the text when "Remote edit"
    // prepends content or when you type before it.
    _cursors.value = [
      CrdtRemoteCursor(
        id: 'bob',
        label: 'Bob',
        color: Colors.pink,
        base: note.stablePositionAt(note.length ~/ 2),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return _DemoCard(
      title: 'Note — CrdtTextFieldBuilder + remote cursors',
      description:
          'A TextField bound to a text handler: typing pushes each edit '
          'into the handler, "Remote edit" imports a change from a throwaway '
          'peer and the controller adopts it in place (caret preserved) — '
          'the badge never bumps because the subtree never rebuilds. '
          '"Toggle cursor" anchors a fake collaborator cursor that follows '
          'the text across edits.',
      actions: [
        FilledButton.tonalIcon(
          onPressed: () {
            // Naive remote peer: a throwaway document with the same handler
            // id merges cleanly via importChanges, no pre-sync needed.
            final remote = CRDTDocument(peerId: PeerId.generate());
            CRDTFugueTextHandler(remote, _noteId).insert(0, '[remote] ');
            context.crdtDocument.importChanges(remote.exportChanges());
          },
          icon: const Icon(Icons.cloud_download),
          label: const Text('Remote edit'),
        ),
        FilledButton.tonalIcon(
          onPressed: _toggleCursor,
          icon: const Icon(Icons.person_pin),
          label: const Text('Toggle cursor'),
        ),
      ],
      child: CrdtTextFieldBuilder(
        id: _noteId,
        builder: (context, controller) {
          return _RebuildBadge(
            label: 'note-text',
            child: ValueListenableBuilder<List<CrdtRemoteCursor>>(
              valueListenable: _cursors,
              builder: (context, cursors, child) {
                return CrdtRemoteCursorsOverlay(
                  id: _noteId,
                  cursors: cursors,
                  child: child!,
                );
              },
              child: TextField(
                key: const Key('note-field'),
                controller: controller,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

TextStyle? _valueStyle(BuildContext context) =>
    Theme.of(context).textTheme.titleMedium;

/// A titled card with a description, a reactive [child] and action buttons.
class _DemoCard extends StatelessWidget {
  const _DemoCard({
    required this.title,
    required this.description,
    required this.child,
    required this.actions,
  });

  final String title;
  final String description;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            child,
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      ),
    );
  }
}

/// Wraps [child] with a badge that counts (and flashes on) each rebuild of this
/// subtree — the visual proof of which regions re-render.
///
/// It is a [StatefulWidget], so its `build` runs again whenever the reactive
/// builder that returns it rebuilds; when that builder skips a rebuild the
/// count stays put.
class _RebuildBadge extends StatefulWidget {
  const _RebuildBadge({
    required this.label,
    required this.child,
    this.stretch = true,
  });

  final String label;
  final Widget child;

  /// Card content lays out full width (Column); AppBar content is compact
  /// (Row).
  final bool stretch;

  @override
  State<_RebuildBadge> createState() => _RebuildBadgeState();
}

class _RebuildBadgeState extends State<_RebuildBadge> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    _count++;
    final scheme = Theme.of(context).colorScheme;
    final chip = TweenAnimationBuilder<double>(
      key: ValueKey<int>(_count),
      tween: Tween<double>(begin: 1, end: 0),
      duration: const Duration(milliseconds: 600),
      builder: (context, t, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Color.lerp(
              scheme.surfaceContainerHighest,
              scheme.primary,
              t,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: child,
        );
      },
      child: Text(
        '⟳ ${widget.label} ×$_count',
        key: Key('rebuilds-${widget.label}'),
        style: TextStyle(
          fontSize: 12,
          color: scheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );

    if (!widget.stretch) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [chip, const SizedBox(width: 8), widget.child],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(alignment: Alignment.centerLeft, child: chip),
        const SizedBox(height: 6),
        widget.child,
      ],
    );
  }
}
