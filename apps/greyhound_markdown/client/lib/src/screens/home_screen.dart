import 'dart:math';

import 'package:flutter/material.dart';

import 'package:greyhound_markdown_client/src/widgets/app_footer.dart';

const _logoWidth = 300.0;

const _palette = [
  Color(0xFFE53935),
  Color(0xFF8E24AA),
  Color(0xFF3949AB),
  Color(0xFF039BE5),
  Color(0xFF00897B),
  Color(0xFF7CB342),
  Color(0xFFFB8C00),
  Color(0xFF6D4C41),
];

String _randomRoomId() {
  final random = Random.secure();
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return String.fromCharCodes(
    List.generate(8, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
  );
}

/// Landing page: pick a display name and color, then create a new room or
/// join an existing one by id. Profile travels to the editor as route
/// arguments; opening a `/room/<id>` URL directly uses defaults.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class HomeScreenArguments {
  const HomeScreenArguments({required this.name, required this.color});

  final String name;
  final Color color;
}

class _HomeScreenState extends State<HomeScreen> {
  final _nameController = TextEditingController();
  final _roomController = TextEditingController();
  late Color _color = _palette[Random().nextInt(_palette.length)];

  @override
  void dispose() {
    _nameController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  void _openRoom(String roomId) {
    final name = _nameController.text.trim();
    Navigator.of(context).pushNamed(
      '/room/$roomId',
      arguments: HomeScreenArguments(
        name: name.isEmpty ? 'anonymous' : name,
        color: _color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const AppFooter(),
      // Scroll on short viewports (mobile landscape / small phones) so the
      // content is never clipped; still vertically centered when there is
      // room (minHeight = viewport keeps the Center meaningful).
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Image.asset(
                          'assets/images/greyhound_markdown_logo.png',
                          height: _logoWidth,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Greyhound Markdown',
                          style: Theme.of(context).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Your name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final color in _palette)
                              GestureDetector(
                                onTap: () => setState(() => _color = color),
                                child: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: color,
                                  child: _color == color
                                      ? const Icon(
                                          Icons.check,
                                          size: 16,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        FilledButton.icon(
                          onPressed: () => _openRoom(_randomRoomId()),
                          icon: const Icon(Icons.add),
                          label: const Text('Create a new room'),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _roomController,
                                decoration: const InputDecoration(
                                  labelText: 'Room id',
                                  border: OutlineInputBorder(),
                                ),
                                onSubmitted: (value) {
                                  if (value.trim().isNotEmpty) {
                                    _openRoom(value.trim());
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: () {
                                final id = _roomController.text.trim();
                                if (id.isNotEmpty) _openRoom(id);
                              },
                              child: const Text('Join'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
