import 'package:crdt_lf_flutter_example/generated.dart';
import 'package:crdt_lf_flutter_example/shared/app_bar_links.dart';
import 'package:flutter/material.dart';

import 'document/document_example.dart';
import 'sortable_todo_list/sortable_todo_list.dart';
import 'todo_list/todo_list.dart';

/// Describes a single example: how it is named, what it demonstrates, the
/// route it lives at and how to build it.
class Example {
  /// Creates an example descriptor.
  const Example({
    required this.name,
    required this.description,
    required this.path,
    required this.builder,
  });

  /// Display name.
  final String name;

  /// One-line description of what the example demonstrates.
  final String description;

  /// Route path (used by the router and for navigation).
  final String path;

  /// Builds the example widget.
  final WidgetBuilder builder;
}

/// The single source of truth for the example list: both this page and the
/// router are derived from it.
final kExamples = <Example>[
  Example(
    name: 'Todo List',
    description:
        'A collaborative todo list backed by CRDTListHandler. '
        'Concurrent edits merge conflict-free; includes time travel and '
        'garbage collection.',
    path: '/todo-list',
    builder: (_) => const TodoList(),
  ),
  Example(
    name: 'Sortable Todo List',
    description:
        'A reorderable todo list backed by '
        'CRDTFugueMovableListHandler. Drag to reorder; concurrent moves of the '
        'same item converge without duplicating it.',
    path: '/sortable-todo-list',
    builder: (_) => const SortableTodoList(),
  ),
  Example(
    name: 'Document',
    description:
        'A nested document built on the reference handlers '
        '(CRDTMapRefHandler / CRDTMovableListRefHandler): sortable chapters, '
        'each with sortable paragraphs holding collaborative text and an '
        'extensible, sortable list of blocks — text and todo lists '
        '(text + done). Nested CRDTs that merge conflict-free.',
    path: '/document',
    builder: (_) => const DocumentExample(),
  ),
];

/// Home page listing the available examples.
class Examples extends StatelessWidget {
  /// Creates the examples landing page.
  const Examples({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const SizedBox(),
        title: const Text('CRDT LF Examples'),
        actions: const [AppBarLinks(), SizedBox(width: 8)],
      ),
      body: Column(
        children: [
          Padding(padding: const EdgeInsets.only(top: 24), child: _Logo()),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            child: _Version(),
          ),
          Expanded(child: _List()),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/images/logo.png', height: 120);
  }
}

class _Version extends StatelessWidget {
  const _Version({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      'crdt_lf v$libraryVersion',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: kExamples.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final example = kExamples[index];
        return Card(
          child: ListTile(
            title: Text(example.name),
            subtitle: Text(example.description),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed(example.path),
          ),
        );
      },
    );
  }
}
