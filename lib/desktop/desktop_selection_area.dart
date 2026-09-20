import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../icons/lucide_adapter.dart';
import '../l10n/app_localizations.dart';
import '../shared/widgets/snackbar.dart';
import '../theme/app_font_weights.dart';
import '../theme/app_semantic_colors.dart';

/// A SelectionArea wrapper that enhances text selection on desktop platforms.
///
/// On desktop (Windows, macOS, Linux):
/// - When the user drags to select text with the mouse, a floating "Copy" pill
///   appears near the cursor upon release for quick 1-click copying.
/// - Right-clicking on the selection displays the standard context menu.
/// - The floating pill automatically dismisses when clicking outside, scrolling,
///   or clearing selection.
///
/// On mobile platforms, it delegates directly to Flutter's native [SelectionArea].
class DesktopFloatingSelectionArea extends StatefulWidget {
  const DesktopFloatingSelectionArea({
    super.key,
    required this.child,
    this.onSelectionChanged,
  });

  final Widget child;
  final ValueChanged<SelectedContent?>? onSelectionChanged;

  @override
  State<DesktopFloatingSelectionArea> createState() =>
      _DesktopFloatingSelectionAreaState();
}

class _DesktopFloatingSelectionAreaState
    extends State<DesktopFloatingSelectionArea> {
  OverlayEntry? _overlayEntry;
  Offset? _lastPointerUpGlobalPosition;
  String? _currentSelectedText;
  bool _isPointerDown = false;

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  void _dismissOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _dismissOverlay();
    super.dispose();
  }

  void _handleSelectionChanged(SelectedContent? content) {
    _currentSelectedText = content?.plainText;
    widget.onSelectionChanged?.call(content);

    if (_currentSelectedText == null ||
        _currentSelectedText!.trim().isEmpty) {
      _dismissOverlay();
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    _isPointerDown = true;
    _dismissOverlay();
  }

  void _handlePointerUp(PointerUpEvent event) {
    _isPointerDown = false;
    _lastPointerUpGlobalPosition = event.position;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkAndShowFloatingToolbar();
      }
    });
  }

  void _checkAndShowFloatingToolbar() {
    if (!_isDesktop) return;
    final text = _currentSelectedText?.trim();
    if (text == null || text.isEmpty || _isPointerDown) {
      _dismissOverlay();
      return;
    }

    final overlay =
        Overlay.maybeOf(context) ??
        Navigator.of(context, rootNavigator: true).overlay;
    if (overlay == null) return;
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (overlayBox == null || !overlayBox.hasSize) return;

    final pointerPos = _lastPointerUpGlobalPosition;
    if (pointerPos == null) return;

    _dismissOverlay();

    final localPos = overlayBox.globalToLocal(pointerPos);
    final screenSize = overlayBox.size;

    const double pillWidth = 92.0;
    const double pillHeight = 34.0;
    const double gap = 8.0;

    double x = localPos.dx - (pillWidth / 2);
    x = x.clamp(
      8.0,
      (screenSize.width - pillWidth - 8.0).clamp(8.0, double.infinity),
    );

    double y = localPos.dy - pillHeight - gap;
    if (y < 8.0) {
      y = localPos.dy + gap;
    }
    y = y.clamp(
      8.0,
      (screenSize.height - pillHeight - 8.0).clamp(8.0, double.infinity),
    );

    _overlayEntry = OverlayEntry(
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final l10n = AppLocalizations.of(ctx)!;

        return Stack(
          children: [
            Positioned(
              left: x,
              top: y,
              child: TapRegion(
                onTapOutside: (_) => _dismissOverlay(),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    height: pillHeight,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF2C2C2E)
                          : ctx.overlaySurface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(
                          alpha: isDark ? 0.35 : 0.22,
                        ),
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.35 : 0.12,
                          ),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () async {
                        final copyText = _currentSelectedText;
                        _dismissOverlay();
                        if (copyText != null && copyText.isNotEmpty) {
                          await Clipboard.setData(
                            ClipboardData(text: copyText),
                          );
                          if (mounted) {
                            showAppSnackBar(
                              context,
                              message:
                                  l10n.chatMessageWidgetCopiedToClipboard,
                              type: NotificationType.success,
                            );
                          }
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Lucide.Copy, size: 14, color: cs.primary),
                            const SizedBox(width: 6),
                            Text(
                              l10n.shareProviderSheetCopyButton,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: AppFontWeights.medium,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 120.ms)
                      .scale(
                        begin: const Offset(0.92, 0.92),
                        duration: 120.ms,
                        curve: Curves.easeOutCubic,
                      ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) {
      return SelectionArea(
        onSelectionChanged: widget.onSelectionChanged,
        child: widget.child,
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification ||
            notification is ScrollStartNotification) {
          _dismissOverlay();
        }
        return false;
      },
      child: Listener(
        onPointerDown: _handlePointerDown,
        onPointerUp: _handlePointerUp,
        child: SelectionArea(
          onSelectionChanged: _handleSelectionChanged,
          contextMenuBuilder: (context, selectableRegionState) {
            return AdaptiveTextSelectionToolbar.selectableRegion(
              selectableRegionState: selectableRegionState,
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}
