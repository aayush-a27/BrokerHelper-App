import 'package:broker_demo_app/data/diary_storage.dart';
import 'package:broker_demo_app/main.dart';
import 'package:broker_demo_app/screens/leads_screen.dart';
import 'package:broker_demo_app/screens/properties_screen.dart';
import 'package:broker_demo_app/services/reminder_service.dart';
import 'package:broker_demo_app/state/app_state.dart';
import 'package:broker_demo_app/state/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_diary.dart';

/// Boots the whole app at phone size and walks every main screen.
///
/// Any RenderFlex overflow, failed assertion or thrown exception during these
/// pumps fails the test, so this is the cheap guard against the layout
/// breaking on a 390x844 handset — the primary target.
void main() {
  const phone = Size(390, 844);

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.physicalSize = phone * 3;
    view.devicePixelRatio = 3.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  late AppState app;
  late NoopReminderScheduler scheduler;

  /// Launches the app on a phone whose diary already has [seed] in it.
  Future<void> launch(WidgetTester tester,
      {bool seeded = true, MemoryDiaryStorage? storage}) async {
    final store = storage ?? MemoryDiaryStorage();
    if (seeded) {
      final seeder = AppState(store, saveDelay: Duration.zero);
      await seeder.bootstrap();
      seedSampleDiary(seeder);
      await seeder.flush();
    }
    final settings = SettingsState(store);
    await settings.load();
    app = AppState(store, saveDelay: Duration.zero);
    scheduler = NoopReminderScheduler();
    await tester.pumpWidget(
        BrokerDiaryRoot(app: app, settings: settings, scheduler: scheduler));
    await tester.pumpAndSettle();
  }

  /// Lets the save and reminder timers run out before the test ends.
  Future<void> settleTimers(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 2));

  testWidgets('first launch asks who the broker is, then opens the diary',
      (tester) async {
    await launch(tester, seeded: false);

    expect(find.text('Broker Diary'), findsOneWidget);
    expect(find.text('Start my diary'), findsOneWidget);
    expect(find.text('I have a backup from another phone'), findsOneWidget);

    // Name is required.
    await tester.tap(find.text('Start my diary'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your name to start'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Aarav Mehta');
    await tester.tap(find.text('Start my diary'));
    await tester.pumpAndSettle();

    expect(app.profile?.name, 'Aarav Mehta');
    expect(find.textContaining('Good'), findsOneWidget);
    expect(find.text('Your diary is empty'), findsOneWidget);
    await settleTimers(tester);
  });

  testWidgets('an existing diary opens straight on Today', (tester) async {
    await launch(tester);

    expect(find.text('Today'), findsWidgets);
    expect(find.textContaining('Good'), findsOneWidget);
    expect(find.text('Due now'), findsOneWidget);
    // Never backed up → the nudge shows.
    expect(find.text('Your diary has never been backed up'), findsOneWidget);
    expect(find.textContaining('DEMO'), findsNothing);
    await settleTimers(tester);
  });

  testWidgets('reminders are planned from the diary', (tester) async {
    await launch(tester);
    await settleTimers(tester);
    final keys = scheduler.lastPlan.map((r) => r.key).toSet();
    expect(keys, contains('task:tk-1'));
    expect(keys, contains('visit:vs-1'));
  });

  testWidgets('every bottom-navigation tab lays out at phone size',
      (tester) async {
    await launch(tester);

    for (final tab in ['Leads', 'Properties', 'Visits', 'More']) {
      await tester.tap(find.widgetWithText(NavigationDestination, tab).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'while opening $tab');
    }
    await settleTimers(tester);
  });

  testWidgets('the quick-add sheet offers all entity types', (tester) async {
    await launch(tester);

    await tester.tap(find.byKey(const Key('quick-add-fab')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('quick-add-lead')), findsOneWidget);
    expect(find.byKey(const Key('quick-add-contact')), findsOneWidget);
    expect(find.byKey(const Key('quick-add-property')), findsOneWidget);
    expect(find.byKey(const Key('quick-add-task')), findsOneWidget);
    expect(find.byKey(const Key('quick-add-visit')), findsOneWidget);
    await settleTimers(tester);
  });

  testWidgets('the More menu opens each remaining section', (tester) async {
    await launch(tester);
    await tester.tap(find.widgetWithText(NavigationDestination, 'More').last);
    await tester.pumpAndSettle();

    for (final section in [
      'Contacts',
      'Deals',
      'Follow-ups',
      'Documents',
      'Reports',
      'Activity log',
      'Recently deleted',
      'Settings and privacy',
    ]) {
      // The lower entries sit under the navigation bar until scrolled up.
      await tester.ensureVisible(find.text(section));
      await tester.pumpAndSettle();
      await tester.tap(find.text(section));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'while opening $section');

      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    await settleTimers(tester);
  });

  testWidgets('settings shows backup, reminders and app lock', (tester) async {
    await launch(tester);
    await tester.tap(find.widgetWithText(NavigationDestination, 'More').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Settings and privacy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings and privacy'));
    await tester.pumpAndSettle();

    expect(find.text('Never backed up'), findsOneWidget);
    expect(find.text('Back up now and send'), findsOneWidget);
    expect(find.text('Restore from a backup'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('App lock'), 300);
    expect(find.text('Follow-up reminders'), findsOneWidget);
    expect(find.text('App lock'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await settleTimers(tester);
  });

  testWidgets('a lead opens its detail screen and the match list',
      (tester) async {
    await launch(tester);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Leads').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(LeadCard, 'Rohit Agarwal'));
    await tester.pumpAndSettle();
    expect(find.text('Requirement'), findsOneWidget);

    await tester.tap(find.text('Match properties'));
    await tester.pumpAndSettle();
    expect(find.text('Matching properties'), findsOneWidget);
    expect(find.text('Budget'), findsWidgets);
    await settleTimers(tester);
  });

  testWidgets('deleting a lead can be undone', (tester) async {
    await launch(tester);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Leads').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(LeadCard, 'Priya Sharma'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete lead').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(app.lead('ld-2'), isNull);
    expect(app.trash, hasLength(1));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(app.lead('ld-2'), isNotNull);
    expect(app.trash, isEmpty);
    await settleTimers(tester);
  });

  testWidgets('a property detail screen lays out with its photo header',
      (tester) async {
    await launch(tester);
    await tester
        .tap(find.widgetWithText(NavigationDestination, 'Properties').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PropertyCard).first);
    await tester.pumpAndSettle();

    expect(find.text('Details'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await settleTimers(tester);
  });

  testWidgets('global search spans leads, contacts and properties',
      (tester) async {
    await launch(tester);

    await tester.tap(find.byIcon(Icons.search).first);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Baner');
    await tester.pumpAndSettle();

    expect(find.textContaining('result'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await settleTimers(tester);
  });

  testWidgets('with a PIN set, the diary opens locked', (tester) async {
    final store = MemoryDiaryStorage();
    final settings = SettingsState(store);
    await settings.load();
    await settings.setPin('2468');
    await launch(tester, storage: store);

    expect(find.text('Enter your PIN'), findsOneWidget);
    for (final d in ['1', '1', '1', '1']) {
      await tester.tap(find.widgetWithText(OutlinedButton, d));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Wrong PIN'), findsOneWidget);

    for (final d in ['2', '4', '6', '8']) {
      await tester.tap(find.widgetWithText(OutlinedButton, d));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Enter your PIN'), findsNothing);
    expect(find.text('Due now'), findsOneWidget);
    await settleTimers(tester);
  });
}
