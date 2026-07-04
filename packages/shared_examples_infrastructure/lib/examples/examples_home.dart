import 'package:flutter/material.dart';
import 'package:shared_examples_infrastructure/examples/example.dart';

/// Home page listing the available [examples].
///
/// Branding is injected so each app can supply its own [logo], [title] and
/// [versionLabel]; [actions] are the app-bar trailing widgets. Tapping an item
/// navigates to `example.path` via the [Navigator] (route table derived from
/// the same [examples] list).
class ExamplesHome extends StatelessWidget {
  /// Creates the examples landing page.
  const ExamplesHome({
    super.key,
    required this.title,
    required this.logo,
    required this.versionLabel,
    required this.examples,
    this.actions = const [],
  });

  /// App-bar title.
  final String title;

  /// Brand logo shown at the top.
  final Widget logo;

  /// Version label shown under the logo (e.g. `'crdt_lf v3.2.1'`).
  final String versionLabel;

  /// The examples to list.
  final List<Example> examples;

  /// App-bar trailing actions.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const SizedBox(),
        title: Text(title),
        actions: [...actions, const SizedBox(width: 8)],
      ),
      body: Column(
        children: [
          Padding(padding: const EdgeInsets.only(top: 24), child: logo),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            child: Text(
              versionLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: examples.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final example = examples[index];
                return Card(
                  child: ListTile(
                    title: Text(example.name),
                    subtitle: Text(example.description),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pushNamed(example.path),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
