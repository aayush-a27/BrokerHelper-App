import 'package:broker_demo_app/data/diary_storage.dart';
import 'package:broker_demo_app/models/models.dart';
import 'package:broker_demo_app/screens/lead_form_screen.dart';
import 'package:broker_demo_app/state/app_state.dart';
import 'package:broker_demo_app/state/settings_state.dart';
import 'package:broker_demo_app/widgets/form_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Drives the lead-add form the way a broker would: open it from another
/// screen, fill in the fields, save, and check the record landed in state.
void main() {
  late AppState appState;

  /// A screen with a button that pushes the form, so the form has a real
  /// route to pop back to when it saves.
  Widget harness() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider(
            create: (_) => SettingsState(MemoryDiaryStorage())),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const LeadFormScreen(),
                  ),
                ),
                child: const Text('open form'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openForm(WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.text('open form'));
    await tester.pumpAndSettle();
  }

  setUp(() async {
    appState = AppState(MemoryDiaryStorage(), saveDelay: Duration.zero);
    await appState.bootstrap();
    appState.saveProfile(BrokerProfile(name: 'Test Broker'));
  });

  setUpAll(() {
    // The form is a lazy ListView, so at the default 800x600 test surface the
    // lower fields are never built. A tall surface keeps the whole form in
    // the tree and the tests free of incidental scrolling.
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1000, 2600);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  testWidgets('shows the new-lead form with its key fields', (tester) async {
    await openForm(tester);

    expect(find.text('New lead'), findsOneWidget);
    expect(find.byKey(const Key('lead-form-name')), findsOneWidget);
    expect(find.byKey(const Key('lead-form-phone')), findsOneWidget);
    expect(find.byKey(const Key('lead-form-save')), findsOneWidget);
    // Voice capture is offered on the add form, per report p. 4, 3.3.
    expect(find.byKey(const Key('lead-form-dictate')), findsOneWidget);
  });

  testWidgets('refuses to save without a name and a valid phone number',
      (tester) async {
    await openForm(tester);

    await tester.tap(find.byKey(const Key('lead-form-save')));
    await tester.pumpAndSettle();

    expect(find.text('Name is required'), findsOneWidget);
    expect(find.text('Phone number is required'), findsOneWidget);
    expect(appState.leads, isEmpty);
    // Still on the form.
    expect(find.text('New lead'), findsOneWidget);
  });

  testWidgets('rejects a phone number that is too short', (tester) async {
    await openForm(tester);

    await tester.enterText(
        find.byKey(const Key('lead-form-name')), 'Rohit Agarwal');
    await tester.enterText(find.byKey(const Key('lead-form-phone')), '98210');
    await tester.tap(find.byKey(const Key('lead-form-save')));
    await tester.pumpAndSettle();

    expect(find.text('Enter at least 10 digits'), findsOneWidget);
    expect(appState.leads, isEmpty);
  });

  testWidgets('saves a lead and closes the form', (tester) async {
    await openForm(tester);

    await tester.enterText(
        find.byKey(const Key('lead-form-name')), 'Rohit Agarwal');
    await tester.enterText(
        find.byKey(const Key('lead-form-phone')), '98210 34567');
    await tester.enterText(
        find.byKey(const Key('lead-form-location')), 'Baner');
    await tester.enterText(
        find.byKey(const Key('lead-form-budget-max')), '12000000');

    await tester.tap(find.byKey(const Key('lead-form-save')));
    await tester.pumpAndSettle();

    expect(appState.leads, hasLength(1));
    final lead = appState.leads.first;
    expect(lead.name, 'Rohit Agarwal');
    expect(lead.phone, '98210 34567');
    expect(lead.preferredLocation, 'Baner');
    expect(lead.budgetMax, 12000000);
    expect(lead.status, LeadStatus.newLead);

    // The form popped back to the launcher screen.
    expect(find.text('open form'), findsOneWidget);
    expect(find.text('New lead'), findsNothing);
  });

  testWidgets('creates the matching buyer contact alongside the lead',
      (tester) async {
    await openForm(tester);

    await tester.enterText(
        find.byKey(const Key('lead-form-name')), 'Meera Joshi');
    await tester.enterText(
        find.byKey(const Key('lead-form-phone')), '99304 11228');
    await tester.tap(find.byKey(const Key('lead-form-save')));
    await tester.pumpAndSettle();

    expect(appState.contacts, hasLength(1));
    final contact = appState.contacts.first;
    expect(contact.name, 'Meera Joshi');
    expect(contact.role, ContactRole.buyer);
    expect(appState.leads.first.contactId, contact.id);
  });

  testWidgets('warns about a duplicate phone number before saving',
      (tester) async {
    appState.addLead(
      Lead(id: 'ld-existing', name: 'Rohit A.', phone: '+91 98210 34567'),
      createContact: false,
    );
    await openForm(tester);

    await tester.enterText(
        find.byKey(const Key('lead-form-name')), 'Rohit Agarwal');
    await tester.enterText(
        find.byKey(const Key('lead-form-phone')), '98210 34567');
    await tester.pumpAndSettle();

    expect(find.textContaining('Possible duplicate'), findsOneWidget);
  });

  testWidgets('a saved lead is written to storage', (tester) async {
    await openForm(tester);

    await tester.enterText(
        find.byKey(const Key('lead-form-name')), 'Harish Bhat');
    await tester.enterText(
        find.byKey(const Key('lead-form-phone')), '99225 10073');
    await tester.tap(find.byKey(const Key('lead-form-save')));
    await tester.pumpAndSettle();
    await tester.runAsync(appState.flush);

    final reopened = AppState(appState.storage);
    await tester.runAsync(reopened.bootstrap);
    expect(reopened.leads.single.name, 'Harish Bhat');
  });

  testWidgets('a follow-up date also creates a reminder task',
      (tester) async {
    await openForm(tester);

    await tester.enterText(
        find.byKey(const Key('lead-form-name')), 'Arjun Deshpande');
    await tester.enterText(
        find.byKey(const Key('lead-form-phone')), '97300 88145');

    // Open the date picker, accept today's date, then the time picker.
    await tester.tap(find.byType(DateTimeField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('lead-form-save')));
    await tester.pumpAndSettle();

    expect(appState.leads.first.nextFollowUpAt, isNotNull);
    expect(
      appState.tasks.where((t) =>
          t.relatedKind == EntityKind.lead &&
          t.relatedId == appState.leads.first.id),
      isNotEmpty,
    );
  });
}
