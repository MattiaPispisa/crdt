import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_example/_view.dart';
import 'package:go_router/go_router.dart';

final router = GoRouter(
  initialLocation: '/documents',
  routes: [
    GoRoute(
      path: '/documents',
      builder: (context, state) => const DocumentsList(),
      routes: [
        GoRoute(
          path: 'document/:id',
          builder: (context, state) {
            return TodoList(
              documentId: PeerId.parse(
                Uri.decodeComponent(state.pathParameters['id']!),
              ),
            );
          },
        ),
      ],
    ),
  ],
);

extension GoRouterHelper on BuildContext {
  void goToDocument(String id) {
    go('/documents/document/${Uri.encodeComponent(id)}');
  }

  void goToDocuments() {
    go('/documents');
  }
}
