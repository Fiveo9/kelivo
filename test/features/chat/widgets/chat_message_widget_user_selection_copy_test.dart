import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/core/providers/user_provider.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/business_test_harness.dart';

const _messageText = 'alpha bravo charlie';
const _wordSelection = TextSelection(baseOffset: 6, extentOffset: 11);

void main() {
  testWidgets(
    'right-click on a selection offers the selected text',
    (tester) async {
      final copied = <String>[];
      _mockClipboard(copied);
      await _pumpUserBubble(tester);
      final l10n = _l10n(tester);
      final paragraph = _paragraphContaining(_messageText);
      await _selectWord(tester, paragraph);
      await _rightClickAt(tester, paragraph, _wordSelection);

      expect(find.text(l10n.shareProviderSheetCopyButton), findsOneWidget);
      expect(find.text(l10n.selectCopyPageCopyAll), findsOneWidget);

      await tester.tap(find.text(l10n.shareProviderSheetCopyButton));
      await tester.pumpAndSettle();

      expect(copied, ['bravo']);
      // Let the copy snackbar's auto-dismiss timer finish.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'right-click without a selection copies the whole message',
    (tester) async {
      final copied = <String>[];
      _mockClipboard(copied);
      await _pumpUserBubble(tester);
      final l10n = _l10n(tester);
      final paragraph = _paragraphContaining(_messageText);
      // The bubble owns right-clicks, so the region keeps whatever selection it
      // holds: with none, the menu only offers the whole message.
      await _rightClickAt(
        tester,
        paragraph,
        const TextSelection(baseOffset: 0, extentOffset: 1),
      );

      expect(find.text(l10n.shareProviderSheetCopyButton), findsOneWidget);
      expect(find.text(l10n.selectCopyPageCopyAll), findsNothing);

      await tester.tap(find.text(l10n.shareProviderSheetCopyButton));
      await tester.pumpAndSettle();

      expect(copied, [_messageText]);
      // Let the copy snackbar's auto-dismiss timer finish.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'keyboard copy copies the selected word of a user bubble',
    (tester) async {
      final copied = <String>[];
      _mockClipboard(copied);
      await _pumpUserBubble(tester);
      await _selectWord(tester, _paragraphContaining(_messageText));
      await _copySelection(tester);

      expect(copied, ['bravo']);
    },
    variant: TargetPlatformVariant.desktop(),
  );
}

Future<void> _pumpUserBubble(WidgetTester tester) async {
  final harness = await createBusinessTestHarness(
    initial: {'display_chat_message_background_style_v1': 'solid'},
  );
  final settings = SettingsProvider(harness.preferences);
  await settings.loaded;
  final message = ChatMessage(
    role: 'user',
    content: _messageText,
    conversationId: 'conversation-user-selection',
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider(
          create: (_) =>
              AssistantProvider(preferences: createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              TtsProvider(preferences: createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              UserProvider(preferences: createBusinessTestPreferences()),
        ),
        ChangeNotifierProvider<ToolApprovalService>.value(
          value: ToolApprovalService(),
        ),
        ChangeNotifierProvider<AskUserInteractionService>.value(
          value: AskUserInteractionService(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatMessageWidget(message: message, showModelIcon: false),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The menu labels come from the app localizations, so the assertions do not
/// depend on the locale the test binding happens to run under.
AppLocalizations _l10n(WidgetTester tester) {
  return AppLocalizations.of(tester.element(find.byType(ChatMessageWidget)))!;
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

/// Double-clicks the word at [selection] inside [paragraph].
Future<void> _selectWord(WidgetTester tester, RenderParagraph paragraph) async {
  final target = _centerOf(paragraph, _wordSelection);
  final mouse = await tester.startGesture(
    target,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump(const Duration(milliseconds: 16));
  await mouse.up();
  await tester.pump(const Duration(milliseconds: 50));
  await mouse.down(target);
  await tester.pump(const Duration(milliseconds: 16));
  await mouse.up();
  await tester.pump(const Duration(milliseconds: 16));
  await mouse.removePointer();
  await tester.pumpAndSettle();
}

Future<void> _rightClickAt(
  WidgetTester tester,
  RenderParagraph paragraph,
  TextSelection selection,
) async {
  final gesture = await tester.startGesture(
    _centerOf(paragraph, selection),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

Offset _centerOf(RenderParagraph paragraph, TextSelection selection) {
  final box = paragraph.getBoxesForSelection(selection).first.toRect();
  return paragraph.localToGlobal(box.center);
}

RenderParagraph _paragraphContaining(String text) {
  return find
      .byType(RichText)
      .evaluate()
      .map((element) => element.renderObject)
      .whereType<RenderParagraph>()
      .firstWhere((paragraph) => paragraph.text.toPlainText().contains(text));
}
