# CRDT LF

A Conflict-free Replicated Data Type (CRDT) implementation in Dart. 
This library provides solutions for:
- Text Editing.
- List Editing.
- Text Editing with Fugue Algorithm ([The Art of the Fugue: Minimizing Interleaving in Collaborative Text Editing" di Matthew Weidner e Martin Kleppmann](https://arxiv.org/abs/2305.00583)).

## Features

- **Hybrid Logical Clock**: Uses HLC for causal ordering of operations
- **Automatic Conflict Resolution**: Automatically resolves conflicts in a CRDT
- **Local Availability**: Operations are available locally as soon as they are applied

## Getting Started

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  crdt_lf: ^1.0.0
```

## Usage

### Basic Usage

```dart
import 'package:crdt_lf/crdt_lf.dart';

void main() {
  // Create a new document
  final doc = CRDTDocument(
    peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
  );

  // Create a text handler
  final text = CRDTFugueTextHandler(doc, 'text1');

  // Insert text
  text.insert(0, 'Hello');

  // Delete text
  text.delete(0, 2); // Deletes "He"

  // Get current value
  print(text.value); // Prints "llo"
}
```

### [Distributed Collaboration Example](https://github.com/MattiaPispisa/crdt/packages/crdt_lf/example/main.dart)


## Architecture

The library is built around several key components:

### CRDTDocument
The main document class that manages the CRDT state and handles synchronization between peers.

### Handlers
Handlers are the core components of the library. They manage the state of a specific type of data and provide operations to modify it.

- `CRDTFugueTextHandler`: Handles text editing with the Fugue algorithm.
- `CRDTListHandler`: Handles list editing.
- `CRDTTextHandler`: Handles text editing.

### DAG
A Directed Acyclic Graph that maintains the causal ordering of operations.

### Change
Represents a modification to the CRDT state, including operation ID, dependencies, and timestamp.

### Frontiers
A structure that manages the frontiers (latest operations) of the CRDT.

## Acknowledgments

- [Fugue Algorithm](https://arxiv.org/abs/2005.05914)
- [Hybrid Logical Clock](https://cse.buffalo.edu/tech-reports/2014-04.pdf)
