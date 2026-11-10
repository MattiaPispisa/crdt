import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

type SidebarItem = SidebarsConfig[string] extends (infer T)[] ? T : never;

// A section whose label opens its overview page, which is also listed as its
// first entry: the reader sees that the section has a page of its own.
function section(
  label: string,
  overview: string,
  items: SidebarItem[],
  options: {collapsed?: boolean} = {},
): SidebarItem {
  return {
    type: 'category',
    label,
    link: {type: 'doc', id: overview},
    collapsed: options.collapsed,
    items: [{type: 'doc', id: overview, label: 'Overview'}, ...items],
  };
}

const sidebars: SidebarsConfig = {
  docs: [
    'introduction',
    'getting-started',
    section('Recipes', 'recipes/index', [
      'recipes/two-peers',
      'recipes/persisted-note',
      'recipes/drift-note',
      'recipes/hive-note',
      'recipes/flutter-note',
      'recipes/notes-list',
      'recipes/todo-list',
      'recipes/todo-aggregate',
      'recipes/quill-editor',
      'recipes/server-client-sync',
      'recipes/relay-rooms',
      'recipes/offline-first-replica',
      'recipes/presence-cursors',
      'recipes/dart-frog-relay',
      'recipes/dart-frog-server',
      'recipes/serverpod-relay',
      'recipes/serverpod-server',
      'recipes/hybrid-clock',
    ]),
    section('The document', 'document/index', [
      'document/handlers',
      'document/changes',
      'document/snapshots-history',
      'document/errors',
    ]),
    section(
      'Use cases',
      'use-cases/index',
      [
        'use-cases/collaborative-text',
        'use-cases/rich-text',
        'use-cases/lists',
        'use-cases/maps-sets-values',
        'use-cases/containers',
        'use-cases/aggregates',
        'use-cases/undo-redo',
        'use-cases/history',
        'use-cases/custom-value-types',
      ],
      {collapsed: false},
    ),
    section(
      'Connectors',
      'connectors/index',
      [
        'connectors/replica',
        section('Persistence', 'connectors/persistence/index', [
          'connectors/persistence/adapters',
          'connectors/persistence/working-with-storage',
          'connectors/persistence/how-it-works',
          'connectors/persistence/build-your-own',
        ]),
        section('Flutter', 'connectors/flutter/index', [
          'connectors/flutter/delta-widgets',
          'connectors/flutter/text-fields',
          'connectors/flutter/presence',
          section('Editors', 'connectors/flutter/editors/index', [
            'connectors/flutter/editors/quill',
          ]),
        ]),
        section('Sync', 'connectors/sync/index', [
          section('Server–client mode', 'connectors/sync/server-client', [
            'connectors/sync/server-registry',
          ]),
          section('Relay mode', 'connectors/sync/relay', [
            'connectors/sync/relay-protocol',
          ]),
          section('Both modes', 'connectors/sync/both-modes', [
            'connectors/sync/server-frameworks',
            'connectors/sync/plugins',
            'connectors/sync/connection',
            'connectors/sync/compatibility',
            'connectors/sync/compression',
            'connectors/sync/custom-transport',
          ]),
        ]),
      ],
      {collapsed: false},
    ),
    section('Deep dive', 'deep-dive/index', [
      'deep-dive/time-hlc',
      'deep-dive/documents-and-changes',
      'deep-dive/transactions',
      'deep-dive/reactivity',
      'deep-dive/handler-deltas',
      'deep-dive/state-cache',
      'deep-dive/snapshots',
      'deep-dive/binary-format',
      'deep-dive/text-positions',
      'deep-dive/handler-specs',
      'deep-dive/custom-handlers',
      'deep-dive/flutter-internals',
      'deep-dive/editor-binding',
      'deep-dive/devtools',
    ]),
    section('Benchmarks', 'benchmarks/index', [
      'benchmarks/crdt_lf',
      'benchmarks/hlc',
      'benchmarks/crdt_lf_flutter',
      'benchmarks/crdt_lf_quill',
    ]),
    section('Migrations', 'migrations/index', [
      {
        type: 'category',
        label: 'crdt_lf',
        items: ['migrations/crdt_lf/v5-0', 'migrations/crdt_lf/v4-0'],
      },
      {
        type: 'category',
        label: 'crdt_socket_sync',
        items: ['migrations/crdt_socket_sync/v0-9'],
      },
    ]),
    'packages',
    'contributing',
    'references',
  ],
};

export default sidebars;
