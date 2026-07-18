# CRDT

![github_starts][github_starts]
![melos_badge][melos_badge]
![repo_size][repo_size]
<div align="center">
  <img width="300" alt="logo" src="https://raw.githubusercontent.com/MattiaPispisa/crdt/refs/heads/main/assets/images/logo.png" />
</div>


- [CRDT](#crdt)
  - [Packages](#packages)
  - [Roadmap](#roadmap)
  - [Workspace structure](#workspace-structure)
    - [Organization](#organization)
  - [Contributing](#contributing)


[![docs_badge]][docs_link]

## Apps

- [greyhound_markdown](./apps/greyhound_markdown/README.md)

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
This repository is a workspace that contains multiple packages.
Consistency is granted by the [melos](https://pub.dev/packages/melos) tool.

To setup the workspace, run:

```bash
melos bootstrap
```

A command is provided to publish all packages:

```bash
melos publish --no-dry-run --git-tag-version
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
└── assets/ # contains the assets used in the documentation
    └── .../
```

## Contributing
We welcome contributions! Whether you want to:
- Fix bugs
- Add new features
- Improve documentation
- Optimize performance
- Or something else

Feel free to:
1. Check out our [GitHub repository](https://github.com/MattiaPispisa/crdt)
2. Look at the [open issues](https://github.com/MattiaPispisa/crdt/issues)
3. Submit a Pull Request

[docs_badge]: https://img.shields.io/badge/docs-crdt-blue?style=for-the-badge&logo=read-the-docs
[docs_link]: https://mattiapispisa.it/crdt/
[repo_size]: https://img.shields.io/github/languages/code-size/MattiaPispisa/crdt
[github_starts]: https://img.shields.io/github/stars/MattiaPispisa/crdt?style=flat&logo=github&color=red
[melos_badge]: https://img.shields.io/badge/maintained%20with-melos-f700ff.svg?style=flat