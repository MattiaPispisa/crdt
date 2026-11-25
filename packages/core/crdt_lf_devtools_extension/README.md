# CRDT LF Devtools Extension

[![docs](https://img.shields.io/badge/docs-crdt-blue?style=for-the-badge&logo=read-the-docs)](https://mattiapispisa.it/crdt/docs/deep-dive/devtools)

The DevTools extension of [`crdt_lf`](../crdt_lf/README.md). It ships inside
`crdt_lf`: open DevTools on an app that uses `crdt_lf` and enable the
`crdt_lf` tab. It only reads: it never writes to a document.

## Features

- **State**: the handlers as a tree, with their revision and their value.
- **Changes**: every change, with a lane graph of the authors and their
  merges, filters, and the decoded operation.
- **Time travel**: the value of a handler at any point of the history.
- **Storage**: the version vector, the snapshot entries and their size, the
  deleted handlers and the formats the data needs.
- **Events**: the live event log, and the delta stream of one handler. Both
  are opt-in.
- Works in debug and profile builds, on every platform, in light and dark.

See the [DevTools page](https://mattiapispisa.it/crdt/docs/deep-dive/devtools)
of the docs site.
