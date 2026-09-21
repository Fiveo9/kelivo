import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';

import '../icons/lucide_adapter.dart';
import '../l10n/app_localizations.dart';
import '../shared/widgets/snackbar.dart';
import 'desktop_context_menu.dart';

/// A SelectionArea wrapper that enhances text selection on desktop platforms.
///
/// On desktop (Windows, macOS, Linux):
/// - Intercepts secondary (right-click) pointer events to prevent Flutter's
///   [SelectableRegion] from prematurely clearing the active selection highlight.
/// - Opens a desktop context menu at the mouse cursor position with "Copy"
///   and "Select all" options.
/// - Supports [clearSelection] via its state key for cell coordination.
///
/// On mobile platforms, it delegates directly to Flutter's native [SelectionArea].
class DesktopFloatingSelectionArea extends StatefulWidget {
  const DesktopFloatingSelectionArea({
    super.key,
    required this.child,
    this.onSelectionChanged,
    this.extraContextMenuItems,
  });

  final Widget child;
  final ValueChanged<SelectedContent?>? onSelectionChanged;
  final List<DesktopContextMenuItem> Function(bool hasSelection)?
      extraContextMenuItems;

  @override
  State<DesktopFloatingSelectionArea> createState() =>
      DesktopFloatingSelectionAreaState();
}

class DesktopFloatingSelectionAreaState
    extends State<DesktopFloatingSelectionArea> {
  final GlobalKey<SelectableRegionState> _regionKey =
      GlobalKey<SelectableRegionState>();
  String? _currentSelectedText;

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  void clearSelection() {
    _regionKey.currentState?.clearSelection();
    _currentSelectedText = null;
  }

  void _handleSelectionChanged(SelectedContent? content) {
    _currentSelectedText = content?.plainText;
    widget.onSelectionChanged?.call(content);
  }

  void _handleSecondaryClick(Offset globalPosition) async {
    final l10n = AppLocalizations.of(context)!;
    final materialL10n = MaterialLocalizations.of(context);
    final text = _currentSelectedText?.trim();
    final hasSelection = text != null && text.isNotEmpty;

    final items = <DesktopContextMenuItem>[
      if (hasSelection)
        DesktopContextMenuItem(
          icon: Lucide.Copy,
          label: l10n.shareProviderSheetCopyButton,
          onTap: () async {
            final copyText = _currentSelectedText;
            if (copyText != null && copyText.isNotEmpty) {
              await Clipboard.setData(ClipboardData(text: copyText));
              if (mounted) {
                showAppSnackBar(
                  context,
                  message: l10n.chatMessageWidgetCopiedToClipboard,
                  type: NotificationType.success,
                );
              }
            }
          },
        ),
      DesktopContextMenuItem(
        icon: Lucide.Check,
        label: materialL10n.selectAllButtonLabel,
        onTap: () {
          _regionKey.currentState?.selectAll(SelectionChangedCause.toolbar);
        },
      ),
      if (widget.extraContextMenuItems != null)
        ...widget.extraContextMenuItems!(hasSelection),
    ];

    await showDesktopContextMenuAt(
      context,
      globalPosition: globalPosition,
      items: items,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) {
      return SelectionArea(
        onSelectionChanged: widget.onSelectionChanged,
        child: widget.child,
      );
    }

    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        _SecondaryClickBlockerRecognizer:
            GestureRecognizerFactoryWithHandlers<_SecondaryClickBlockerRecognizer>(
          () => _SecondaryClickBlockerRecognizer(),
          (_SecondaryClickBlockerRecognizer instance) {
            instance.onSecondaryClick = _handleSecondaryClick;
          },
        ),
      },
      child: SelectionArea(
        key: _regionKey,
        onSelectionChanged: _handleSelectionChanged,
        contextMenuBuilder: (context, selectableRegionState) =>
            const SizedBox.shrink(),
        child: widget.child,
      ),
    );
  }
}

class _SecondaryClickBlockerRecognizer extends GestureRecognizer {
  _SecondaryClickBlockerRecognizer({super.debugOwner});

  ValueChanged<Offset>? onSecondaryClick;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if ((event.buttons & kSecondaryMouseButton) != 0) {
      startTrackingPointer(event.pointer, event.transform);
      resolve(GestureDisposition.accepted);
    } else {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      onSecondaryClick?.call(event.position);
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  String get debugDescription => 'SecondaryClickBlocker';

  @override
  void didStopTrackingLastPointer(int pointer) {}
}
