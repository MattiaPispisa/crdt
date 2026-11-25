// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf_devtools_extension/src/application/changes/change_log_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/documents/documents_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/change_mirror.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/changes/change_detail.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/changes/change_log_list.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/change_link.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The changes of the document of [mirror], and the detail of the selected
/// one.
class ChangesTab extends StatefulWidget {
  const ChangesTab({required this.mirror, this.link, super.key});

  final ChangeMirror mirror;

  /// Selects the change it asks for; `null` for none.
  final ChangeLink? link;

  @override
  State<ChangesTab> createState() => _ChangesTabState();
}

class _ChangesTabState extends State<ChangesTab> {
  late final ChangeLogCubit _log;

  @override
  void initState() {
    super.initState();
    _log = ChangeLogCubit(widget.mirror, selected: widget.link?.take());
    widget.link?.addListener(_onLink);
  }

  void _onLink() {
    if (widget.link?.take() case final id?) _log.select(id);
  }

  @override
  void dispose() {
    widget.link?.removeListener(_onLink);
    unawaited(_log.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = context.select((DocumentsCubit c) => c.state.selected);
    final localPeer = document?.peerId ?? '';
    return BlocProvider.value(
      value: _log,
      child: SplitPane(
        axis: Axis.horizontal,
        initialFractions: const [0.5, 0.5],
        children: [
          ChangeLogList(
            localPeer: localPeer,
            hasSnapshot: document?.snapshotId != null,
          ),
          ChangeDetail(localPeer: localPeer),
        ],
      ),
    );
  }
}
