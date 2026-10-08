import 'dart:ui' as ui;

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/markdown_with_highlight.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/business_test_harness.dart';

/// A paragraph, a fenced code block and another paragraph. Code blocks and
/// table cells used to open their own selection region, which cut drag
/// selection and keyboard copy off at the block boundary.
const _mixedText =
    'intro paragraph\n\n'
    '```dart\n'
    'final value = 1;\n'
    '```\n\n'
    'outro paragraph';

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
            child: MarkdownWithCodeHighlight(
              text: '| Name | Value |\n| - | - |\n| Alpha | 42 |',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Table), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);

    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    region.selectAll();
    await tester.pumpAndSettle();

    expect(selected, contains('Alpha'));
    expect(selected, contains('42'));
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

    await _dragAcross(
      tester,
      _paragraphContaining('intro paragraph'),
      _paragraphContaining('outro paragraph'),
    );
    await tester.pumpAndSettle();

    expect(selected, contains('intro paragraph'));
    expect(selected, contains('final value = 1;'));
    expect(selected, contains('outro paragraph'));
  });

  testWidgets('keyboard copy keeps a selection that spans a code block', (
    tester,
  ) async {
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

    await _dragAcross(
      tester,
      _paragraphContaining('intro paragraph'),
      _paragraphContaining('outro paragraph'),
    );
    await tester.pumpAndSettle();
    await _copySelection(tester);

    expect(copied, hasLength(1));
    expect(copied.single, contains('intro paragraph'));
    expect(copied.single, contains('final value = 1;'));
    expect(copied.single, contains('outro paragraph'));
  }, variant: TargetPlatformVariant.desktop());
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

/// Drags from the start of one paragraph to the end of another.
Future<void> _dragAcross(
  WidgetTester tester,
  RenderParagraph first,
  RenderParagraph last,
) async {
  final start = first.localToGlobal(const Offset(1, 8));
  final end = last.localToGlobal(Offset(last.size.width - 1, 8));
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

RenderParagraph _paragraphContaining(String text) {
  return find
      .byType(RichText)
      .evaluate()
      .map((element) => element.renderObject)
      .whereType<RenderParagraph>()
      .firstWhere((paragraph) => paragraph.text.toPlainText().contains(text));
}
