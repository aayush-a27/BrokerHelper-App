import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../services/backup_service.dart';
import '../services/export_service.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../theme.dart';
import 'common.dart';
import 'quick_add.dart';

/// Shared chrome for the main sections: title, search, export, the
/// save-error banner and the quick-add FAB.
///
/// [embedded] is true when the screen sits inside [HomeShell]'s tab stack —
/// it drops the back button and lets the shell own the bottom navigation.
class MainScaffold extends StatelessWidget {
  const MainScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.embedded = false,
    this.actions = const <Widget>[],
    this.exportBuilder,
    this.showSearch = true,
    this.showQuickAdd = true,
    this.bottom,
    this.floatingActionButton,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final bool embedded;
  final List<Widget> actions;

  /// Supplies the rows to export. Built lazily so the export always reflects
  /// the filters currently applied on screen.
  final ExportDataset Function()? exportBuilder;
  final bool showSearch;
  final bool showQuickAdd;
  final PreferredSizeWidget? bottom;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !embedded,
        title: subtitle == null
            ? Text(title)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
        actions: [
          ...actions,
          if (showSearch)
            IconButton(
              tooltip: 'Search everything',
              icon: const Icon(Icons.search),
              onPressed: () => Navigator.pushNamed(context, Routes.search),
            ),
          if (exportBuilder != null) ExportButton(builder: exportBuilder!),
        ],
        bottom: bottom,
      ),
      body: Column(
        children: [
          const SaveErrorBanner(),
          Expanded(child: body),
        ],
      ),
      floatingActionButton: floatingActionButton ??
          (showQuickAdd ? const QuickAddFab() : null),
    );
  }
}

/// Export menu shown in the app bar of every list screen.
class ExportButton extends StatelessWidget {
  const ExportButton({super.key, required this.builder});

  final ExportDataset Function() builder;

  Future<void> _run(BuildContext context, bool pdf) async {
    final data = builder();
    if (data.isEmpty) {
      showToast(context, 'Nothing to export with the current filters',
          icon: Icons.info_outline);
      return;
    }
    const service = ExportService();
    showToast(context, 'Generating ${pdf ? 'PDF' : 'CSV'}…',
        icon: Icons.file_download_outlined);
    final outcome =
        pdf ? await service.sharePdf(data) : await service.shareCsv(data);
    if (!context.mounted) return;
    showToast(
      context,
      outcome.message,
      icon: outcome.status == ExportStatus.failed
          ? Icons.error_outline
          : Icons.check_circle_outline,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Export',
      icon: const Icon(Icons.ios_share),
      onSelected: (value) => _run(context, value == 'pdf'),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'csv',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.table_chart_outlined),
            title: Text('Export CSV'),
          ),
        ),
        PopupMenuItem(
          value: 'pdf',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.picture_as_pdf_outlined),
            title: Text('Export PDF'),
          ),
        ),
      ],
    );
  }
}

/// Shown if writing to the phone failed (usually: storage full). The change
/// is still on screen and is retried on the next save.
class SaveErrorBanner extends StatelessWidget {
  const SaveErrorBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final error = context.select<AppState, String?>((s) => s.saveError);
    if (error == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Icon(Icons.sd_card_alert_outlined,
                size: 16, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Couldn't save to the phone — is storage full? "
                'Your last change will be saved when there is space.',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: () => context.read<AppState>().flush(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A weekly nudge on the Today screen. With no server, a backup file is the
/// only copy of the diary that survives losing the phone.
class BackupNudgeBanner extends StatelessWidget {
  const BackupNudgeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final hasData = context.select<AppState, bool>((s) => !s.isEmpty);
    if (!settings.backupDue(hasData: hasData)) return const SizedBox.shrink();
    final last = settings.lastBackupAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        color: AppTheme.accent.withValues(alpha: 0.10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.backup_outlined, color: AppTheme.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      last == null
                          ? 'Your diary has never been backed up'
                          : 'Last backup was ${DateTime.now().difference(last).inDays} days ago',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.only(left: 34, right: 8),
                child: Text(
                  'Everything is on this phone only. Send a backup to '
                  "yourself on WhatsApp or Drive so a lost phone doesn't "
                  'mean a lost diary.',
                  style: TextStyle(fontSize: 12.5, height: 1.35),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: settings.snoozeBackupNudge,
                    child: const Text('Later'),
                  ),
                  FilledButton.tonal(
                    onPressed: () async {
                      final outcome =
                          await context.read<BackupService>().share();
                      if (context.mounted) {
                        showToast(context, outcome.message);
                      }
                    },
                    child: const Text('Back up now'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
