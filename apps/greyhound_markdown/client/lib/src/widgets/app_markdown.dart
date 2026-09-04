import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/widgets/code_element_builder.dart';

/// One builder per brightness, kept for the life of the app.
///
/// [Markdown] rebuilds its whole widget tree whenever the data changes, so the
/// builder map is read often; there is no reason to allocate a new one each
/// time.
final CodeElementBuilder _lightCodeBuilder =
    CodeElementBuilder(Brightness.light);
final CodeElementBuilder _darkCodeBuilder = CodeElementBuilder(Brightness.dark);

/// Space above and below a heading, per level.
///
/// A heading belongs to what comes *after* it, so the gap above it is several
/// times the gap below: that is what makes a section read as one block instead
/// of a line floating between two. The gap also shrinks with the rank, so the
/// outline of a long document is visible while scrolling past it. The package
/// default is [EdgeInsets.zero] for all six levels, which leaves every rank
/// with the same gap as an ordinary paragraph.
///
/// These sit on top of [MarkdownStyleSheet.blockSpacing], which the builder
/// inserts between any two blocks. The gap below is therefore small on purpose:
/// `blockSpacing` alone already keeps the heading off the first line of its
/// section, and the lowest ranks need nothing more than that.
const EdgeInsets _kH1Padding = EdgeInsets.only(top: 22, bottom: 4);
const EdgeInsets _kH2Padding = EdgeInsets.only(top: 16, bottom: 3);
const EdgeInsets _kH3Padding = EdgeInsets.only(top: 12, bottom: 2);
const EdgeInsets _kH4Padding = EdgeInsets.only(top: 10, bottom: 1);
const EdgeInsets _kH5Padding = EdgeInsets.only(top: 8, bottom: 0);
const EdgeInsets _kH6Padding = EdgeInsets.only(top: 4, bottom: 0);

/// Heading size per level, as a multiple of the body size.
///
/// Built from the body size rather than from the `textTheme` roles, because
/// those roles do not form a ramp: `titleSmall` is 14 and `bodyLarge` is 16, so
/// mapping h4 and h5 onto them makes an h5 *larger* than an h4. The ratios
/// below are the ones GitHub and Tailwind's typography plugin settle on.
const List<double> _kHeadingScale = [1.8, 1.5, 1.25, 1.1, 1.0, 0.9];

/// The style for heading level [level] (1-6), derived from [body].
TextStyle _heading(TextStyle body, int level) {
  return body.copyWith(
    fontSize: body.fontSize! * _kHeadingScale[level - 1],
    fontWeight: FontWeight.w700,
    // Tighter than body text: a heading that wraps should read as one unit.
    height: 1.25,
  );
}

/// The app's markdown styling, derived from [theme].
///
/// It starts from [MarkdownStyleSheet.fromTheme] and changes what that default
/// leaves flat:
///
/// - **heading rhythm** — see [_kH1Padding];
/// - **six distinct heading levels** — the default maps h4, h5 and h6 to the
///   same style, so three of the six ranks are indistinguishable;
/// - **theme-coloured links** — the default is a hard-coded `Colors.blue`,
///   which is hard to read on a dark background;
/// - **a hairline rule** — the default `---` is a 5 px slab;
/// - **quotes marked by a rule, not a fill**, which is quieter next to code
///   blocks;
/// - **rounded code blocks** that share the highlighter's own background.
MarkdownStyleSheet appMarkdownStyleSheet(ThemeData theme) {
  final colors = theme.colorScheme;
  final body = theme.textTheme.bodyMedium!;

  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    a: TextStyle(color: colors.primary),
    blockSpacing: 12,
    h1: _heading(body, 1),
    h1Padding: _kH1Padding,
    h2: _heading(body, 2),
    h2Padding: _kH2Padding,
    h3: _heading(body, 3),
    h3Padding: _kH3Padding,
    h4: _heading(body, 4),
    h4Padding: _kH4Padding,
    h5: _heading(body, 5),
    h5Padding: _kH5Padding,
    // Smallest rank, and the only one that is not full-strength: at this depth
    // the label matters less than the text under it.
    h6: _heading(body, 6).copyWith(color: colors.onSurfaceVariant),
    h6Padding: _kH6Padding,
    code: body.copyWith(
      fontFamily: kMonospaceFontFamily,
      fontSize: body.fontSize! * 0.9,
      backgroundColor: colors.surfaceContainerHighest,
    ),
    blockquote: body.copyWith(color: colors.onSurfaceVariant),
    blockquotePadding: const EdgeInsets.only(left: 16, top: 2, bottom: 2),
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: colors.outline, width: 4),
      ),
    ),
    // Only reached by a fence whose language the highlighter does not know;
    // the rest carry [HighlightView]'s own padding, which this matches.
    codeblockPadding: const EdgeInsets.all(12),
    codeblockDecoration: BoxDecoration(
      color: highlightBackground(theme.brightness),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: colors.outlineVariant),
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: colors.outlineVariant)),
    ),
  );
}

/// The one markdown renderer of the app.
///
/// Every place that shows markdown goes through it, so the preview and the
/// changelog agree on the flavour ([kMarkdownExtensionSet], the same one the
/// HTML and PDF exporters use), on code highlighting ([CodeElementBuilder]),
/// on the look ([appMarkdownStyleSheet]) and on what a link does.
///
/// Rendering is not cheap: it parses [data] and builds a widget per block on
/// every change. A caller that feeds it a stream of edits should slow that
/// stream down first.
class AppMarkdown extends StatelessWidget {
  /// Creates a markdown view of [data].
  const AppMarkdown({required this.data, super.key});

  /// The markdown source to render.
  final String data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Markdown(
      data: data,
      selectable: true,
      // Little on top, because a document usually opens on a heading and the
      // heading brings its own space. Generous at the bottom, so the last line
      // does not sit on the edge of the pane.
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      extensionSet: kMarkdownExtensionSet,
      styleSheet: appMarkdownStyleSheet(theme),
      builders: {
        'code': theme.brightness == Brightness.dark
            ? _darkCodeBuilder
            : _lightCodeBuilder,
      },
      onTapLink: (text, href, title) {
        if (href == null) {
          return;
        }
        launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
      },
    );
  }
}
