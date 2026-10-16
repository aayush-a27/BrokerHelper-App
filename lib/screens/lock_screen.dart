import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/reminder_service.dart';
import '../state/app_state.dart';
import '../state/lock_state.dart';
import '../state/settings_state.dart';

/// Covers the whole app until the PIN (or fingerprint) is given.
///
/// It sits above the navigator, so it can't use dialogs; "Forgot PIN" is a
/// second view inside this screen instead.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  String? _error;
  bool _forgot = false;
  bool _erasing = false;
  bool _canBiometric = false;

  @override
  void initState() {
    super.initState();
    _initBiometric();
  }

  Future<void> _initBiometric() async {
    final lock = context.read<AppLock>();
    if (!lock.settings.biometricEnabled) return;
    final can = await lock.canUseBiometrics();
    if (!mounted) return;
    setState(() => _canBiometric = can);
    if (can) await lock.unlockWithBiometrics();
  }

  int get _length => context.read<SettingsState>().pinLength;

  void _tap(String digit) {
    if (_pin.length >= _length) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == _length) _tryUnlock();
  }

  void _tryUnlock() {
    final lock = context.read<AppLock>();
    final error = lock.unlockWithPin(_pin);
    if (error == null) return;
    setState(() {
      _error = error;
      _pin = '';
    });
  }

  Future<void> _erase() async {
    setState(() => _erasing = true);
    final app = context.read<AppState>();
    final settings = context.read<SettingsState>();
    final lock = context.read<AppLock>();
    final scheduler = context.read<ReminderScheduler>();
    await scheduler.cancelAll();
    await app.eraseAllData();
    await settings.reset();
    lock.reset();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: _forgot ? _buildForgot(theme) : _buildPad(theme),
          ),
        ),
      ),
    );
  }

  Widget _buildPad(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 40, color: scheme.primary),
          const SizedBox(height: 12),
          Text('Enter your PIN', style: theme.textTheme.titleLarge),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _length,
              (i) => Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? scheme.primary : null,
                  border: Border.all(color: scheme.outline),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 36,
            child: Center(
              child: Text(_error ?? '',
                  style: TextStyle(color: scheme.error)),
            ),
          ),
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [for (final d in row) _key(d)],
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: _canBiometric
                    ? IconButton(
                        tooltip: 'Use fingerprint',
                        iconSize: 32,
                        onPressed: () =>
                            context.read<AppLock>().unlockWithBiometrics(),
                        icon: const Icon(Icons.fingerprint),
                      )
                    : null,
              ),
              _key('0'),
              SizedBox(
                width: 76,
                height: 76,
                child: IconButton(
                  tooltip: 'Delete',
                  onPressed: _pin.isEmpty
                      ? null
                      : () => setState(
                          () => _pin = _pin.substring(0, _pin.length - 1)),
                  icon: const Icon(Icons.backspace_outlined),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() => _forgot = true),
            child: const Text('Forgot PIN?'),
          ),
        ],
      ),
    );
  }

  Widget _key(String digit) => SizedBox(
        width: 76,
        height: 76,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
            ),
            onPressed: () => _tap(digit),
            child: Text(digit, style: const TextStyle(fontSize: 24)),
          ),
        ),
      );

  Widget _buildForgot(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.help_outline, size: 40, color: scheme.primary),
          const SizedBox(height: 12),
          Text('Forgot your PIN?',
              textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          const Text(
            'There is no account and no server, so the PIN can\'t be reset '
            'by email. The only way in is to erase this phone\'s diary and '
            'start again — then restore your latest backup file.',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: _erasing ? null : _erase,
            icon: const Icon(Icons.delete_forever_outlined),
            label: Text(_erasing ? 'Erasing…' : 'Erase diary and start again'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _erasing ? null : () => setState(() => _forgot = false),
            child: const Text('Back to PIN'),
          ),
        ],
      ),
    );
  }
}
