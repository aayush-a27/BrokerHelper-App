# BrokerHelper App (Flutter)

**Broker Diary** is an offline CRM for real estate brokers, built with
Flutter for Android. It works like a broker's diary: leads, contacts,
properties, site visits, follow-ups, deals and commission, with reminders
that ring on time.

**Everything stays on the phone.** There is no server, no account and no
login. The app does not even ask for the internet permission, so it cannot
send a client's details anywhere. Each broker's data lives only on their own
phone.

| | |
|---|---|
| Platform | Android 7.0+ (minSdk 24, targetSdk 36) |
| Framework | Flutter 3.47 / Dart 3 |
| Storage | JSON files in the app's private folder (no database, no server) |
| State | `provider` + `ChangeNotifier` |
| Reminders | `flutter_local_notifications` (Android AlarmManager) |
| Tests | 87 unit and widget tests |

### Quick start

```bash
git clone <this repo>
cd <this repo>
flutter pub get
flutter run            # with an Android phone connected over USB
```

### Highlights

- Leads, contacts, properties and buyer–property matching
- Site visits, follow-ups and deals with commission tracking
- Reminders that work with the app closed, with Snooze / Done buttons and a morning summary
- Real photos and documents (PDF, camera, gallery), kept inside the diary
- Voice entry using the phone's speech recogniser
- One-tap backup to WhatsApp / Drive and restore on a new phone
- PIN and fingerprint app lock, 30-day "Recently deleted" with undo
- CSV (Excel) and PDF export

Because there is no server, the **backup file is the only copy that survives
a lost phone or an uninstall**. The app nudges the broker every week to send
themselves one.

---

## Building

```bash
flutter pub get
flutter analyze          # clean
flutter test             # 86 tests
flutter build apk --release --split-per-abi
```

The APKs end up in `build/app/outputs/flutter-apk/`. Send
`app-arm64-v8a-release.apk` (about 20 MB) for any phone made since about
2017.

Built with **Flutter 3.47.7** / Dart 3. Android **minSdk 24** (Android 7.0),
targetSdk 36, compileSdk 36.

On the development machine, the JDK and Android SDK are not on the PATH:

```powershell
$env:JAVA_HOME='C:\tools\jdk-17.0.20.1+1'
$env:ANDROID_SDK_ROOT='C:\Android\Sdk'; $env:ANDROID_HOME='C:\Android\Sdk'
$env:PATH="$env:JAVA_HOME\bin;C:\Android\Sdk\platform-tools;C:\flutter\bin;$env:PATH"
```

### Before publishing to the Play Store

1. **Application id.** It is `com.brokerdiary.app` in
   `android/app/build.gradle.kts`. Change it to the client's own id
   **before the first release**. It can never change after that.
2. **Signing key.** Create an upload keystore and an `android/key.properties`:

   ```properties
   storePassword=…
   keyPassword=…
   keyAlias=upload
   storeFile=C:/path/to/upload-keystore.jks
   ```

   The Gradle file picks it up automatically. Without it, release builds use
   the debug key. That is fine for sideloading but cannot be published, and
   later builds signed with a real key won't install over it. **Keep the
   keystore safe:** losing it means the app can never be updated.
3. **Version.** Bump `version:` in `pubspec.yaml` for every release.
4. **Play Console declarations:**
   - *Exact alarms.* The app uses `SCHEDULE_EXACT_ALARM` so follow-up
     reminders fire on the minute. The user can turn it off, and the app
     then falls back to inexact timing. It deliberately does **not** use
     `USE_EXACT_ALARM`, which Play restricts.
   - *Data safety.* No data is collected or shared. Nothing leaves the
     device except files the user sends themselves.

---

## How the data is stored

```
<app documents>/diary/
  profile.json   leads.json      contacts.json   properties.json
  visits.json    tasks.json      deals.json      payments.json
  documents.json activity.json   trash.json      settings.json
  attachments/   ← copies of photos and documents
```

- **One JSON file per collection.** Saving a lead rewrites only
  `leads.json`. Each file is `{"version": 1, "items": [...]}`, so later app
  versions can migrate old files.
- **Everything is held in memory** once loaded (`AppState`), so reads are
  instant. A broker's diary is a few MB even after years of use. Photos are
  files on disk, not part of the JSON.
