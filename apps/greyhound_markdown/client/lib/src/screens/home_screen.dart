import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:greyhound_markdown_client/src/application/application.dart';
import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/widgets/app_footer.dart';

const _logoWidth = 300.0;

/// Landing page: pick a display name and color, then create a new room or
/// join an existing one by id.
///
/// Name and color are kept in [UserSettingsCubit], so they come back on the
/// next visit and the editor reads them straight from there.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final TextEditingController _nameController;
  final _roomController = TextEditingController();

  /// Whether the visitor arrived without a stored name — the one case where
  /// the page takes the focus. Read once, so it cannot move under the user
  /// while they type.
  late final bool _nameWasEmpty;

  @override
  void initState() {
    super.initState();
    // Hydration is synchronous, so the stored name is already there.
    final settings = context.read<UserSettingsCubit>().state;
    _nameController = TextEditingController(text: settings.name);
    _nameWasEmpty = settings.name.trim().isEmpty;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  void _openRoom(String roomId) {
    Navigator.of(context).pushNamed(roomRoute(roomId));
  }

  /// Enter, from either field: into the room whose id is typed, or into a
  /// brand new one when there is no usable id to join.
  ///
  /// Never a dead key — with the form half filled, creating is the only thing
  /// left to mean.
  void _submit() {
    _openRoom(parseRoomId(_roomController.text) ?? generateRoomId());
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
                        Image.asset(kLogoAsset, height: _logoWidth),
                        const SizedBox(height: 16),
                        Text(
                          kAppName,
                          style: Theme.of(context).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        TextField(
                          controller: _nameController,
                          // The only field the page focuses on its own, and
                          // only while it is still empty.
                          autofocus: _nameWasEmpty,
                          onChanged: context.read<UserSettingsCubit>().setName,
                          textInputAction: TextInputAction.go,
                          onSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            labelText: 'Your name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const _ColorPicker(),
                        const SizedBox(height: 32),
                        // Rebuilds on every keystroke in the room field: which
                        // of the two actions is the filled one depends on it.
                        ListenableBuilder(
                          listenable: _roomController,
                          builder: (context, _) => _RoomActions(
                            controller: _roomController,
                            onCreate: () => _openRoom(generateRoomId()),
                            onSubmit: _submit,
                          ),
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

/// The palette, with a check mark on the color currently stored in
/// [UserSettingsCubit].
class _ColorPicker extends StatelessWidget {
  const _ColorPicker();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<UserSettingsCubit, UserSettingsState, Color>(
      selector: (settings) => settings.color,
      builder: (context, selected) => Wrap(
        spacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final color in kAvatarPalette)
            GestureDetector(
              onTap: () => context.read<UserSettingsCubit>().setColor(color),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: color,
                child: selected == color
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// The two ways into a room, with the emphasis on the one the user is heading
/// for: filled *Create* until the field holds an id worth joining, filled
/// *Join* — and a merely outlined *Create* — from that point on.
class _RoomActions extends StatelessWidget {
  const _RoomActions({
    required this.controller,
    required this.onCreate,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final VoidCallback onCreate;

  /// Join what is typed, or create a room when it names none.
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    // The typed id, once it is one — half-typed input reads as "no id yet",
    // which is what keeps Create the highlighted action.
    final joining = parseRoomId(controller.text) != null;
    const createIcon = Icon(Icons.add);
    const createLabel = Text('Create a new room');
    const joinLabel = Text('Join');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (joining)
          OutlinedButton.icon(
            onPressed: onCreate,
            icon: createIcon,
            label: createLabel,
          )
        else
          FilledButton.icon(
            onPressed: onCreate,
            icon: createIcon,
            label: createLabel,
          ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => onSubmit(),
                decoration: const InputDecoration(
                  labelText: 'Room id',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (joining)
              FilledButton(onPressed: onSubmit, child: joinLabel)
            else
              // Disabled rather than a no-op: with no room to join, the only
              // live action left is the filled one above.
              const OutlinedButton(onPressed: null, child: joinLabel),
          ],
        ),
      ],
    );
  }
}
