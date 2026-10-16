import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../services/backup_service.dart';
import '../services/reminder_service.dart';
import '../state/app_state.dart';
import '../state/lock_state.dart';
import '../state/settings_state.dart';
import '../utils/formatters.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';
import 'restore_flow.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = context.watch<SettingsState>();
    final profile = state.profile;

    Widget card(List<Widget> children) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Card(child: Column(children: children)),
        );
    const divider = Divider(height: 1, indent: 56);

    return MainScaffold(
      title: 'Settings',
      embedded: embedded,
      showQuickAdd: false,
      showSearch: false,
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 40),
        children: [
          if (profile != null)
            card([
              ListTile(
                leading: CircleAvatar(child: Text(profile.initials)),
                title: Text(profile.name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([profile.agency, profile.phone]
                    .where((e) => e.isNotEmpty)
                    .join(' · ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pushNamed(context, Routes.profile),
              ),
            ]),

          // --- backup ----------------------------------------------------
          const SectionHeader('Backup',
              subtitle: 'Your diary lives only on this phone'),
          const _BackupCard(),

          // --- reminders -------------------------------------------------
          const SectionHeader('Reminders'),
          card([
            SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('Follow-up reminders'),
              subtitle: const Text('Calls, site visits, payments due'),
              value: settings.remindersEnabled,
              onChanged: (v) async {
                if (v) {
                  await context.read<ReminderScheduler>().requestPermission();
                }
                await settings.setRemindersEnabled(v);
              },
            ),
            divider,
            SwitchListTile(
              secondary: const Icon(Icons.wb_sunny_outlined),
              title: const Text('Morning summary'),
              subtitle: Text(settings.digestEnabled
                  ? 'Every day at ${settings.digestTime.format(context)}'
                  : 'Off'),
              value: settings.digestEnabled && settings.remindersEnabled,
              onChanged: settings.remindersEnabled
                  ? settings.setDigestEnabled
                  : null,
            ),
            if (settings.digestEnabled && settings.remindersEnabled) ...[
              divider,
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Summary time'),
                trailing: Text(settings.digestTime.format(context)),
                onTap: () async {
                  final t = await showTimePicker(
                      context: context, initialTime: settings.digestTime);
                  if (t != null) await settings.setDigestTime(t);
                },
              ),
            ],
            divider,
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('Remind me before a site visit'),
              trailing: DropdownButton<int>(
                value: settings.visitLeadMinutes,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 15, child: Text('15 min')),
                  DropdownMenuItem(value: 30, child: Text('30 min')),
                  DropdownMenuItem(value: 60, child: Text('1 hour')),
                  DropdownMenuItem(value: 120, child: Text('2 hours')),
                ],
                onChanged: settings.remindersEnabled
                    ? (v) => settings.setVisitLeadMinutes(v ?? 60)
                    : null,
              ),
            ),
            divider,
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Reminders not arriving?'),
              subtitle: const Text('Check permissions and battery settings'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, Routes.reminderHelp),
            ),
          ]),

          // --- security --------------------------------------------------
          const SectionHeader('Privacy',
              subtitle: 'Keep the diary private if someone picks up the phone'),
          const _LockCard(),

          // --- data ------------------------------------------------------
          const SectionHeader('Your data'),
          card([
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Export to Excel / PDF'),
              subtitle: const Text('From any list, or the Reports screen'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, Routes.reports),
            ),
            divider,
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Recently deleted'),
              subtitle: Text(state.trash.isEmpty
                  ? 'Empty'
                  : pluralise(state.trash.length, 'item')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Navigator.pushNamed(context, Routes.recentlyDeleted),
            ),
            divider,
            const _StorageTile(),
            divider,
            ListTile(
              leading: Icon(Icons.delete_forever_outlined,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Erase all data',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
              subtitle: const Text('Removes the diary from this phone'),
              onTap: () => _eraseAll(context),
            ),
          ]),

          // --- appearance ------------------------------------------------
          const SectionHeader('Appearance'),
          card([
            SwitchListTile(
              secondary: const Icon(Icons.dark_mode_outlined),
              title: const Text('Dark theme'),
              value: settings.darkMode,
              onChanged: settings.setDarkMode,
            ),
          ]),

          const SectionHeader('About'),
          card([
            const ListTile(
              leading: Icon(Icons.menu_book_rounded),
              title: Text('Broker Diary'),
              subtitle: Text(
                'Everything is stored on this phone. The app has no '
                'internet permission and no account — nothing is uploaded '
                'anywhere unless you share it yourself.',
              ),
              isThreeLine: true,
            ),
          ]),
        ],
      ),
    );
  }

  static Future<void> _eraseAll(BuildContext context) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: const Text('Erase the whole diary?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Every lead, contact, property, deal, photo and document on '
                'this phone will be deleted. Take a backup first if you may '
                'want any of it back.\n\nType ERASE to confirm.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: controller.text.trim().toUpperCase() == 'ERASE'
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Erase'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (ok != true || !context.mounted) return;
    final app = context.read<AppState>();
    final settings = context.read<SettingsState>();
    final scheduler = context.read<ReminderScheduler>();
    final lock = context.read<AppLock>();
    final navigator = Navigator.of(context);
    await scheduler.cancelAll();
    await app.eraseAllData();
    await settings.reset();
    lock.reset();
    navigator.popUntil((r) => r.isFirst);
  }
}

