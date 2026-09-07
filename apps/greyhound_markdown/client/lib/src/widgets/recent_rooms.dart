import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:greyhound_markdown_client/src/application/application.dart';
import 'package:greyhound_markdown_client/src/config.dart';

/// The rooms this device opened last, as a discreet list of shortcuts back
/// into them.
///
/// The room id is the only name a document has. Without this list, someone
/// who closed the tab and did not write the id down cannot reach a room that
/// is still stored on their device.
///
/// Draws nothing until a room has been opened, so a first visit looks exactly
/// as it did before.
class RecentRooms extends StatelessWidget {
  /// Creates the list, opening a room with [onOpen] when a row is tapped.
  const RecentRooms({required this.onOpen, super.key});

  /// Called with the room id of the tapped row.
  final void Function(String roomId) onOpen;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<UserSettingsCubit, UserSettingsState,
        List<RecentRoom>>(
      selector: (settings) => settings.recentRooms,
      builder: (context, rooms) {
        if (rooms.isEmpty) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final grey = theme.colorScheme.outline;
        final now = DateTime.now().toUtc();

        return Padding(
          // Kept here rather than on the page, so an empty list takes no room
          // at all.
          padding: const EdgeInsets.only(top: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Recently opened',
                style: theme.textTheme.titleSmall?.copyWith(color: grey),
              ),
              for (final room in rooms)
                _RecentRoomRow(
                  room: room,
                  now: now,
                  onTap: () => onOpen(room.roomId),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One room of the list: its id, and how long ago it was opened.
class _RecentRoomRow extends StatelessWidget {
  const _RecentRoomRow({
    required this.room,
    required this.now,
    required this.onTap,
  });

  final RecentRoom room;

  /// Read once by the list, so every row of a build agrees on "now".
  final DateTime now;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.outline,
    );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                room.roomId,
                style: style?.copyWith(fontFamily: kMonospaceFontFamily),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Text(relativeTime(room.openedAt, now), style: style),
          ],
        ),
      ),
    );
  }
}

/// How long before [now] the moment [past] was, in words.
///
/// Coarse on purpose: the list only has to say which room was left most
/// recently. Past a week it gives the date instead, where the exact day says
/// more than "13 days ago".
@visibleForTesting
String relativeTime(DateTime past, DateTime now) {
  final elapsed = now.difference(past);
  if (elapsed.inMinutes < 1) {
    return 'just now';
  }
  if (elapsed.inHours < 1) {
    return '${elapsed.inMinutes} min ago';
  }
  if (elapsed.inDays < 1) {
    return '${elapsed.inHours} h ago';
  }
  if (elapsed.inDays < 7) {
    return elapsed.inDays == 1 ? 'yesterday' : '${elapsed.inDays} days ago';
  }

  final local = past.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}
