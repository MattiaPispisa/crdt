/// Shared UI and example logic reused by the crdt_lf and crdt_socket_sync
/// Flutter example apps.
library;

// Sync seam + base controller.
export 'shared/example_document.dart';
export 'shared/example_sync_session.dart';
export 'shared/peer_colors.dart';
export 'shared/text_cursor_presence.dart';

// Shared UI.
export 'shared/add_item_dialog.dart';
export 'shared/app_bar_links.dart';
export 'shared/crdt_text_field.dart';
export 'shared/document_controls.dart';
export 'shared/document_pane.dart';
export 'shared/example_scaffold.dart';
export 'shared/layout.dart';

// Example machinery + identifiers.
export 'examples/example.dart';
export 'examples/examples_home.dart';
export 'examples/ids.dart';

// The example screens (each builds an ExampleScaffold from a SessionsFactory).
export 'examples/document/document_example.dart';
export 'examples/sortable_todo_list/sortable_todo_list.dart';
export 'examples/todo_list/todo_list.dart';
