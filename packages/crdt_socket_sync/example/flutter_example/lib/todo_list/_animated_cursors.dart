import 'package:flutter/material.dart';
import 'package:flutter_example/todo_list/_user_connected_item.dart';

class AnimatedCursors extends StatefulWidget {
  final List<UserConnectedItem> users;
  const AnimatedCursors({super.key, required this.users});

  @override
  State<AnimatedCursors> createState() => _AnimatedCursorsState();
}

class _AnimatedCursorsState extends State<AnimatedCursors>
    with TickerProviderStateMixin {
  late final Map<String, AnimationController> _controllers;
  late final Map<String, Tween<Offset>> _tweens;

  @override
  void initState() {
    super.initState();
    _controllers = {};
    _tweens = {};
    _updateCursors(widget.users, []);
  }

  @override
  void didUpdateWidget(AnimatedCursors oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateCursors(widget.users, oldWidget.users);
  }

  void _updateCursors(
    List<UserConnectedItem> newUsers,
    List<UserConnectedItem> oldUsers,
  ) {
    final oldMap = {for (var u in oldUsers) '${u.username}${u.surname}': u};
    final newMap = {for (var u in newUsers) '${u.username}${u.surname}': u};

    // Remove old controllers
    for (final oldId in oldMap.keys) {
      if (!newMap.containsKey(oldId)) {
        _controllers[oldId]?.dispose();
        _controllers.remove(oldId);
        _tweens.remove(oldId);
      }
    }

    // Add/update controllers
    for (final newUser in newUsers) {
      final id = '${newUser.username}${newUser.surname}';
      if (newUser.position == null) continue;

      final oldUser = oldMap[id];
      // Use relative positions for animation
      final from = _tweens[id]?.end ?? oldUser?.position ?? newUser.position!;
      final to = newUser.position!;

      if (_controllers.containsKey(id)) {
        _tweens[id]!.begin = from;
        _tweens[id]!.end = to;
        _controllers[id]!
          ..value = 0
          ..forward();
      } else {
        final controller = AnimationController(
          duration: const Duration(milliseconds: 200),
          vsync: this,
        );
        final tween = Tween<Offset>(begin: from, end: to);
        _controllers[id] = controller;
        _tweens[id] = tween;
        controller.forward();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    
    return AnimatedBuilder(
      animation: Listenable.merge(_controllers.values.toList()),
      builder: (context, child) {
        final animatedUsers =
            widget.users.map((user) {
              final id = '${user.username}${user.surname}';
              final controller = _controllers[id];
              final tween = _tweens[id];

              if (controller == null ||
                  tween == null ||
                  user.position == null) {
                // Convert relative position to absolute
                final absolutePosition = user.position != null
                    ? Offset(
                        user.position!.dx * screenSize.width,
                        user.position!.dy * screenSize.height,
                      )
                    : null;
                return UserConnectedItem(
                  username: user.username,
                  surname: user.surname,
                  position: absolutePosition,
                  isMe: user.isMe,
                  isHovering: user.isHovering,
                );
              }

              final animation = tween.animate(
                CurvedAnimation(parent: controller, curve: Curves.easeInOut),
              );

              // Convert relative position to absolute
              final absolutePosition = Offset(
                animation.value.dx * screenSize.width,
                animation.value.dy * screenSize.height,
              );

              return UserConnectedItem(
                username: user.username,
                surname: user.surname,
                position: absolutePosition,
                isMe: user.isMe,
                isHovering: user.isHovering,
              );
            }).toList();

        return CustomPaint(
          painter: CursorPainter(animatedUsers),
          size: Size.infinite,
        );
      },
    );
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
}

class CursorPainter extends CustomPainter {
  final List<UserConnectedItem> users;

  CursorPainter(this.users);

  @override
  void paint(Canvas canvas, Size size) {
    for (final user in users) {
      final paint =
          Paint()
            ..color = user.color
            ..style = PaintingStyle.fill;
      
      // Increase cursor size when hovering
      final cursorRadius = user.isHovering ? 8.0 : 5.0;
      
      canvas.drawCircle(user.position ?? Offset.zero, cursorRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CursorPainter oldDelegate) {
    return true;
  }
}
