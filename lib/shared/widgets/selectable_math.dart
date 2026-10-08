import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Renders a formula as one atomic, selectable block.
///
/// `flutter_math_fork` paints formulas through its own `RenderObject`, so an
/// enclosing `SelectionArea` finds nothing selectable where the formula sits:
/// a drag jumps over it and a copy drops it. A paragraph stops its selectable
/// fragments at the formula's placeholder for the same reason, which is why
/// the formula goes missing from the copied text as well.
///
/// [SelectableLatex] registers a [Selectable] of its own with the closest
/// [SelectionContainer], so an enclosing selection region can select the
/// formula like a piece of text. The formula stays indivisible: an edge that
/// lands inside it selects the whole formula, and [source] - the original
/// LaTeX including its delimiters - is what the region copies.
///
/// The name avoids `SelectableMath` from `flutter_math_fork`, whose selection
/// belongs to its own overlay instead of the ambient region.
class SelectableLatex extends SingleChildRenderObjectWidget {
  /// Creates a selectable wrapper around an already rendered formula.
  const SelectableLatex({
    super.key,
    required this.source,
    required super.child,
  });

  /// The markdown source of the formula, delimiters included.
  ///
  /// The enclosing selection region copies this verbatim so a pasted formula
  /// keeps rendering.
  final String source;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSelectableLatex(
      source: source,
      registrar: SelectionContainer.maybeOf(context),
      selectionColor: _selectionColorOf(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderSelectableLatex)
      ..source = source
      ..registrar = SelectionContainer.maybeOf(context)
      ..selectionColor = _selectionColorOf(context);
  }

  // Matches the color `Text` hands to its paragraph, so a selected formula
  // highlights exactly like the text around it.
  static Color _selectionColorOf(BuildContext context) =>
      DefaultSelectionStyle.of(context).selectionColor ??
      DefaultSelectionStyle.defaultColor;
}