- **Saves are batched.** A change marks its collection dirty, and a save
  runs 300 ms later. Ten quick edits cost one write. The app also saves
  immediately whenever it leaves the screen, so swiping it away loses
  nothing.
- **Crash-safe writes.** Each save writes `x.json.tmp`, moves the old file
  to `x.json.bak`, then renames the new one into place. If the phone dies
  mid-save, the next start reads whichever copy is complete
  (`FileDiaryStorage.read`).
- **Damaged records are skipped one at a time**, never the whole file.
- **If a save fails** (usually a full phone), a red banner says so, the
  change stays on screen, and the save retries.
- **Ids are random UUIDs**, so a restored backup can never collide with
  records created since.
- **Dates are stored in UTC**, so a diary restored in another time zone
  still means the same moments.

### Deleting

Nothing is deleted outright. A delete moves the record, plus anything that
went with it (a deal's payments, a visit's reminder task), to **Recently
deleted** for 30 days. Every delete offers **Undo**. After 30 days the record
and its files are purged on the next app start.

Unused attachments are cleaned up after a day: a photo replaced in a form, or
one picked for a form that was then cancelled.

---

## Backup and restore

**Settings › Backup**

- **Back up now and send** builds one `.zip` (manifest, every JSON file,
  every attachment) and opens the phone's share sheet. The broker sends it
  to themselves on WhatsApp, Drive, email or anywhere else. The phone does
  the sending; the app has no network code.
- **Save backup to phone** saves the zip to a folder the broker picks, such
  as Downloads.
- **Restore** checks the file first and shows whose diary it is, when it was
  made and how many records it holds. A damaged file or one from a newer app
  version is refused **before anything is overwritten**.
- **Safety copies.** Before any restore over an existing diary, the current
  diary is saved to `safety_copies/` (the last three are kept). A restore of
  the wrong file can be undone.
- First launch on a new phone offers **"I have a backup from another
  phone"**.
- Settings (PIN, theme) are not in backups, so the old phone's PIN doesn't
  follow the diary.

Android's own Google backup (`allowBackup`) is left on as an extra safety
net. The app does not depend on it.

---

## Reminders

`flutter_local_notifications` hands each reminder to Android's AlarmManager.
Reminders fire with the app closed, survive a reboot and need no internet.

| Reminder | When |
|---|---|
| Follow-up task | At its due time, with **Snooze 1 hour** / **Done** buttons |
| Lead follow-up | At `nextFollowUpAt`, with Snooze / Done (skipped if a follow-up task already covers it) |
| Site visit | 15 min to 2 h before (setting) |
| Commission due | 10 am on the due date |
| Document expiry | 10 am, a week before |
| Morning summary | Daily at a set time: "3 follow-ups · 1 site visit · 2 overdue" |

**How it stays correct** (`services/reminder_*.dart`):

- `ReminderPlanner` is pure Dart. From the diary and the clock it works out
  exactly which reminders should exist: the next 30 days, at most 60, nearest
  first. Every reminder has a stable id derived from its record.
- `LocalReminderScheduler.reconcile` compares that plan with what the phone
  has pending. It cancels what's gone or changed and schedules what's new.
  It runs a second after any change to the diary, and on every app start and
  resume. The window rolls forward and the morning-summary counts stay
  current.
- **Snooze / Done with the app closed:** the press runs in a background
  isolate. If the app is alive it's passed straight in. Otherwise it's
  queued as a file and applied on next launch. A snooze is re-armed
  immediately, so it rings again in an hour even if the app isn't opened.
- Tapping a reminder opens the lead, deal or list it is about.

**Settings › Reminders not arriving?** checks the notification and exact-alarm
permissions and sends a test reminder. It also has step-by-step battery
settings for Xiaomi, Oppo/Realme, Vivo, OnePlus and Samsung. Those phones stop
background alarms to save battery, and no code can override that.

---

## Privacy

- **App lock.** A 4–6 digit PIN (salted and stretched with SHA-256, never
  stored as typed), optional fingerprint, and a re-lock delay of 30 s to
  15 min. Five wrong PINs trigger a 30-second wait.
- **Forgot PIN** can only erase the diary, since there is no account to
  reset it by email. The broker then restores their latest backup. The lock
  screen says this plainly.
