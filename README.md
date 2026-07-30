# CRDT

![github_starts][github_starts]
![melos_badge][melos_badge]
![repo_size][repo_size]
<div align="center">
  <img width="300" alt="logo" src="https://raw.githubusercontent.com/MattiaPispisa/crdt/refs/heads/main/assets/images/logo.png" />
</div>


- [CRDT](#crdt)
  - [Apps](#apps)
  - [Packages](#packages)
  - [Roadmap](#roadmap)
  - [Workspace structure](#workspace-structure)
    - [Melos](#melos)
    - [Setup](#setup)
    - [Organization](#organization)
    - [VS Code](#vs-code)
  - [Contributing](#contributing)


[![docs_badge]][docs_link]

## Apps

- [greyhound_markdown](https://mattiapispisa.it/crdt/greyhound_markdown/) — real-time collaborative markdown editor built on `crdt_lf` ([source](./apps/greyhound_markdown/README.md))

## Packages

- [hlc](./packages/hlc/README.md)
- [crdt_lf](./packages/crdt_lf/README.md)
- [crdt_socket_sync](./packages/crdt_socket_sync/README.md)
- [crdt_lf_flutter](./packages/crdt_lf_flutter/README.md)
- [crdt_lf_devtools_extension](./packages/crdt_lf_devtools_extension/README.md)
- [crdt_lf_hive](./packages/crdt_lf_hive/README.md)
- [crdt_lf_sqlite](./packages/crdt_lf_sqlite/README.md)
- [crdt_lf_drift](./packages/crdt_lf_drift/README.md)

## [Roadmap](https://github.com/users/MattiaPispisa/projects/1)
A roadmap is available in the [project](https://github.com/users/MattiaPispisa/projects/1) page. The roadmap provides a high-level overview of the project's goals and the current status of the project.

## Workspace structure
This repository is a workspace that contains multiple packages and apps.
Consistency is granted by the [melos](https://pub.dev/packages/melos) tool.

### Melos
[Melos](https://melos.invertase.dev/) ([pub.dev](https://pub.dev/packages/melos))
is a CLI tool for Dart/Flutter monorepos. It links the local packages together,
so every package can depend on the others without publishing them first, and it
runs the same command over all of them (format, analyze, test, publish, ...).

Every shared command lives in [`melos.yaml`](./melos.yaml) and runs with
`melos run <script>`:

| Script | What it does |
| --- | --- |
| `format` | formats the code (80 characters per line) |
| `analyze` | runs the analyzer with warnings and infos as errors |
| `test` / `test_flutter` / `test_chrome` | runs the Dart, Flutter and web tests |
| `benchmark` | runs the `crdt_lf` benchmarks |
| `devtools_build` | builds the DevTools extension |
| `docs_bs` / `docs_build` | bootstraps and builds the documentation site |
| `update_references` | propagates package/app references into the READMEs |

### Setup
The Flutter SDK is pinned with [fvm](https://fvm.app/), and the documentation
site is a [Docusaurus](https://docusaurus.io/) project, so **Node.js (with
`npm`) is required too**.

```bash
fvm install                     # installs the pinned Flutter SDK
fvm dart pub get                # resolves the workspace tools (melos included)
fvm dart run melos bootstrap    # links the packages and prepares the examples
fvm dart run melos run docs_bs  # optional: installs the documentation site (needs Node.js)
```

> **Note**
> Melos is a `dev_dependency` of the root [`pubspec.yaml`](./pubspec.yaml), so
> running it as `fvm dart run melos ...` is the safest option: you use the melos
> version pinned by this repository, with the Flutter/Dart SDK pinned by fvm.
> A globally activated melos (`dart pub global activate melos`) works as well,
> but it may be a different version than the one the workspace expects, and the
> difference usually shows up at the worst possible moment 🙃.

A command is provided to try to publish all packages:

```bash
fvm dart run melos publish --dry-run
```

This ensures that every package is formatted, analyzed, tested and built.

### Organization
The repository structure is organized as follows:

```
workspace/
├── melos.yaml # melos configuration file
├── packages/ # contains every package of the workspace
│   ├── crdt_lf/
│   │   ├── lib/
│   │   ├── example/
│   │   └── flutter_example/
│   └── .../
│       ├── lib/
│       ├── example/
│       └── flutter_example/
├── apps/ # contains the applications built on top of the packages
│   └── greyhound_markdown/
│       ├── client/
│       └── server/
├── docs/ # the documentation site (Docusaurus, Node.js project)
├── scripts/ # dart scripts used by the melos commands
└── assets/ # contains the assets used in the documentation
    └── .../
```

### VS Code
If you work with VS Code, the repository already contains a
[`.vscode`](./.vscode) folder with:

- the **recommended extensions** (Dart, Flutter, Melos, Mermaid);
- the **settings** (fvm SDK path, project dictionary for the spell checker);
- the **launch configurations** for the apps and the examples;
- the **snippets** used in the READMEs and the changelogs.

Accepting the recommended extensions gives you the smoothest experience on this
workspace.

## Contributing
Contributions are welcome: bug fixes, new features, documentation, performance
work, or anything else — a fixed typo counts too 💚.

The whole flow (roadmap, issues, pull requests, AI-assisted work) is described
in [CONTRIBUTING.md](./CONTRIBUTING.md). Please read it before opening an issue
or a pull request.

[docs_badge]: https://img.shields.io/badge/docs-crdt-blue?style=for-the-badge&logo=read-the-docs
[docs_link]: https://mattiapispisa.it/crdt/
[repo_size]: https://img.shields.io/github/languages/code-size/MattiaPispisa/crdt
[github_starts]: https://img.shields.io/github/stars/MattiaPispisa/crdt?style=flat&logo=github&color=red
[melos_badge]: https://img.shields.io/badge/maintained%20with-melos-f700ff.svg?style=flat