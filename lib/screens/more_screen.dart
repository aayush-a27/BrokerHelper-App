import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/common.dart';

/// The rest of the navigation — Contacts, Deals, Documents, Reports,
/// Activity and Settings.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.profile;

    final entries = <_Entry>[
      _Entry(
        icon: Icons.contacts_outlined,
        title: 'Contacts',
        subtitle: '${state.contacts.length} buyers and sellers',
        route: Routes.contacts,
      ),
      _Entry(
        icon: Icons.handshake_outlined,
        title: 'Deals',
        subtitle: '${state.openDeals.length} open · '
            '${formatMoney(state.totalPendingCommission)} pending',
        route: Routes.deals,
      ),
      _Entry(
        icon: Icons.task_alt,
        title: 'Follow-ups',
        subtitle: '${state.todaysTasks.length} due today · '
            '${state.overdueTasks.length} overdue',
        route: Routes.tasks,
      ),
      _Entry(
        icon: Icons.folder_outlined,
        title: 'Documents',
        subtitle: '${state.documents.length} files · '
            '${state.missingDocuments.length} missing',
        route: Routes.documents,
      ),
      _Entry(
        icon: Icons.bar_chart_outlined,
        title: 'Reports',
        subtitle: 'Business summary and success measures',
        route: Routes.reports,
      ),
      _Entry(
        icon: Icons.history,
        title: 'Activity log',
        subtitle: '${state.activities.length} recorded changes',
        route: Routes.activity,
      ),
      _Entry(
        icon: Icons.search,
        title: 'Search',
        subtitle: 'Leads, contacts and properties together',
        route: Routes.search,
      ),
      _Entry(
        icon: Icons.delete_outline,
        title: 'Recently deleted',
        subtitle: state.trash.isEmpty
            ? 'Nothing deleted'
            : '${state.trash.length} kept for 30 days',
        route: Routes.recentlyDeleted,
      ),
      _Entry(
        icon: Icons.settings_outlined,
        title: 'Settings and privacy',
        subtitle: 'Backup, reminders, app lock',
        route: Routes.settings,
      ),
    ];

    return MainScaffold(
      title: 'More',
      embedded: embedded,
      showSearch: false,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Card(
                child: ListTile(
                  leading: CircleAvatar(radius: 24, child: Text(user.initials)),
                  title: Text(user.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(user.agency.isEmpty ? 'My profile' : user.agency),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, Routes.profile),
                ),
              ),
            ),
          const SectionHeader('Sections'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Card(
              child: Column(
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    ListTile(
                      leading: Icon(entries[i].icon),
                      title: Text(entries[i].title,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(entries[i].subtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          Navigator.pushNamed(context, entries[i].route),
                    ),
                    if (i < entries.length - 1)
                      const Divider(height: 1, indent: 56),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Entry {
  const _Entry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
}
