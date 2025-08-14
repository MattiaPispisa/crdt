import 'package:flutter/material.dart';
import 'package:flutter_example/_view.dart';
import 'package:flutter_example/user/user_page.dart';
import 'package:go_router/go_router.dart';

final router = GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(
      path: '/home',
      builder: (context, state) => const DocumentsListPage(),
      routes: [
        GoRoute(
          path: 'documents/:id',
          builder: (context, state) {
            return TodoListPage(
              documentId: Uri.decodeComponent(state.pathParameters['id']!),
            );
          },
        ),
        GoRoute(path: 'user', builder: (context, state) => const UserPage()),
      ],
    ),
  ],
);

extension GoRouterHelper on BuildContext {
  void goToDocument(String id) {
    go('/home/documents/${Uri.encodeComponent(id)}');
  }

  void goToDocuments() {
    go('/home');
  }

  void goToUser() {
    go('/home/user');
  }
}
