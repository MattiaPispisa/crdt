# CRDT

<p align="center">
  <a href="https://github.com/invertase/melos">
    <img src="https://img.shields.io/badge/maintained%20with-melos-f700ff.svg?style=flat-square" alt="Maintained with Melos" />
  </a>
</p>

- [CRDT](#crdt)
  - [Packages](#packages)
  - [Roadmap](#roadmap)
  - [Workspace structure](#workspace-structure)
    - [Organization](#organization)
  - [Contributing](#contributing)


## Packages

- [hlc](./packages/hlc/README.md)
- [crdt_lf](./packages/crdt_lf/README.md)
- [crdt_socket_sync](./packages/crdt_socket_sync/README.md)
- [crdt_lf_devtools_extension](./packages/crdt_lf_devtools_extension/README.md)

## [Roadmap](https://github.com/users/MattiaPispisa/projects/1)
A roadmap is available in the [project](https://github.com/users/MattiaPispisa/projects/1) page. The roadmap provides a high-level overview of the project's goals and the current status of the project.

## Workspace structure
This repository is a workspace that contains multiple packages.
Consistency is granted by the [melos](https://pub.dev/packages/melos) tool.

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