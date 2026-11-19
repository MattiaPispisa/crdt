// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/presentation/widgets/peer_color.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

/// A peer: its color and the first 8 characters of its id.
class PeerChip extends StatelessWidget {
  const PeerChip(this.peerId, {this.local = false, super.key});

  final String peerId;

  /// Adds the [localLabel] of the peer of the selected document.
  final bool local;

  /// The label of the local peer.
  static const String localLabel = 'me';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final short = peerId.length > 8 ? peerId.substring(0, 8) : peerId;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: peerColor(peerId)),
        const SizedBox(width: densePadding),
        Flexible(
          child: Text(
            short,
            style: theme.fixedFontStyle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (local) ...[
          const SizedBox(width: densePadding),
          const Flexible(child: RoundedLabel(labelText: localLabel)),
        ],
      ],
    );
  }
}
