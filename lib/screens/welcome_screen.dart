import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/backup_service.dart';
import '../services/reminder_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'restore_flow.dart';

/// First launch. There are no accounts — the diary belongs to whoever sets
/// up this phone — so this just asks who the broker is, or offers to bring
/// back a backup from an old phone.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _agency = TextEditingController();
  final _email = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _agency.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final app = context.read<AppState>();
    final scheduler = context.read<ReminderScheduler>();
    app.saveProfile(BrokerProfile(
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      agency: _agency.text.trim(),
      email: _email.text.trim(),
    ));
    await app.flush();
    // Ask now, with the reason in view, rather than out of nowhere later.
    await scheduler.requestPermission();
  }

  Future<void> _restore() async {
    final backup = context.read<BackupService>();
    await runRestoreFlow(context, backup);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.menu_book_rounded,
                        size: 56, color: theme.colorScheme.primary),
                    Gap.m,
                    Text(
                      'Broker Diary',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Gap.s,
                    Text(
                      'Leads, properties, site visits and follow-ups — '
                      'all kept on this phone. No account, no internet.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Your name *',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Enter your name to start'
                          : null,
                    ),
                    Gap.m,
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Your phone',
                        helperText: 'Used in the property details you share',
                        prefixIcon: Icon(Icons.call_outlined),
                      ),
                    ),
                    Gap.m,
                    TextFormField(
                      controller: _agency,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Agency or firm',
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                    ),
                    Gap.m,
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _start(),
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _busy ? null : _start,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Start my diary'),
                    ),
                    Gap.m,
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _restore,
                      icon: const Icon(Icons.settings_backup_restore),
                      label: const Text('I have a backup from another phone'),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_outline,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Your clients\' details never leave this phone '
                            'unless you share them. Take a backup now and '
                            'then from Settings — if the phone is lost, the '
                            'backup file is the only copy.',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
