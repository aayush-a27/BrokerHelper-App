import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/models.dart';
import '../screens/deal_detail_screen.dart';
import '../screens/lead_detail_screen.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import 'reminder_planner.dart';
import 'reminder_service.dart';

/// Keeps the phone's scheduled notifications in step with the diary.
///
/// Any change to the diary or the reminder settings triggers a re-plan a
/// moment later (batched, so typing in a form doesn't thrash the alarm
/// manager). Opening the app does too, which rolls the 30-day window forward
/// and refreshes the morning-summary counts.
class ReminderCoordinator {
  ReminderCoordinator({
    required this.app,
    required this.settings,
    required this.scheduler,
    required this.navigatorKey,
    this.planner = const ReminderPlanner(),
    this.debounce = const Duration(seconds: 1),
  });

  final AppState app;
  final SettingsState settings;
  final ReminderScheduler scheduler;
  final GlobalKey<NavigatorState> navigatorKey;
  final ReminderPlanner planner;
  final Duration debounce;

  final _subs = <StreamSubscription<Object?>>[];
  Timer? _timer;
  int _lastRevision = -1;
  ReminderTap? _pendingTap;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await scheduler.init();
    } catch (e) {
      debugPrint('Reminders unavailable: $e');
    }
    _subs
      ..add(scheduler.actions.listen(_apply))
      ..add(scheduler.taps.listen(_open));
    app.addListener(_onAppChanged);
    settings.addListener(_schedule);
    _pendingTap = await scheduler.launchTap();
    if (!app.isLoading) await onDiaryReady();
  }

  void _onAppChanged() {
    if (app.isLoading) return;
    if (!_readyHandled) {
      unawaited(onDiaryReady());
      return;
    }
    if (app.revision == _lastRevision) return;
    _lastRevision = app.revision;
    _schedule();
  }

  bool _readyHandled = false;

  /// Called once the diary has loaded, and whenever the app comes back to
  /// the foreground.
  Future<void> onDiaryReady() async {
    if (app.isLoading) return;
    _readyHandled = true;
    _lastRevision = app.revision;
    for (final action in await scheduler.takeQueuedActions()) {
      app.applyReminderAction(action);
    }
    _schedule(immediate: true);
    final tap = _pendingTap;
    if (tap != null) {
      _pendingTap = null;
      // Let the first frame (and any lock screen) settle before navigating.
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(tap));
    }
  }

  void _apply(ReminderAction action) {
    if (app.isLoading) return;
    app.applyReminderAction(action);
  }

  void _schedule({bool immediate = false}) {
    _timer?.cancel();
    if (immediate) {
      unawaited(_reconcile());
    } else {
      _timer = Timer(debounce, () => unawaited(_reconcile()));
    }
  }

  Future<void> _reconcile() async {
    if (app.isLoading || !settings.loaded) return;
    try {
      if (!app.isSetUp || !settings.remindersEnabled) {
        await scheduler.cancelAll();
        return;
      }
      final plan = planner.plan(
        app,
        now: DateTime.now(),
        digestEnabled: settings.digestEnabled,
        digestHour: settings.digestTime.hour,
        digestMinute: settings.digestTime.minute,
        visitLeadMinutes: settings.visitLeadMinutes,
      );
      await scheduler.reconcile(plan);
    } catch (e) {
      debugPrint('Reminder sync failed: $e');
    }
  }

  void _open(ReminderTap tap) {
    final nav = navigatorKey.currentState;
    if (nav == null || app.isLoading || !app.isSetUp) {
      _pendingTap = tap;
      return;
    }
    final id = tap.entityId;
    switch (tap.source) {
      case ReminderSource.leadFollowUp when app.lead(id) != null:
        nav.push(MaterialPageRoute<void>(
            builder: (_) => LeadDetailScreen(leadId: id!)));
      case ReminderSource.payment when app.deal(id) != null:
        nav.push(MaterialPageRoute<void>(
            builder: (_) => DealDetailScreen(dealId: id!)));
      case ReminderSource.visit:
        nav.pushNamed(Routes.visits);
      case ReminderSource.document:
        nav.pushNamed(Routes.documents);
      case ReminderSource.task:
        final t = app.task(id);
        if (t?.relatedKind == EntityKind.lead && app.lead(t?.relatedId) != null) {
          nav.push(MaterialPageRoute<void>(
              builder: (_) => LeadDetailScreen(leadId: t!.relatedId!)));
        } else {
          nav.pushNamed(Routes.tasks);
        }
      default:
        // Digest, or a record that has since been deleted: Today is home.
        nav.popUntil((r) => r.isFirst);
    }
  }

  void dispose() {
    _timer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    app.removeListener(_onAppChanged);
    settings.removeListener(_schedule);
  }
}
