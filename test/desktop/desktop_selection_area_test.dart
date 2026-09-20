import 'package:Kelivo/desktop/desktop_selection_area.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _testHarness({
  required Widget child,
  ValueChanged<SelectedContent?>? onSelectionChanged,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: DesktopFloatingSelectionArea(
        onSelectionChanged: onSelectionChanged,
        child: child,
      ),
    ),
  );
}

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop selection area delegates to SelectionArea on mobile', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    String? selected;

    await tester.pumpWidget(
      _testHarness(
        child: const Text('Mobile selectable text'),
        onSelectionChanged: (content) => selected = content?.plainText,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsOneWidget);

    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    region.selectAll(SelectionChangedCause.keyboard);
    await tester.pumpAndSettle();

    expect(selected, 'Mobile selectable text');
  });

  testWidgets('desktop selection area supports text selection on Windows', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    String? selected;

    await tester.pumpWidget(
      _testHarness(
        child: const Text('Windows desktop text to copy'),
        onSelectionChanged: (content) => selected = content?.plainText,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsOneWidget);

    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    region.selectAll(SelectionChangedCause.keyboard);
    await tester.pumpAndSettle();

    expect(selected, 'Windows desktop text to copy');
  });
}
