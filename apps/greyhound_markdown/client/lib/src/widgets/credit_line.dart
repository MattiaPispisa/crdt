import 'package:flutter/material.dart';

import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/widgets/footer_link.dart';

/// The credit line, with the author's name linking to their site.
///
/// A [Wrap] rather than a rich [Text]: the name is a real [FooterLink], with
/// its own hit target, and the line reflows on a narrow footer.
class CreditLine extends StatelessWidget {
  /// Creates a credit line laid out along [alignment].
  const CreditLine({this.alignment = WrapAlignment.start, super.key});

  /// How the line sits in the space it is given.
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      alignment: alignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(kCreditPrefix, style: theme.textTheme.bodySmall),
        const FooterLink(label: kAuthor, url: kAuthorUrl),
      ],
    );
  }
}