class _BackupCard extends StatefulWidget {
  const _BackupCard();

  @override
  State<_BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<_BackupCard> {
  bool _busy = false;

  Future<void> _run(Future<BackupOutcome> Function() task) async {
    setState(() => _busy = true);
    final outcome = await task();
    if (!mounted) return;
    setState(() => _busy = false);
    showToast(context, outcome.message,
        icon: outcome.ok ? Icons.check_circle_outline : Icons.info_outline);
  }

  @override
  Widget build(BuildContext context) {
    final backup = context.read<BackupService>();
    final settings = context.watch<SettingsState>();
    final last = settings.lastBackupAt;
    final due = settings.backupDue(hasData: !context.watch<AppState>().isEmpty);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        child: Column(
          children: [
            ListTile(
              leading: Icon(
                due ? Icons.warning_amber_rounded : Icons.verified_outlined,
                color: due ? scheme.error : const Color(0xFF059669),
              ),
              title: Text(last == null
                  ? 'Never backed up'
                  : 'Last backup ${formatRelativeDay(last).toLowerCase()}'),
              subtitle: const Text(
                'If this phone is lost or the app is uninstalled, a backup '
                'file is the only way to get the diary back.',
              ),
              isThreeLine: true,
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.send_outlined),
              title: const Text('Back up now and send'),
              subtitle: const Text('To WhatsApp, Google Drive, email…'),
              enabled: !_busy,
              onTap: () => _run(backup.share),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Save backup to phone'),
              subtitle: const Text('Choose a folder, e.g. Downloads'),
              enabled: !_busy,
              onTap: () => _run(backup.saveToPhone),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: const Text('Restore from a backup'),
              enabled: !_busy,
              onTap: () => runRestoreFlow(context, backup),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Safety copies'),
              subtitle: const Text('Saved automatically before each restore'),
              enabled: !_busy,
              onTap: () => _showSafetyCopies(context, backup),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSafetyCopies(
      BuildContext context, BackupService backup) async {
    final copies = await backup.safetyCopies();
    if (!context.mounted) return;
    final chosen = await showModalBottomSheet<File>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: copies.isEmpty
            ? const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Text('No safety copies yet. One is made '
                    'automatically whenever you restore a backup.'),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final f in copies)
                    ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(formatDateTime(f.lastModifiedSync())),
                      subtitle: Text(
                          '${(f.lengthSync() / 1024).ceil()} KB · tap to restore'),
                      onTap: () => Navigator.pop(context, f),
                    ),
                ],
              ),
      ),
    );
    if (chosen == null) return;
    final bytes = await chosen.readAsBytes();
    if (!context.mounted) return;
    await runRestoreFlow(context, backup, bytes: bytes);
  }
}

class _LockCard extends StatefulWidget {
  const _LockCard();

  @override
  State<_LockCard> createState() => _LockCardState();
}

class _LockCardState extends State<_LockCard> {
  bool _canBiometric = false;

