import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/reminder_service.dart';
import '../services/system_settings.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';

/// "Reminders not arriving?" — checks what the app can check, and explains
/// what only the broker can change.
///
/// Many Android phones sold in India (Xiaomi, Oppo, Vivo, Realme, OnePlus,
/// Samsung) stop background alarms to save battery. No code can override
/// that; the phone has to be told to leave this app alone.
class ReminderHelpScreen extends StatefulWidget {
  const ReminderHelpScreen({super.key});

  @override
  State<ReminderHelpScreen> createState() => _ReminderHelpScreenState();
}

class _ReminderHelpScreenState extends State<ReminderHelpScreen>
    with WidgetsBindingObserver {
  ReminderStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from the system settings screen: re-check.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await context.read<ReminderScheduler>().status();
    if (mounted) setState(() => _status = s);
  }

  @override
  Widget build(BuildContext context) {
    final scheduler = context.read<ReminderScheduler>();
    final status = _status;
    final scheme = Theme.of(context).colorScheme;

    Widget check({
      required bool ok,
      required String title,
      required String okText,
      required String badText,
      required String fixLabel,
      required VoidCallback onFix,
    }) =>
        ListTile(
          leading: Icon(ok ? Icons.check_circle : Icons.error,
              color: ok ? const Color(0xFF059669) : scheme.error),
          title: Text(title),
          subtitle: Text(ok ? okText : badText),
          trailing: ok
              ? null
              : FilledButton.tonal(onPressed: onFix, child: Text(fixLabel)),
        );

    return MainScaffold(
      title: 'Reminders not arriving?',
      showQuickAdd: false,
      showSearch: false,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const SectionHeader('Checks'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: status == null
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : Column(
                      children: [
                        check(
                          ok: status.notificationsAllowed,
                          title: 'Notifications',
                          okText: 'Allowed',
                          badText: 'Turned off for Broker Diary',
                          fixLabel: 'Allow',
                          onFix: () async {
                            final granted = await scheduler.requestPermission();
                            if (!granted) await SystemSettings.openAppSettings();
                            await _refresh();
                          },
                        ),
                        const Divider(height: 1),
                        check(
                          ok: status.exactAlarmsAllowed,
                          title: 'Alarms & reminders',
                          okText: 'Reminders fire on the minute',
                          badText: 'Off — reminders may come up to 15 '
                              'minutes late',
                          fixLabel: 'Allow',
                          onFix: () async {
                            await scheduler.requestExactAlarms();
                            await _refresh();
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.schedule),
                          title: const Text('Reminders waiting'),
                          subtitle: Text(
                              '${status.pendingCount} scheduled on this phone '
                              '(the next 30 days)'),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.notifications_active_outlined),
                          title: const Text('Send a test reminder'),
                          subtitle: const Text('Shows one straight away'),
                          onTap: () async {
                            await scheduler.showTest();
                            if (context.mounted) {
                              showToast(context, 'Test reminder sent');
                            }
                          },
                        ),
                      ],
                    ),
            ),
          ),
          const SectionHeader(
            'Stop the phone from blocking reminders',
            subtitle: 'Do this once. Menu names vary a little by model.',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('Open this app\'s settings'),
                    subtitle: const Text(
                        'Most of the steps below start from here'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: SystemSettings.openAppSettings,
                  ),
                  for (final tip in _tips) ...[
                    const Divider(height: 1),
                    ExpansionTile(
                      leading: const Icon(Icons.phone_android),
                      title: Text(tip.brand),
                      childrenPadding:
                          const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < tip.steps.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text('${i + 1}. ${tip.steps[i]}',
                                style: const TextStyle(height: 1.35)),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _tips = <_Tip>[
    _Tip('Xiaomi / Redmi / POCO', [
      'Settings › Apps › Manage apps › Broker Diary.',
      'Turn on Autostart.',
      'Battery saver › No restrictions.',
      'Open recent apps, long-press Broker Diary and tap the lock icon.',
    ]),
    _Tip('Oppo / Realme', [
      'Settings › Apps › App management › Broker Diary.',
      'Allow Auto launch (or "Allow background activity").',
      'Battery usage › Allow background activity.',
      'In recent apps, pull Broker Diary down to lock it.',
    ]),
    _Tip('Vivo / iQOO', [
      'Settings › Battery › Background power consumption management › '
          'Broker Diary › Allow.',
      'Settings › Apps › Autostart › turn on Broker Diary.',
    ]),
    _Tip('OnePlus', [
      'Settings › Apps › Broker Diary › Battery › Don\'t optimise '
          '(or "Unrestricted").',
      'In recent apps, tap the menu on Broker Diary and choose Lock.',
    ]),
    _Tip('Samsung', [
      'Settings › Apps › Broker Diary › Battery › Unrestricted.',
      'Settings › Battery › Background usage limits: make sure Broker Diary '
          'is not under "Sleeping" or "Deep sleeping" apps.',
    ]),
    _Tip('Other phones', [
      'Settings › Apps › Broker Diary › Battery: choose Unrestricted or '
          '"Don\'t optimise".',
      'Make sure Notifications are on for Broker Diary.',
      'Don\'t swipe the app away with a "clean all" booster app.',
    ]),
  ];
}

class _Tip {
  const _Tip(this.brand, this.steps);
  final String brand;
  final List<String> steps;
}