- The lock keeps the diary private from someone holding the phone. **The
  files are not encrypted.** Android already keeps app files private to the
  app, and files on most modern phones are encrypted at rest by the OS.
- **Erase all data** (Settings) asks the broker to type ERASE.

### Android permissions

| Permission | Why |
|---|---|
| `POST_NOTIFICATIONS` | Reminders (asked on first run, with the reason on screen) |
| `SCHEDULE_EXACT_ALARM` | Reminders on the minute |
| `RECEIVE_BOOT_COMPLETED` | Re-arm reminders after a restart |
| `VIBRATE` | Reminder vibration |
| `RECORD_AUDIO` | Dictating a lead (only while the mic sheet is open) |
| `USE_BIOMETRIC` | Fingerprint unlock |

No `INTERNET`, no storage or media permissions. Files are picked through the
system picker, and photos come from the system camera and gallery.

---

## Features

| Feature | Where |
|---|---|
| First-run setup | Name, phone, agency. Or restore a backup |
| Today | Due and overdue follow-ups, calls to make, upcoming visits, pipeline, commission, backup nudge. A first-use guide when the diary is empty |
| Leads | Search, status/source filters, **Needs details** filter for quick jots, duplicate-phone warning |
| Contacts | One record per person; buyer and seller sections; call log |
| Properties | Cover photo from the camera or gallery; availability; interested buyers |
| Matching | A lead › **Match properties**, with reasons for each match |
| Site visits | Calendar strip, outcomes, reminder before each |
| Follow-ups | **More › Follow-ups**; snooze/done from the notification |
| Deals | Pipeline, milestones, commission instalments |
| Documents | Real files (PDF, photos), opened in the phone's viewer, shared via the share sheet; "still to collect" placeholders; expiry reminders |
| Voice | **+ › Dictate**: the phone's speech recogniser (works offline with the language pack), then a review before saving |
| WhatsApp / call | Pre-filled messages; the broker presses send |
| Export | CSV (opens in Excel) and PDF from any list |
| Activity log | Every change, by day |
| Recently deleted | 30-day bin with restore |
| Settings | Backup/restore, reminders, app lock, dark theme, storage used, erase |

---

## Project layout

```
lib/
  main.dart                  start-up: storage, settings, lifecycle saves
  app.dart                   routes, first-run vs home, lock overlay
  data/diary_storage.dart    JSON files on the phone (+ in-memory for tests)
  models/                    records with fromJson/toJson
  state/
    app_state.dart           the diary: CRUD, batching, trash, reminder actions
    settings_state.dart      preferences, PIN, last backup
    lock_state.dart          AppLock: when the PIN screen shows
  services/
    reminder_planner.dart    what should ring, and when (pure)
    reminder_service.dart    Android notifications, actions, queue
    reminder_coordinator.dart keeps the two in step
    backup_service.dart      zip backup, inspect, restore, safety copies
    attachment_service.dart  photos & files into the diary folder
    voice_service.dart       speech recogniser + note parser
    export_*.dart            CSV / PDF
    system_settings.dart     opens the app's system settings page
  screens/                   one file per screen
  widgets/                   shared UI
test/                        storage, persistence, trash, reminders, backup,
                             parsing, matching, export, and widget tests
```

## Tests

```bash
flutter test
```

- `storage_test.dart`: atomic writes, fallback to `.bak`/`.tmp`, ordered
  parallel writes, restart round-trips for every record type, write
  batching, unique ids, skipping bad records, save-failure retry, erase,
  trash and restore, follow-up sync, Snooze/Done.
- `reminder_planner_test.dart`: what is scheduled and when, de-duplication,
  the 30-day window and cap, stable ids, morning summary.
- `backup_test.dart`: backup on one "phone" restored on another (photos
  included), safety copy and undo, refusal of wrong, newer or damaged files
  without touching the diary.
- `screens_smoke_test.dart`: first-run setup, every screen at phone size,
  undo-delete, PIN lock.
- Plus the voice parser, matcher, CSV/PDF export and lead form.

## Not covered yet

- **iOS** builds were not tested. `Info.plist` has the permission texts, but
  notification actions and background handling need checking on a real
  iPhone.
- **Encryption of the files.** See *Privacy* above.
- **More than one device per broker.** Moving to a new phone works through
  backup/restore. Two phones in use at once is not supported, because there
  is no sync.
