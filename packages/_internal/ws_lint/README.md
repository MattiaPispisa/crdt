# ws_lint

Private, unpublished package with the analysis options of the workspace.

## Usage

Add it as a dev dependency with a `path:`:

```yaml
dev_dependencies:
  ws_lint:
    path: ../../_internal/ws_lint
```

Then include one of its files in `analysis_options.yaml`:

| File | For |
| --- | --- |
| `package:ws_lint/dart.yaml` | Dart packages |
| `package:ws_lint/flutter.yaml` | Flutter packages |
| `package:ws_lint/dart_example.yaml` | Dart examples and apps |
| `package:ws_lint/flutter_example.yaml` | Flutter examples, apps and the DevTools extension: as above, for Flutter |

```yaml
include: package:ws_lint/dart.yaml
```
