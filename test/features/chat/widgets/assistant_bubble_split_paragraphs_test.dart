import "../../../support/business_test_harness.dart";

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/tts_provider.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/home/services/ask_user_interaction_service.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

const String _content = 'first paragraph\n\nsecond paragraph';

Future<void> _pumpMessage(WidgetTester tester, {required bool split}) async {
  final harness = await createBusinessTestHarness(
    initial: {
      'display_chat_message_background_style_v1': 'solid',
      if (split) 'display_assistant_bubble_split_paragraphs_v1': true,
    },
  );
  final settings = SettingsProvider(harness.preferences);
  await settings.loaded;
  final message = ChatMessage(
    role: 'assistant',
    content: _content,
    conversationId: 'conversation-split-paragraphs',
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider(
          create: (_) =>
              TtsProvider(preferences: createBusinessTestPreferences()),
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

/// Bubbles are counted by the key `_buildAssistantTextBlock` puts on each of
/// them, not by selection regions: every bubble of one reply shares a single
/// region so a drag is never cut off at a bubble edge.
int _bubbleCount() {
  return find
      .byWidgetPredicate((widget) {
        const prefix = 'assistant-bubble:';
        final Key? key = widget.key;
        return key is ValueKey<String> && key.value.startsWith(prefix);
      })
      .evaluate()
      .length;
}

void main() {
  testWidgets('option off keeps the whole reply in one bubble', (tester) async {
    await _pumpMessage(tester, split: false);

    expect(_bubbleCount(), 1);
    expect(find.byType(SelectionArea), findsOneWidget);
  });

  testWidgets('option on renders one bubble per paragraph in one region', (
    tester,
  ) async {
    await _pumpMessage(tester, split: true);

    expect(_bubbleCount(), 2);
    expect(find.byType(SelectionArea), findsOneWidget);
  });
}
