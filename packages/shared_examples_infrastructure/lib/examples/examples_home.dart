import 'package:flutter/material.dart';
import 'package:shared_examples_infrastructure/examples/example.dart';

/// A package name + version pair shown under the logo on the examples home.
class PackageVersion {
  /// Creates a package version entry.
  const PackageVersion({required this.name, required this.version});

  /// Package name, e.g. `crdt_lf`.
  final String name;

  /// Package version, e.g. `3.2.1`.
  final String version;
}

/// Home page listing the available [examples].
///
/// Branding is injected so each app can supply its own [logo], [title] and the
/// list of [versions] of the packages it uses; [actions] are the app-bar
/// trailing widgets. Tapping an item navigates to `example.path` via the
/// [Navigator] (route table derived from the same [examples] list).
class ExamplesHome extends StatelessWidget {
  /// Creates the examples landing page.
  const ExamplesHome({
    super.key,
    required this.title,
    required this.logo,
    required this.examples,
    this.versions = const [],
    this.actions = const [],
  });

  /// App-bar title.
  final String title;

  /// Brand logo shown at the top.
  final Widget logo;

  /// The examples to list.
  final List<Example> examples;

  /// Versions of the packages used, shown under the logo.
  final List<PackageVersion> versions;

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
            child: _Versions(versions: versions),
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

/// Renders the package versions as a centered, wrapping row of `name vX.Y.Z`.
class _Versions extends StatelessWidget {
  const _Versions({required this.versions});

  final List<PackageVersion> versions;

  @override
  Widget build(BuildContext context) {
    if (versions.isEmpty) {
      return const SizedBox.shrink();
    }
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.outline,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final package in versions)
          Text('${package.name} v${package.version}', style: style),
      ],
    );
  }
}
