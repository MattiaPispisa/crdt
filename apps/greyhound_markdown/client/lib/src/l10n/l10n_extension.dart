import 'package:flutter/widgets.dart';

import 'package:greyhound_markdown_client/l10n/gen/app_l10n.dart';

/// Shorthand for the localized strings of the closest [Localizations].
extension AppL10nContext on BuildContext {
  /// The translations for the locale this subtree is rendered in.
  AppL10n get l10n => AppL10n.of(this);
}
