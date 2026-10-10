# ws_lint

Private, unpublished package with the analysis options of the workspace.
It also pins the versions of `lints` and `flutter_lints`.

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
| `package:ws_lint/analysis_options.yaml` | packages: the strict rule set |
| `package:ws_lint/recommended.yaml` | Dart examples and servers: `lints` recommended |
| `package:ws_lint/flutter.yaml` | Flutter examples and apps: `flutter_lints` |

```yaml
include: package:ws_lint/dart.yaml
```
