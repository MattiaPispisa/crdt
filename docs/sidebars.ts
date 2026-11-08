import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

const sidebars: SidebarsConfig = {
  docs: [
    'introduction',
    'getting-started',
    {
      type: 'category',
      label: 'Use cases',
      link: {type: 'doc', id: 'use-cases/index'},
      collapsed: false,
      items: [
        'use-cases/collaborative-text',
        'use-cases/rich-text',
        'use-cases/lists',
        'use-cases/maps-sets-values',
        'use-cases/containers',
        'use-cases/aggregates',
        'use-cases/undo-redo',
        'use-cases/custom-value-types',
      ],
    },
    {
      type: 'category',
      label: 'Connectors',
      link: {type: 'doc', id: 'connectors/index'},
      collapsed: false,
      items: [
        'connectors/replica',
        {
          type: 'category',
          label: 'Persistence',
          link: {type: 'doc', id: 'connectors/persistence/index'},
          items: [
            'connectors/persistence/adapters',
            'connectors/persistence/working-with-storage',
            'connectors/persistence/how-it-works',
            'connectors/persistence/build-your-own',
          ],
        },
        {
          type: 'category',
          label: 'Flutter',
          link: {type: 'doc', id: 'connectors/flutter/index'},
          items: [
            'connectors/flutter/delta-widgets',
            'connectors/flutter/text-fields',
            'connectors/flutter/presence',
            {
              type: 'category',
              label: 'Editors',
              link: {type: 'doc', id: 'connectors/flutter/editors/index'},
              items: ['connectors/flutter/editors/quill'],
            },
          ],
        },
        {
          type: 'category',
          label: 'Sync',
          link: {type: 'doc', id: 'connectors/sync/index'},
          items: [
            'connectors/sync/server-frameworks',
            'connectors/sync/server-client',
            'connectors/sync/server-registry',
            'connectors/sync/relay',
            'connectors/sync/relay-protocol',
            'connectors/sync/plugins',
            'connectors/sync/connection',
            'connectors/sync/compatibility',
            'connectors/sync/compression',
            'connectors/sync/custom-transport',
          ],
        },
      ],
    },
    {
      type: 'category',
      label: 'Deep dive',
      link: {type: 'doc', id: 'deep-dive/index'},
      items: [
        'deep-dive/time-hlc',
        'deep-dive/documents-and-changes',
        'deep-dive/transactions',
        'deep-dive/reactivity',
        'deep-dive/handler-deltas',
        'deep-dive/state-cache',
        'deep-dive/snapshots',
        'deep-dive/binary-format',
        'deep-dive/text-positions',
        'deep-dive/custom-handlers',
        'deep-dive/flutter-internals',
        'deep-dive/benchmarks',
        'deep-dive/devtools',
      ],
    },
    {
      type: 'category',
      label: 'Migrations',
      link: {type: 'doc', id: 'migrations/index'},
      items: [
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
      ],
    },
    'packages',
    'contributing',
    'references',
  ],
};

export default sidebars;
