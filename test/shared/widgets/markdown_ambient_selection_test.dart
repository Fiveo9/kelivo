import 'dart:ui' as ui;

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/ios_tactile.dart';
import 'package:Kelivo/shared/widgets/markdown_with_highlight.dart';
import 'package:Kelivo/shared/widgets/selectable_math.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/business_test_harness.dart';

/// A paragraph, a fenced code block and another paragraph. The code block used
/// to open its own selection region, which cut drag selection and keyboard copy
/// off at the block boundary.
const _mixedText =
    'intro paragraph\n\n'
    '```dart\n'
    'final value = 1;\n'
    '```\n\n'
    'outro paragraph';

const _tableText = '| Name | Value |\n| - | - |\n| Alpha | 42 |';

void main() {
  testWidgets('code blocks join the surrounding selection region', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      _harness(
        SelectionArea(
          onSelectionChanged: (content) => selected = content?.plainText,
          child: const Align(
            alignment: Alignment.topLeft,
            child: MarkdownWithCodeHighlight(text: _mixedText),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SelectableText), findsNothing);
    expect(find.byType(SelectionArea), findsOneWidget);

    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    region.selectAll();
    await tester.pumpAndSettle();

    expect(selected, contains('intro paragraph'));
    expect(selected, contains('final value = 1;'));
    expect(selected, contains('outro paragraph'));
  });

  testWidgets('long code blocks keep one region instead of a nested one', (
    tester,
  ) async {
    final longCode = List<String>.generate(
      200,
      (index) => 'final value$index = $index;',
    ).join('\n');
    String? selected;
    await tester.pumpWidget(
      _harness(
        SelectionArea(
          onSelectionChanged: (content) => selected = content?.plainText,
          child: Align(
            alignment: Alignment.topLeft,
            child: MarkdownWithCodeHighlight(text: '```dart\n$longCode\n```'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SelectableText), findsNothing);
    expect(find.byType(SelectionArea), findsOneWidget);

    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    region.selectAll();
    await tester.pumpAndSettle();

    expect(selected, contains('final value199 = 199;'));
  });

  testWidgets('dragging across a code block selects it and both paragraphs', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      _harness(
        SelectionArea(
          onSelectionChanged: (content) => selected = content?.plainText,
          child: const Align(
            alignment: Alignment.topLeft,
            child: MarkdownWithCodeHighlight(text: _mixedText),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _dragAcrossDocument(tester);
    await tester.pumpAndSettle();

    expect(selected, contains('intro paragraph'));
    expect(selected, contains('final value = 1;'));
    expect(selected, contains('outro paragraph'));
  });

  testWidgets('desktop tables join the surrounding selection region', (
    tester,
  ) async {
    markdownTableTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => markdownTableTargetPlatformOverride = null);
    String? selected;
    await tester.pumpWidget(
      _harness(
        SelectionArea(
          onSelectionChanged: (content) => selected = content?.plainText,
          child: const Align(
            alignment: Alignment.topLeft,
            child: MarkdownWithCodeHighlight(text: _tableText),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Table), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);

    await _dragBetween(
      tester,
      _paragraphContaining('Alpha'),
      _paragraphContaining('42'),
    );
    await tester.pumpAndSettle();

    expect(selected, contains('Alpha'));
    expect(selected, contains('42'));
  });

  testWidgets(
    'keyboard copy keeps a selection that spans a code block',
    (tester) async {
      final copied = <String>[];
      _mockClipboard(copied);
      await tester.pumpWidget(
        _harness(
          const Align(
            alignment: Alignment.topLeft,
            child: SelectionArea(
              child: MarkdownWithCodeHighlight(text: _mixedText),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _dragAcrossDocument(tester);
      await tester.pumpAndSettle();
      await _copySelection(tester);

      expect(copied, hasLength(1));
      expect(copied.single, contains('intro paragraph'));
      expect(copied.single, contains('final value = 1;'));
      expect(copied.single, contains('outro paragraph'));
    },
    variant: TargetPlatformVariant.desktop(),
  );
  testWidgets('inline formulas join the surrounding selection region', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      _harness(
        SelectionArea(
          onSelectionChanged: (content) => selected = content?.plainText,
          child: const Align(
            alignment: Alignment.topLeft,
            child: MarkdownWithCodeHighlight(
              text: r'before $80\%\sim 125\%$ after',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Math), findsOneWidget);

    await _dragAcrossDocument(tester);
    await tester.pumpAndSettle();

    expect(selected, contains(r'$80\%\sim 125\%$'));
    expect(selected, contains('before'));
    expect(selected, contains('after'));
    // The formula contributes its source in place: no paragraph placeholder
    // leaks into the copy and the formula is not appended after the text.
    expect(selected, r'before $80\%\sim 125\%$ after');
    expect(selected, isNot(contains('\uFFFC')));
  });

  testWidgets('dragging over part of a formula selects the whole formula', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      _harness(
        SelectionArea(
          onSelectionChanged: (content) => selected = content?.plainText,
          child: const Align(
            alignment: Alignment.topLeft,
            child: MarkdownWithCodeHighlight(text: r'before $x^2 + y^2$ after'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Rect formula = tester.getRect(find.byType(Math));
    await _drag(
      tester,
      Offset(formula.left + formula.width * 0.35, formula.center.dy),
      Offset(formula.left + formula.width * 0.65, formula.center.dy),
    );
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected, contains(r'$x^2 + y^2$'));
    expect(selected, isNot(contains('before')));
    expect(selected, isNot(contains('after')));
  });

  testWidgets('a selection that stops before a formula leaves it out', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      _harness(
        SelectionArea(
          onSelectionChanged: (content) => selected = content?.plainText,
          child: const Align(
            alignment: Alignment.topLeft,
            child: MarkdownWithCodeHighlight(text: r'before $x^2$ after'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final RenderParagraph paragraph = _documentParagraph();
    final TextBox wordBox = paragraph
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 6),
        )
        .first;
    await _drag(
      tester,
      paragraph.localToGlobal(wordBox.toRect().topLeft + const Offset(1, 2)),
      paragraph.localToGlobal(
        wordBox.toRect().bottomRight - const Offset(1, 2),
      ),
    );
    await tester.pumpAndSettle();

    expect(selected, contains('before'));
    expect(selected, isNot(contains(r'$x^2$')));
  });

  testWidgets(
    'keyboard copy keeps a formula that the selection spans',
    (tester) async {
      final copied = <String>[];
      _mockClipboard(copied);
      await tester.pumpWidget(
        _harness(
          const Align(
            alignment: Alignment.topLeft,
            child: SelectionArea(
              child: MarkdownWithCodeHighlight(text: r'before $x^2$ after'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _dragAcrossDocument(tester);
      await tester.pumpAndSettle();
      await _copySelection(tester);

      expect(copied, hasLength(1));
      expect(copied.single, contains(r'$x^2$'));
      expect(copied.single, contains('before'));
      expect(copied.single, contains('after'));
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets('display formulas are copied with their delimiters', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      _harness(
        SelectionArea(
          onSelectionChanged: (content) => selected = content?.plainText,
          child: const Align(
            alignment: Alignment.topLeft,
            child: MarkdownWithCodeHighlight(
              text: 'para one\n\n\$\$E = mc^2\$\$\n\npara two',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    region.selectAll();
    await tester.pumpAndSettle();

    expect(selected, contains(r'$$E = mc^2$$'));
    expect(selected, contains('para one'));
    expect(selected, contains('para two'));
  });
  // Shift+Arrow does not move a `SelectionArea` selection in the widget test
  // binding, so the collapse is driven through the events the region sends.
  testWidgets('a collapse walks the formula out of the selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const Align(
          alignment: Alignment.topLeft,
          child: MarkdownWithCodeHighlight(text: r'before $x^2$ after'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dynamic formula = tester.renderObject(find.byType(SelectableLatex));

    // What the region's select-all sends to the formula.
    expect(
      formula.dispatchSelectionEvent(const SelectAllSelectionEvent()),
      SelectionResult.none,
    );
    await tester.pumpAndSettle();
    expect(
      (formula.value as SelectionGeometry).hasSelection,
      isTrue,
      reason: 'select-all should select the formula',
    );
    expect(
      (formula.getSelectedContent() as SelectedContent?)?.plainText,
      r'$x^2$',
    );

    // A collapse moves the selection end past the formula. The formula has no
    // in-between state, so it has to leave the selection entirely instead of
    // staying selected and copied forever.
    expect(
      formula.dispatchSelectionEvent(
        const GranularlyExtendSelectionEvent(
          forward: false,
          isEnd: true,
          granularity: TextGranularity.character,
        ),
      ),
      SelectionResult.previous,
    );
    await tester.pumpAndSettle();
    expect(
      (formula.value as SelectionGeometry).hasSelection,
      isFalse,
      reason: 'a collapsed selection must drop the formula',
    );
    expect(formula.getSelectedContent(), isNull);
  });

  testWidgets('table copy restores dollar math to its authored delimiters', (
    tester,
  ) async {
    final copied = <String>[];
    _mockClipboard(copied);
    // The compact (mobile) table layout is the one with the copy toolbar.
    markdownTableTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => markdownTableTargetPlatformOverride = null);
    await tester.pumpWidget(
      _harness(
        const Align(
          alignment: Alignment.topLeft,
          child: MarkdownWithCodeHighlight(
            text: '| Formula |\n| - |\n| \$E=mc^2\$ and `\$5` |',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder copyButton = find.byWidgetPredicate(
      (widget) => widget is IosIconButton && widget.semanticLabel == 'Copy',
    );
    expect(copyButton, findsOneWidget);
    await tester.tap(copyButton);
    await tester.pumpAndSettle();

    expect(copied, hasLength(1));
    expect(copied.single, contains(r'$E=mc^2$'));
    // Inline code keeps its dollar instead of the preprocessing mask.
    expect(copied.single, contains(r'`$5`'));
    expect(copied.single, isNot(contains(String.fromCharCode(0xE003))));

    // Let the copy snackbar timer finish so the tree does not leak a timer.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('a formula that stops overflowing no longer blocks the drag', (
    tester,
  ) async {
    String? selected;
    // A formula wider than the viewport starts out scrollable.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _harness(
        SelectionArea(
          onSelectionChanged: (content) => selected = content?.plainText,
          child: const Align(
            alignment: Alignment.topLeft,
            child: MarkdownWithCodeHighlight(
              text:
                  r'$aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa + bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb$',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // While it overflows, a drag inside the formula scrolls it instead of
    // starting a selection; without this the test would pass even if the
    // gesture was never enabled.
    final Rect overflowing = tester.getRect(find.byType(Math));
    await _drag(
      tester,
      Offset(overflowing.left + 8, overflowing.center.dy),
      Offset(overflowing.left + 48, overflowing.center.dy),
    );
    await tester.pumpAndSettle();
    expect(selected, isNull);

    // Widening the viewport clears the overflow, so the drag gesture has to
    // stop competing with the selection region.
    tester.view.physicalSize = const Size(1400, 640);
    await tester.pumpAndSettle();

    final Rect formula = tester.getRect(find.byType(Math));
    await _drag(
      tester,
      Offset(formula.left + formula.width * 0.3, formula.center.dy),
      Offset(formula.left + formula.width * 0.7, formula.center.dy),
    );
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected, contains('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'));
  });
}

Widget _harness(Widget child) {
  return ChangeNotifierProvider(
    create: (_) => SettingsProvider(createBusinessTestPreferences()),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void _mockClipboard(List<String> copied) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
}

Future<void> _copySelection(WidgetTester tester) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

/// Drags from the first line of the document paragraph to its last line. Block
/// widgets such as code blocks are embedded in that paragraph as widget spans,
/// so this is the gesture a reader makes across one.
Future<void> _dragAcrossDocument(WidgetTester tester) async {
  final paragraph = _documentParagraph();
  await _drag(
    tester,
    paragraph.localToGlobal(const Offset(1, 8)),
    paragraph.localToGlobal(
      Offset(paragraph.size.width - 1, paragraph.size.height - 8),
    ),
  );
}

Future<void> _dragBetween(
  WidgetTester tester,
  RenderParagraph from,
  RenderParagraph to,
) async {
  await _drag(
    tester,
    from.localToGlobal(const Offset(1, 9)),
    to.localToGlobal(Offset(to.size.width - 1, 9)),
  );
}

Future<void> _drag(WidgetTester tester, Offset start, Offset end) async {
  final gesture = await tester.startGesture(
    start,
    kind: ui.PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveTo(end);
  await tester.pump();
  await gesture.up();
  await gesture.removePointer();
}

/// The paragraph the markdown document itself renders into: tables, code and
/// other block widgets are embedded in it, so it is the tallest one on screen.
RenderParagraph _documentParagraph() {
  return find
      .byType(RichText)
      .evaluate()
      .map((element) => element.renderObject)
      .whereType<RenderParagraph>()
      .reduce((a, b) => a.size.height >= b.size.height ? a : b);
}

RenderParagraph _paragraphContaining(String text) {
  return find
      .byType(RichText)
      .evaluate()
      .map((element) => element.renderObject)
      .whereType<RenderParagraph>()
      .firstWhere((paragraph) => paragraph.text.toPlainText().contains(text));
}
