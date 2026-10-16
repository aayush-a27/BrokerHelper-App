import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/diary_storage.dart';
import 'services/attachment_service.dart';
import 'services/backup_service.dart';
import 'services/reminder_coordinator.dart';
import 'services/reminder_service.dart';
import 'state/app_state.dart';
import 'state/lock_state.dart';
import 'state/settings_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final DiaryStorage storage;
  try {
    storage = await FileDiaryStorage.open();
  } catch (e) {
    // Without storage nothing could be saved; say so rather than run a
    // diary that silently forgets.
    runApp(StorageErrorApp(error: e.toString()));
    return;
  }

  AttachmentService.instance.dir = storage.attachmentsDir;
  final settings = SettingsState(storage);
  await settings.load();

  runApp(BrokerDiaryRoot(
    app: AppState(storage),
    settings: settings,
    scheduler: LocalReminderScheduler.instance,
  ));
}

/// Owns the long-lived objects and ties them to the app lifecycle.
/// Tests build this directly with a [MemoryDiaryStorage] and a
/// [NoopReminderScheduler].
class BrokerDiaryRoot extends StatefulWidget {
  const BrokerDiaryRoot({
    super.key,
    required this.app,
    required this.settings,
    required this.scheduler,
  });

  final AppState app;
  final SettingsState settings;
  final ReminderScheduler scheduler;

  @override
  State<BrokerDiaryRoot> createState() => _BrokerDiaryRootState();
}

class _BrokerDiaryRootState extends State<BrokerDiaryRoot> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final AppLock _lock = AppLock(widget.settings);
  late final BackupService _backup = BackupService(widget.app, widget.settings);
  late final ReminderCoordinator _reminders = ReminderCoordinator(
    app: widget.app,
    settings: widget.settings,
    scheduler: widget.scheduler,
    navigatorKey: _navigatorKey,
  );
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    unawaited(widget.app.bootstrap());
    unawaited(_reminders.start());
    _lifecycle = AppLifecycleListener(
      // Save the moment the app leaves the screen: Android may kill a
      // background app without warning.
      onInactive: () => unawaited(widget.app.flush()),
      onHide: () {
        unawaited(widget.app.flush());
        _lock.onBackgrounded();
      },
      onDetach: () => unawaited(widget.app.flush()),
      onShow: _lock.onForegrounded,
      onResume: () => unawaited(_reminders.onDiaryReady()),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _reminders.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.app),
        ChangeNotifierProvider.value(value: widget.settings),
        ChangeNotifierProvider.value(value: _lock),
        Provider<ReminderScheduler>.value(value: widget.scheduler),
        Provider<BackupService>.value(value: _backup),
      ],
      child: BrokerDiaryApp(navigatorKey: _navigatorKey),
    );
  }
}

class StorageErrorApp extends StatelessWidget {
  const StorageErrorApp({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.sd_card_alert_outlined, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Broker Diary can\'t open its storage',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Free up some space on the phone, then close and reopen '
                  'the app. Your existing diary has not been changed.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
