import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/models.dart' hide Priority;
import '../state/app_state.dart';
import 'reminder_planner.dart';

/// A notification the broker tapped, for opening the record it is about.
class ReminderTap {
  const ReminderTap({required this.source, this.kind, this.entityId});

  final ReminderSource source;
  final EntityKind? kind;
  final String? entityId;
}

/// What the rest of the app needs from the phone's notification system.
/// Tests use [NoopReminderScheduler].
abstract class ReminderScheduler {
  Future<void> init();

  /// Makes the phone's pending notifications match [planned] exactly.
  Future<void> reconcile(List<PlannedReminder> planned);

  Future<void> cancelAll();

  /// Asks for notification permission. Returns whether it is granted.
  Future<bool> requestPermission();

  Future<ReminderStatus> status();

  /// Opens the system screen for "Alarms & reminders" (Android 12+).
  Future<void> requestExactAlarms();

  Future<void> showTest();

  Stream<ReminderTap> get taps;
  Stream<ReminderAction> get actions;

  /// Snooze / Done presses made while the app was closed.
  Future<List<ReminderAction>> takeQueuedActions();

  /// The tap that opened the app, if it was opened from a notification.
  Future<ReminderTap?> launchTap();
}

class ReminderStatus {
  const ReminderStatus({
    required this.notificationsAllowed,
    required this.exactAlarmsAllowed,
    required this.pendingCount,
  });

  final bool notificationsAllowed;

  /// When false, Android may deliver a reminder up to ~15 minutes late.
  final bool exactAlarmsAllowed;
  final int pendingCount;
}

/// Reminders through `flutter_local_notifications`, which hands them to
/// Android's own AlarmManager — they fire with the app closed, survive a
/// reboot, and need no internet.
class LocalReminderScheduler implements ReminderScheduler {
  LocalReminderScheduler._();

  static final instance = LocalReminderScheduler._();

  static const portName = 'broker_diary_reminder_actions';
  static const _followUpChannel = 'follow_ups';
  static const _digestChannel = 'daily_digest';
  static const actionSnooze = 'snooze';
  static const actionDone = 'done';

  final _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<ReminderTap>.broadcast();
  final _actions = StreamController<ReminderAction>.broadcast();
  ReceivePort? _port;
  bool _ready = false;

  @override
  Stream<ReminderTap> get taps => _taps.stream;

  @override
  Stream<ReminderAction> get actions => _actions.stream;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_diary'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );

    await _android?.createNotificationChannel(const AndroidNotificationChannel(
      _followUpChannel,
      'Follow-ups and visits',
      description: 'Calls to make, site visits and payments due',
      importance: Importance.high,
    ));
    await _android?.createNotificationChannel(const AndroidNotificationChannel(
      _digestChannel,
      'Morning summary',
      description: "Today's follow-ups and visits, once a day",
      importance: Importance.defaultImportance,
    ));

