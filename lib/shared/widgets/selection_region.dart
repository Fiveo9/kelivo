import 'package:flutter/widgets.dart';

/// Whether an ancestor already provides text selection for this subtree, for
/// example the `SelectionArea` around a chat message body.
///
/// Selection regions do not nest. Inside an ambient region a `SelectableText`
/// or a nested `SelectionArea` becomes a region of its own, and then:
///
/// * the framework clears one side's selection as soon as the other side takes
///   focus, so the highlight disappears while the user is still reading it;
/// * keyboard copy only reaches the region that currently owns focus, so
///   Ctrl+C can end up copying the smaller nested selection or nothing at all;
/// * a drag that crosses the boundary silently drops the text on the far side,
///   which is how code blocks and table cells go missing from a copy.
///
/// Widgets that render text inside a message must keep the text in the
/// surrounding region instead of opening their own, and only own a region when
/// none exists (a standalone preview, the select & copy dialog, and so on).
bool hasAmbientSelectionRegion(BuildContext context) =>
    SelectionContainer.maybeOf(context) != null;
