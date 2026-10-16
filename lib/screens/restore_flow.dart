import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/backup_service.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Pick a backup → show what's in it → confirm → restore.
///
/// Shared by the first-run screen ("I have a backup") and Settings.
/// [bytes] skips the picker, for restoring one of the automatic safety
/// copies.
Future<bool> runRestoreFlow(BuildContext context, BackupService backup,
    {Uint8List? bytes}) async {
  Uint8List? data = bytes;
  try {
    data ??= await backup.pickBackup();
  } catch (e) {
    if (context.mounted) showToast(context, 'Could not open the file: $e');
    return false;
  }
  if (data == null || !context.mounted) return false;

  final BackupSummary summary;
  try {
    summary = backup.inspect(data);
  } on BackupException catch (e) {
    await _error(context, e.message);
    return false;
  }
  if (!context.mounted) return false;

  final replacing = !backup.app.isEmpty;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.settings_backup_restore),
      title: const Text('Restore this backup?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (summary.brokerName.isNotEmpty)
            Text('Diary of ${summary.brokerName}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          if (summary.createdAt != null)
            Text('Made ${formatDateTime(summary.createdAt)}'),
          Gap.m,
          Text([
            pluralise(summary.count(Collections.leads), 'lead'),
            pluralise(summary.count(Collections.contacts), 'contact'),
            pluralise(summary.count(Collections.properties), 'property',
                'properties'),
            pluralise(summary.count(Collections.deals), 'deal'),
            pluralise(summary.count(Collections.tasks), 'follow-up'),
            pluralise(summary.attachments, 'file'),
          ].join(' · ')),
          if (replacing) ...[
            Gap.m,
            Text(
              'This replaces everything currently in the diary on this '
              'phone. A safety copy of the current diary is kept first, so '
              'you can switch back from Settings › Safety copies.',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error, height: 1.35),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(replacing ? 'Replace and restore' : 'Restore'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;

  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            SizedBox(
                width: 24, height: 24, child: CircularProgressIndicator()),
            SizedBox(width: 16),
            Expanded(child: Text('Restoring your diary…')),
          ],
        ),
      ),
    ),
  );
  try {
    await backup.restore(data);
    navigator.pop();
    if (context.mounted) {
      showToast(context, 'Diary restored', icon: Icons.check_circle_outline);
    }
    return true;
  } on BackupException catch (e) {
    navigator.pop();
    if (context.mounted) await _error(context, e.message);
    return false;
  } catch (e) {
    navigator.pop();
    if (context.mounted) await _error(context, 'Restore failed: $e');
    return false;
  }
}

Future<void> _error(BuildContext context, String message) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.error_outline),
        title: const Text('Could not restore'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