  @override
  void initState() {
    super.initState();
    context.read<AppLock>().canUseBiometrics().then((v) {
      if (mounted) setState(() => _canBiometric = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final lock = context.read<AppLock>();
    const divider = Divider(height: 1, indent: 56);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        child: Column(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.lock_outline),
              title: const Text('App lock'),
              subtitle: Text(settings.lockEnabled
                  ? 'PIN needed to open the diary'
                  : 'Off'),
              value: settings.lockEnabled,
              onChanged: (v) async {
                if (v) {
                  final pin = await _askNewPin(context);
                  if (pin != null) {
                    await settings.setPin(pin);
                    if (context.mounted) {
                      showToast(context, 'App lock on',
                          icon: Icons.lock_outline);
                    }
                  }
                } else {
                  await settings.clearPin();
                  lock.reset();
                }
              },
            ),
            if (settings.lockEnabled) ...[
              divider,
              ListTile(
                leading: const Icon(Icons.password),
                title: const Text('Change PIN'),
                onTap: () async {
                  final pin = await _askNewPin(context);
                  if (pin != null) {
                    await settings.setPin(pin);
                    if (context.mounted) showToast(context, 'PIN changed');
                  }
                },
              ),
              if (_canBiometric) ...[
                divider,
                SwitchListTile(
                  secondary: const Icon(Icons.fingerprint),
                  title: const Text('Unlock with fingerprint'),
                  value: settings.biometricEnabled,
                  onChanged: (v) async {
                    if (v && !await lock.confirmBiometrics()) return;
                    await settings.setBiometricEnabled(v);
                  },
                ),
              ],
              divider,
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Lock again after'),
                trailing: DropdownButton<int>(
                  value: settings.lockAfterSeconds,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 30, child: Text('30 seconds')),
                    DropdownMenuItem(value: 60, child: Text('1 minute')),
                    DropdownMenuItem(value: 300, child: Text('5 minutes')),
                    DropdownMenuItem(value: 900, child: Text('15 minutes')),
                  ],
                  onChanged: (v) => settings.setLockAfterSeconds(v ?? 60),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'If you forget the PIN, the only way back in is to erase '
                  'the diary and restore a backup — keep your backups '
                  'current.',
                  style: TextStyle(fontSize: 12, height: 1.35),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Enter a 4–6 digit PIN twice. Returns null if cancelled.
  static Future<String?> _askNewPin(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (context) => const _NewPinDialog(),
    );
  }
}

class _NewPinDialog extends StatefulWidget {
  const _NewPinDialog();

  @override
  State<_NewPinDialog> createState() => _NewPinDialogState();
}

class _NewPinDialogState extends State<_NewPinDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _submit() {
    final a = _first.text, b = _second.text;
    if (a.length < 4) {
      setState(() => _error = 'Use 4 to 6 digits');
    } else if (a != b) {
      setState(() => _error = 'The two PINs don\'t match');
    } else {
      Navigator.pop(context, a);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label) =>
        InputDecoration(labelText: label, counterText: '');
    final formatters = [FilteringTextInputFormatter.digitsOnly];
    return AlertDialog(
      title: const Text('Set a PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _first,
            autofocus: true,
            obscureText: true,
            maxLength: 6,
            keyboardType: TextInputType.number,
            inputFormatters: formatters,
            decoration: deco('New PIN (4–6 digits)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _second,
            obscureText: true,
            maxLength: 6,
            keyboardType: TextInputType.number,
            inputFormatters: formatters,
            decoration: deco('Enter it again'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save PIN')),
      ],
    );
  }
}

/// How much room the diary takes on the phone.
class _StorageTile extends StatefulWidget {
  const _StorageTile();

  @override
  State<_StorageTile> createState() => _StorageTileState();
}

class _StorageTileState extends State<_StorageTile> {
  String? _size;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final dir = context.read<AppState>().storage.dataDir;
    if (dir == null || !await dir.exists()) {
      if (mounted) setState(() => _size = '—');
      return;
    }
    var bytes = 0;
    await for (final e in dir.list(recursive: true)) {
      if (e is File) bytes += await e.length();
    }
    if (mounted) setState(() => _size = formatBytes(bytes));
  }

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(Icons.sd_storage_outlined),
        title: const Text('Space used on phone'),
        trailing: Text(_size ?? '…'),
      );
}
