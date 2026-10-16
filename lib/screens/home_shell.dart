import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'dashboard_screen.dart';
import 'leads_screen.dart';
import 'more_screen.dart';
import 'properties_screen.dart';
import 'visits_screen.dart';

/// Bottom navigation over the five most-used sections. On a tablet-width
/// window it switches to a [NavigationRail] instead.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index = widget.initialIndex;

  static const _destinations = <_Destination>[
    _Destination('Today', Icons.today_outlined, Icons.today),
    _Destination('Leads', Icons.filter_alt_outlined, Icons.filter_alt),
    _Destination('Properties', Icons.home_work_outlined, Icons.home_work),
    _Destination('Visits', Icons.event_outlined, Icons.event),
    _Destination('More', Icons.grid_view_outlined, Icons.grid_view),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.loadError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 12),
                const Text('Could not open your diary'),
                const SizedBox(height: 8),
                Text(
                  state.loadError!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: state.bootstrap,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final pages = <Widget>[
      const DashboardScreen(embedded: true),
      const LeadsScreen(embedded: true),
      const PropertiesScreen(embedded: true),
      const VisitsScreen(embedded: true),
      const MoreScreen(embedded: true),
    ];
    final body = IndexedStack(index: _index, children: pages);
    final wide = MediaQuery.of(context).size.width >= 840;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
