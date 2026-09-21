import "../../../support/business_test_harness.dart";
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/providers/user_provider.dart';
import 'package:Kelivo/desktop/desktop_selection_area.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/snackbar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _harness(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(createBusinessTestPreferences()),
      ),
      ChangeNotifierProvider(
        create: (_) =>
            UserProvider(preferences: createBusinessTestPreferences()),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => AppSnackBarOverlay(child: child!),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSnackBarManager().dismissAll();
  });

  tearDown(() {
    AppSnackBarManager().dismissAll();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop user message has SelectionArea with onSelectionChanged', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    const message = ChatMessage(
      id: 'user-selection-msg',
      role: 'user',
      content: 'Hello selected world',
      conversationId: 'conversation-1',
    );

    await tester.pumpWidget(_harness(const ChatMessageWidget(message: message)));
    await tester.pumpAndSettle();

    final userSelectionArea = find.byKey(
      const ValueKey('user_user-selection-msg'),
    );
    expect(userSelectionArea, findsOneWidget);

    final areaWidget =
        tester.widget<DesktopFloatingSelectionArea>(userSelectionArea);
    expect(areaWidget.onSelectionChanged, isNotNull);
  });
}
