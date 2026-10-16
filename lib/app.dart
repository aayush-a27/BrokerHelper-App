import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/activity_log_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/deals_screen.dart';
import 'screens/documents_screen.dart';
import 'screens/home_shell.dart';
import 'screens/leads_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/more_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/properties_screen.dart';
import 'screens/recently_deleted_screen.dart';
import 'screens/reminder_help_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tasks_screen.dart';
import 'screens/visits_screen.dart';
import 'screens/welcome_screen.dart';
import 'state/app_state.dart';
import 'state/lock_state.dart';
import 'state/settings_state.dart';
import 'theme.dart';

/// Named routes for the main sections. Detail and form screens are pushed
/// with their record as a constructor argument rather than through the
/// route table, so they stay type-safe.
class Routes {
  const Routes._();

  static const dashboard = '/dashboard';
  static const leads = '/leads';
  static const contacts = '/contacts';
  static const properties = '/properties';
  static const visits = '/visits';
  static const tasks = '/tasks';
  static const deals = '/deals';
  static const documents = '/documents';
  static const search = '/search';
  static const activity = '/activity';
  static const reports = '/reports';
  static const settings = '/settings';
  static const profile = '/profile';
  static const more = '/more';
  static const recentlyDeleted = '/recently-deleted';
  static const reminderHelp = '/reminder-help';
}

class BrokerDiaryApp extends StatelessWidget {
  const BrokerDiaryApp({super.key, this.navigatorKey});

  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    final darkMode = context.select<SettingsState, bool>((s) => s.darkMode);
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Broker Diary',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      home: const _Home(),
      routes: {
        Routes.dashboard: (_) => const DashboardScreen(),
        Routes.leads: (_) => const LeadsScreen(),
        Routes.contacts: (_) => const ContactsScreen(),
        Routes.properties: (_) => const PropertiesScreen(),
        Routes.visits: (_) => const VisitsScreen(),
        Routes.tasks: (_) => const TasksScreen(),
        Routes.deals: (_) => const DealsScreen(),
        Routes.documents: (_) => const DocumentsScreen(),
        Routes.search: (_) => const SearchScreen(),
        Routes.activity: (_) => const ActivityLogScreen(),
        Routes.reports: (_) => const ReportsScreen(),
        Routes.settings: (_) => const SettingsScreen(),
        Routes.profile: (_) => const ProfileScreen(),
        Routes.more: (_) => const MoreScreen(),
        Routes.recentlyDeleted: (_) => const RecentlyDeletedScreen(),
        Routes.reminderHelp: (_) => const ReminderHelpScreen(),
      },
      builder: (context, child) {
        // Cap the text scale so the dense list rows stay readable.
        final media = MediaQuery.of(context);
        final locked = context.select<AppLock, bool>((l) => l.locked);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(maxScaleFactor: 1.4),
          ),
          child: Stack(
            children: [
              // Hidden from screen readers and taps while locked.
              ExcludeSemantics(
                excluding: locked,
                child: AbsorbPointer(
                  absorbing: locked,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
              // Above the navigator, so it needs its own overlay for
              // tooltips and the like.
              if (locked)
                Positioned.fill(
                  child: Overlay(initialEntries: [
                    OverlayEntry(builder: (_) => const LockScreen()),
                  ]),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Loading → first-run setup → the diary.
class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (state.loadError != null) return _LoadError(error: state.loadError!);
    if (!state.isSetUp) return const WelcomeScreen();
    return const HomeShell();
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              const Text('Could not open your diary',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(error,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: context.read<AppState>().bootstrap,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Convenience accessors used all over the screens.
extension AppStateContext on BuildContext {
  AppState get app => read<AppState>();
  AppState get watchApp => watch<AppState>();
  SettingsState get settings => read<SettingsState>();
}
