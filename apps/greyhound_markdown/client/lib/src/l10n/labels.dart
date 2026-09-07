import 'package:flutter/widgets.dart';

import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/l10n/l10n_extension.dart';

/// How [link] is named in the footer and on the settings page.
///
/// The lookup lives here rather than on the enum: [ProjectLink] is a plain
/// const value with no [BuildContext] to read the translations from.
String projectLinkLabel(BuildContext context, ProjectLink link) {
  return switch (link) {
    ProjectLink.repo => context.l10n.linkRepo,
    ProjectLink.appSource => context.l10n.linkAppSource,
    ProjectLink.docs => context.l10n.linkDocs,
  };
}
