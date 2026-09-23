## 0.1.0

First release. `crdt_lf create <name>` generates a pub workspace with a
package the client and server share and a `crdt_socket_sync` WebSocket
server. The server keeps its documents in Hive, Drift, SQLite or a backend
written by hand, and the document starts empty or with one collaborative
text. Every choice has a flag, so the command also runs without prompts.