    // While the app is alive, presses from the background isolate come
    // straight here instead of going through the queue on disk.
    IsolateNameServer.removePortNameMapping(portName);
    final port = ReceivePort();
    IsolateNameServer.registerPortWithName(port.sendPort, portName);
    port.listen((msg) {
      if (msg is Map) {
        _actions.add(ReminderAction.fromJson(Map<String, dynamic>.from(msg)));
      }
    });
    _port = port;
    _ready = true;
  }

  void _onResponse(NotificationResponse response) {
    final action = actionFrom(response);
    if (action != null) {
      _actions.add(action);
      return;
    }
    final tap = tapFrom(response.payload);
    if (tap != null) _taps.add(tap);
  }

  @override
  Future<ReminderTap?> launchTap() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    final response = details.notificationResponse;
    if (response == null || response.actionId != null) return null;
    return tapFrom(response.payload);
  }

  // --- scheduling ----------------------------------------------------------

  @override
  Future<void> reconcile(List<PlannedReminder> planned) async {
    if (!_ready) return;
    final pending = await _plugin.pendingNotificationRequests();
    final wanted = {for (final r in planned) r.id: r};

    for (final req in pending) {
      final want = wanted[req.id];
      if (want == null || _fingerprintOf(req.payload) != want.fingerprint) {
        await _plugin.cancel(id: req.id);
      } else {
        wanted.remove(req.id); // already scheduled exactly as wanted
      }
    }

    if (wanted.isEmpty) return;
    final mode = await _scheduleMode();
    for (final r in wanted.values) {
      try {
        await _plugin.zonedSchedule(
          id: r.id,
          scheduledDate: tz.TZDateTime.from(r.at, tz.UTC),
          title: r.title,
          body: r.body,
          payload: payloadFor(r),
          notificationDetails: _details(r),
          androidScheduleMode: mode,
        );
      } on Exception catch (e) {
        // One bad reminder (e.g. exact alarms revoked mid-run) must not stop
        // the rest; the next reconcile retries it.
        debugPrint('Could not schedule ${r.key}: $e');
      }
    }
  }

  Future<AndroidScheduleMode> _scheduleMode() async {
    final exact = await _android?.canScheduleExactNotifications() ?? true;
    return exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  static NotificationDetails _details(PlannedReminder r) {
    final digest = r.source == ReminderSource.digest;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        digest ? _digestChannel : _followUpChannel,
        digest ? 'Morning summary' : 'Follow-ups and visits',
        importance: digest ? Importance.defaultImportance : Importance.high,
        priority: digest ? Priority.defaultPriority : Priority.high,
        category: AndroidNotificationCategory.reminder,
        styleInformation: BigTextStyleInformation(r.body),
        actions: r.actionable
            ? const [
                AndroidNotificationAction(actionSnooze, 'Snooze 1 hour'),
                AndroidNotificationAction(actionDone, 'Done'),
              ]
            : null,
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }

  @override
  Future<void> cancelAll() async {
    if (_ready) await _plugin.cancelAll();
  }

  @override
  Future<void> showTest() async {
    await _plugin.show(
      id: 1,
      title: 'Reminders are working',
      body: 'This is how a follow-up reminder will look.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _followUpChannel,
          'Follow-ups and visits',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  // --- permissions ---------------------------------------------------------

  @override
  Future<bool> requestPermission() async {
    final android = _android;
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  @override
  Future<void> requestExactAlarms() async {
    await _android?.requestExactAlarmsPermission();
  }

  @override
  Future<ReminderStatus> status() async {
    final android = _android;
    final pending = _ready ? (await _plugin.pendingNotificationRequests()).length : 0;
    return ReminderStatus(
      notificationsAllowed: await android?.areNotificationsEnabled() ?? true,
      exactAlarmsAllowed: await android?.canScheduleExactNotifications() ?? true,
      pendingCount: pending,
    );
  }

  // --- payloads ------------------------------------------------------------

  static String payloadFor(PlannedReminder r) => jsonEncode({
        's': r.source.name,
        if (r.kind != null) 'k': r.kind!.name,
        if (r.entityId != null) 'id': r.entityId,
        'f': r.fingerprint,
        // Kept so a snooze pressed while the app is closed can re-show it.
        't': r.title,
        'b': r.body,
      });

  static Map<String, dynamic>? _decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final j = jsonDecode(payload);
      return j is Map ? Map<String, dynamic>.from(j) : null;
    } on FormatException {
      return null;
    }
  }

  static String? _fingerprintOf(String? payload) =>
      _decode(payload)?['f'] as String?;

  static ReminderTap? tapFrom(String? payload) {
    final j = _decode(payload);
    if (j == null) return null;
    return ReminderTap(
      source: enumFromName(ReminderSource.values, j['s'], ReminderSource.task),
      kind: j['k'] == null
          ? null
          : enumFromName(EntityKind.values, j['k'], EntityKind.task),
      entityId: j['id'] as String?,
    );
  }

  static ReminderAction? actionFrom(NotificationResponse response) {
    final type = switch (response.actionId) {
      actionSnooze => ReminderActionType.snooze,
      actionDone => ReminderActionType.done,
      _ => null,
    };
    final tap = tapFrom(response.payload);
    if (type == null || tap?.kind == null || tap?.entityId == null) return null;
    return ReminderAction(
      type: type,
      kind: tap!.kind!,
      entityId: tap.entityId!,
      at: DateTime.now(),
    );
  }

  // --- presses made while the app was closed -------------------------------

  static Future<Directory> _queueDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'diary', 'pending_actions'));
  }

  static Future<void> _enqueue(ReminderAction action) async {
    final dir = await _queueDir();
    await dir.create(recursive: true);
    // One file per press: two presses can never clobber each other.
    final name =
        '${action.at.microsecondsSinceEpoch}-${action.entityId.hashCode}.json';
    await File(p.join(dir.path, name))
        .writeAsString(jsonEncode(action.toJson()), flush: true);
  }

  @override
  Future<List<ReminderAction>> takeQueuedActions() async {
    final dir = await _queueDir();
    if (!await dir.exists()) return const [];
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final out = <ReminderAction>[];
    for (final f in files) {
      try {
        out.add(ReminderAction.fromJson(
            Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map)));
      } catch (_) {}
      try {
        await f.delete();
      } catch (_) {}
    }
    return out;
  }

  /// Runs in a background isolate when Snooze / Done is pressed.
  static Future<void> handleInBackground(NotificationResponse response) async {
    final action = actionFrom(response);
    if (action == null) return;

    final port = IsolateNameServer.lookupPortByName(portName);
    if (port != null) {
      port.send(action.toJson());
      return;
    }

    // The app isn't running. Park the press on disk for the next launch…
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    await _enqueue(action);

    // …and for a snooze, re-arm the reminder now, so it comes back in an
    // hour even if the app isn't opened in between.
    if (action.type == ReminderActionType.snooze) {
      final j = _decode(response.payload) ?? const {};
      tzdata.initializeTimeZones();
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_diary'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      final snoozed = PlannedReminder(
        key: '${action.kind == EntityKind.lead ? 'lead' : 'task'}:${action.entityId}',
        at: action.at.add(ReminderAction.snoozeFor),
        title: j['t'] as String? ?? 'Follow-up',
        body: j['b'] as String? ?? '',
        source: action.kind == EntityKind.lead
            ? ReminderSource.leadFollowUp
            : ReminderSource.task,
        kind: action.kind,
        entityId: action.entityId,
      );
      await plugin.zonedSchedule(
        id: response.id ?? snoozed.id,
        scheduledDate: tz.TZDateTime.from(snoozed.at, tz.UTC),
        title: snoozed.title,
        body: snoozed.body,
        payload: payloadFor(snoozed),
        notificationDetails: _details(snoozed),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  @visibleForTesting
  void dispose() {
    _port?.close();
    IsolateNameServer.removePortNameMapping(portName);
  }
}

@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) {
  LocalReminderScheduler.handleInBackground(response);
}

/// Does nothing. For widget tests and platforms without notifications.
class NoopReminderScheduler implements ReminderScheduler {
  List<PlannedReminder> lastPlan = const [];

  @override
  Future<void> init() async {}
  @override
  Future<void> reconcile(List<PlannedReminder> planned) async =>
      lastPlan = planned;
  @override
  Future<void> cancelAll() async => lastPlan = const [];
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<ReminderStatus> status() async => ReminderStatus(
      notificationsAllowed: true,
      exactAlarmsAllowed: true,
      pendingCount: lastPlan.length);
  @override
  Future<void> requestExactAlarms() async {}
  @override
  Future<void> showTest() async {}
  @override
  Stream<ReminderTap> get taps => const Stream.empty();
  @override
  Stream<ReminderAction> get actions => const Stream.empty();
  @override
  Future<List<ReminderAction>> takeQueuedActions() async => const [];
  @override
  Future<ReminderTap?> launchTap() async => null;
}
