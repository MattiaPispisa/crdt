// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:greyhound_markdown_client/src/l10n/l10n_extension.dart';
import 'package:greyhound_markdown_client/src/services/room/room_session.dart';
import 'package:greyhound_markdown_client/src/widgets/room_builder.dart';

/// Opens the room named by [roomId] and keeps it open for every page of the
/// room.
///
/// The pages below it, the editor and the history, read the document from
/// `CrdtProvider` and the whole [RoomSession] from the tree. Moving from one
/// page to the other closes nothing; leaving the room does.
class RoomShell extends StatelessWidget {
  /// Creates the shell of the room named by [roomId], around its pages.
  const RoomShell({required this.roomId, required this.child, super.key});

  /// The room to open. It is the document id and the relay room key.
  final String roomId;

  /// The pages of the room.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RoomBuilder(
      // A shell outlives a change of room, and a room is opened only once by
      // its state: another room needs another state.
      key: ValueKey(roomId),
      roomId: roomId,
      // The frame of the page, so nothing jumps when the room arrives.
      loading: (context) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.roomTitle(roomId))),
        body: const Center(child: CircularProgressIndicator()),
      ),
      builder: (context, room) =>
          RepositoryProvider<RoomSession>.value(value: room, child: child),
    );
  }
}