/// The selectable behind [SelectableLatex].
///
/// It behaves like a one-character text run that cannot be split: either the
/// whole formula is part of the selection or none of it is. Selecting it
/// contributes [source] to the region's copied content.
class _RenderSelectableLatex extends RenderProxyBox
    with Selectable, SelectionRegistrant {
  _RenderSelectableLatex({
    required this.source,
    required SelectionRegistrar? registrar,
    required this._selectionColor,
  }) {
    this.registrar = registrar;
  }

  final List<VoidCallback> _listeners = <VoidCallback>[];

  SelectionGeometry _geometry = const SelectionGeometry(
    status: SelectionStatus.none,
    hasContent: true,
  );

  /// The local positions of the selection edges that have reached this
  /// formula, used to decide whether the formula is inside the selection.
  Offset? _startEdge;
  Offset? _endEdge;

  LayerLink? _startHandleLayer;
  LayerLink? _endHandleLayer;

  /// The markdown source copied when this formula is selected.
  String source;

  Rect get _localBounds => Offset.zero & size;

  bool get _isSelected => _geometry.hasSelection;

  Color get selectionColor => _selectionColor;
  Color _selectionColor;
  set selectionColor(Color value) {
    if (value == _selectionColor) {
      return;
    }
    _selectionColor = value;
    if (_isSelected) {
      markNeedsPaint();
    }
  }

  @override
  SelectionGeometry get value => _geometry;

  @override
  int get contentLength => source.length;

  @override
  List<Rect> get boundingBoxes => <Rect>[_localBounds];

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @override
  void dispose() {
    _listeners.clear();
    super.dispose();
  }

  @override
  SelectedContent? getSelectedContent() {
    return _isSelected ? SelectedContent(plainText: source) : null;
  }

  @override
  SelectedContentRange? getSelection() {
    return _isSelected
        ? SelectedContentRange(startOffset: 0, endOffset: source.length)
        : null;
  }

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    if (!attached) {
      assert(
        startHandle == null && endHandle == null,
        'Only clean up can be called.',
      );
      return;
    }
    if (_startHandleLayer != startHandle) {
      _startHandleLayer = startHandle;
      markNeedsPaint();
    }
    if (_endHandleLayer != endHandle) {
      _endHandleLayer = endHandle;
      markNeedsPaint();
    }
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    switch (event.type) {
      case SelectionEventType.startEdgeUpdate:
      case SelectionEventType.endEdgeUpdate:
        return _handleEdgeUpdate(event as SelectionEdgeUpdateEvent);
      case SelectionEventType.clear:
        _setEdges(start: null, end: null);
        return SelectionResult.none;
      case SelectionEventType.selectAll:
        _selectWholeFormula();
        return SelectionResult.none;
      // A word or paragraph boundary that lands on the formula is what a
      // double/triple click on it produces; the formula has no smaller unit.
      // `SelectParagraphSelectionEvent.absorb` is only used on the
      // `SelectableText` path, where this block is never registered, so the
      // region path must keep answering `end` - a block that answered `next`
      // would leave the boundary search without a hit.
      case SelectionEventType.selectWord:
      case SelectionEventType.selectParagraph:
        _selectWholeFormula();
        return SelectionResult.end;
      // Keyboard and edge-drag extension only moves the edge that owns this
      // formula; hand the other direction back to the region so it reaches the
      // neighbouring text.
      case SelectionEventType.granularlyExtendSelection:
        final GranularlyExtendSelectionEvent granular =
            event as GranularlyExtendSelectionEvent;
        // The region only routes this to the selectable that owns the edge and
        // never revisits the opposite edge, so the block has to walk its own
        // edge across itself. Without that a collapse would leave the formula
        // selected (and copied) after the selection moved past it.
        _moveEdge(
          isEnd: granular.isEnd,
          forward: granular.forward,
          horizontalOnly: true,
        );
        return granular.forward
            ? SelectionResult.next
            : SelectionResult.previous;
      case SelectionEventType.directionallyExtendSelection:
        final DirectionallyExtendSelectionEvent directional =
            event as DirectionallyExtendSelectionEvent;
        _moveEdge(
          isEnd: directional.isEnd,
          forward: switch (directional.direction) {
            SelectionExtendDirection.previousLine ||
            SelectionExtendDirection.backward => false,
            SelectionExtendDirection.nextLine ||
            SelectionExtendDirection.forward => true,
          },
          // A line movement leaves the formula above or below instead of
          // walking along the reading direction.
          horizontalOnly:
              directional.direction == SelectionExtendDirection.forward ||
              directional.direction == SelectionExtendDirection.backward,
        );
        return switch (directional.direction) {
          SelectionExtendDirection.previousLine => SelectionResult.previous,
          SelectionExtendDirection.nextLine => SelectionResult.next,
          // The region asserts `end` for the two reading-direction movements.
          SelectionExtendDirection.forward ||
          SelectionExtendDirection.backward => SelectionResult.end,
        };
    }
  }

  /// Moves the named selection edge to the far side of this formula.
  ///
  /// A formula is indivisible, so an edge extension that crosses it has to land
  /// outside: [forward] towards the reading direction, or above/below for a
  /// line movement. The edge pair then decides whether the formula stays
  /// selected, which is how spanning keeps it and collapsing drops it.
  void _moveEdge({
    required bool isEnd,
    required bool forward,
    required bool horizontalOnly,
  }) {
    final Rect bounds = _localBounds;
    final Offset moved;
    if (!horizontalOnly) {
      moved = forward
          ? Offset(bounds.right, bounds.bottom + 1)
          : Offset(bounds.left, bounds.top - 1);
    } else {
      moved = forward
          ? Offset(bounds.right + 1, bounds.bottom)
          : Offset(bounds.left - 1, bounds.top);
    }
    if (isEnd) {
      _endEdge = moved;
    } else {
      _startEdge = moved;
    }
    _refreshSelection();
  }

  SelectionResult _handleEdgeUpdate(SelectionEdgeUpdateEvent event) {
    final Offset local = globalToLocal(event.globalPosition);
    if (event.type == SelectionEventType.endEdgeUpdate) {
      _endEdge = local;
    } else {
      _startEdge = local;
    }
    _refreshSelection();
    // The updated edge decides where the region continues looking; a formula
    // that is merely spanned by the other edge keeps its selection.
    return SelectionUtils.getResultBasedOnRect(_localBounds, local);
  }

  void _selectWholeFormula() {
    final Rect bounds = _localBounds;
    // Anchor the edges just outside the formula. The formula has no in-between
    // state, and edges placed inside it would keep it selected - and copied -
    // even after a collapse moved the other edge past it.
    _setEdges(
      start: Offset(bounds.left - 1, bounds.top),
      end: Offset(bounds.right + 1, bounds.bottom),
    );
  }

  void _setEdges({required Offset? start, required Offset? end}) {
    if (start == _startEdge && end == _endEdge) {
      return;
    }
    _startEdge = start;
    _endEdge = end;
    _refreshSelection();
  }

  void _refreshSelection() {
    final Rect bounds = _localBounds;
    final Offset? start = _startEdge;
    final Offset? end = _endEdge;
    // A formula is selected when an edge lands on it, or when the selection
    // spans across it, which is what an edge on each side means.
    final bool spansFormula =
        start != null &&
        end != null &&
        Rect.fromPoints(start, end).overlaps(bounds);
    final bool selected =
        bounds.isFinite &&
        !bounds.isEmpty &&
        (_containsInclusive(bounds, start) ||
            _containsInclusive(bounds, end) ||
            spansFormula);
    if (!selected) {
      _publish(
        const SelectionGeometry(status: SelectionStatus.none, hasContent: true),
      );
      return;
    }
    _publish(
      SelectionGeometry(
        status: SelectionStatus.uncollapsed,
        hasContent: true,
        selectionRects: <Rect>[bounds],
        startSelectionPoint: SelectionPoint(
          localPosition: Offset(bounds.left, bounds.bottom),
          lineHeight: bounds.height,
          handleType: TextSelectionHandleType.left,
        ),
        endSelectionPoint: SelectionPoint(
          localPosition: Offset(bounds.right, bounds.bottom),
          lineHeight: bounds.height,
          handleType: TextSelectionHandleType.right,
        ),
      ),
    );
  }

  static bool _containsInclusive(Rect bounds, Offset? point) {
    if (point == null) {
      return false;
    }
    return point.dx >= bounds.left &&
        point.dx <= bounds.right &&
        point.dy >= bounds.top &&
        point.dy <= bounds.bottom;
  }

  void _publish(SelectionGeometry geometry) {
    if (geometry == _geometry) {
      return;
    }
    _geometry = geometry;
    markNeedsPaint();
    for (final VoidCallback listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  @override
  void performLayout() {
    super.performLayout();
    if (_isSelected) {
      // Keep the cached selection rect and handle anchors in step with a size
      // change, for example when a streaming formula grows.
      _refreshSelection();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // The highlight goes below the formula, matching how a paragraph paints
    // its selection under the glyphs.
    if (_isSelected) {
      context.canvas.drawRect(
        _localBounds.shift(offset),
        Paint()
          ..style = PaintingStyle.fill
          ..color = _selectionColor,
      );
    }
    super.paint(context, offset);
    final SelectionPoint? startPoint = _geometry.startSelectionPoint;
    if (_startHandleLayer != null && startPoint != null) {
      context.pushLayer(
        LeaderLayer(
          link: _startHandleLayer!,
          offset: offset + startPoint.localPosition,
        ),
        (PaintingContext context, Offset offset) {},
        Offset.zero,
      );
    }
    final SelectionPoint? endPoint = _geometry.endSelectionPoint;
    if (_endHandleLayer != null && endPoint != null) {
      context.pushLayer(
        LeaderLayer(
          link: _endHandleLayer!,
          offset: offset + endPoint.localPosition,
        ),
        (PaintingContext context, Offset offset) {},
        Offset.zero,
      );
    }
  }
}
