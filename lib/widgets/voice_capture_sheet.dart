import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/system_settings.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import '../utils/formatters.dart';

/// Opens the voice-to-record flow and returns what the broker confirmed,
/// or null if they backed out.
Future<VoiceCapture?> showVoiceCaptureSheet(BuildContext context) {
  return showModalBottomSheet<VoiceCapture>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _VoiceCaptureSheet(),
  );
}

enum _Phase { consent, idle, listening, review }

class _VoiceCaptureSheet extends StatefulWidget {
  const _VoiceCaptureSheet();

  @override
  State<_VoiceCaptureSheet> createState() => _VoiceCaptureSheetState();
}

class _VoiceCaptureSheetState extends State<_VoiceCaptureSheet>
    with SingleTickerProviderStateMixin {
  final _speech = SpeechService();
  static const _parser = VoiceParser();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  late final TextEditingController _transcript = TextEditingController();

  _Phase _phase = _Phase.idle;
  VoiceCapture? _capture;
  String _live = '';
  String? _error;
  bool _permanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    _speech.hasPermission.then((granted) {
      if (!mounted || granted) return;
      setState(() => _phase = _Phase.consent);
    });
  }

  @override
  void dispose() {
    if (_speech.isListening) _speech.cancel();
    _pulse.dispose();
    _transcript.dispose();
    super.dispose();
  }

  Future<void> _allowMicrophone() async {
    if (_permanentlyDenied) {
      await SystemSettings.openAppSettings();
      return;
    }
    // Initialising the recogniser shows Android's microphone prompt.
    await _speech.init();
    final granted = await _speech.hasPermission;
    if (!mounted) return;
    setState(() {
      if (granted) {
        _phase = _Phase.idle;
      } else {
        // Android only asks twice; after that it has to be done in Settings.
        _permanentlyDenied = true;
        _error = "Microphone access is off. Turn it on in the app's "
            'settings › Permissions.';
      }
    });
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _live = '';
    });
    final problem = await _speech.init(onError: (msg) {
      if (!mounted || _phase != _Phase.listening) return;
      // "No match" just means nothing was heard; let them try again.
      setState(() {
        _error = msg.contains('no_match') || msg.contains('speech_timeout')
            ? "Didn't catch that — tap the mic and try again."
            : 'Speech recognition stopped ($msg).';
        _phase = _live.isEmpty ? _Phase.idle : _Phase.review;
        if (_live.isNotEmpty) _finish(_live);
      });
    });
    if (!mounted) return;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() => _phase = _Phase.listening);
    await _speech.start(onText: (words, isFinal) {
      if (!mounted) return;
      setState(() => _live = words);
      if (isFinal) setState(() => _finish(words));
    });
  }

  Future<void> _stop() async {
    await _speech.stop();
    if (!mounted) return;
    if (_live.isEmpty) {
      setState(() => _phase = _Phase.idle);
    } else if (_phase == _Phase.listening) {
      setState(() => _finish(_live));
    }
  }

  void _finish(String words) {
    _capture = _parser.parse(words);
    _transcript.text = words;
    _phase = _Phase.review;
  }

  void _reparse() {
    final reparsed = _parser.parse(_transcript.text);
    setState(() => _capture = reparsed);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: switch (_phase) {
          _Phase.consent => _buildConsent(context),
          _Phase.idle => _buildIdle(context),
          _Phase.listening => _buildListening(context),
          _Phase.review => _buildReview(context),
        },
      ),
    );
  }

  Widget _buildConsent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.mic_none, size: 22),
            const SizedBox(width: 10),
            Text('Microphone access',
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        Gap.m,
        Text(
          'Used only while you dictate a note. The phone turns your words '
          'into text; no recording is kept.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (_error != null) ...[
          Gap.s,
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        Gap.l,
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Not now'),
              ),
            ),
            Gap.m,
            Expanded(
              child: FilledButton(
                onPressed: _allowMicrophone,
                child: Text(_permanentlyDenied ? 'Open settings' : 'Allow'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIdle(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Dictate a note',
            style: Theme.of(context).textTheme.titleMedium),
        Gap.s,
        Text(
          'Say the buyer\'s name, phone, budget, preferred area and when to '
          'follow up. You will review everything before it is saved.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        if (_error != null) ...[
          Gap.m,
          Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        Gap.l,
        _MicButton(onTap: _start, animation: _pulse, active: false),
        Gap.l,
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Type it instead'),
        ),
        Gap.s,
      ],
    );
  }

  Widget _buildListening(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Listening…', style: Theme.of(context).textTheme.titleMedium),
        Gap.s,
        Text(
          _live.isEmpty ? 'Start speaking…' : _live,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Gap.l,
        _MicButton(onTap: _stop, animation: _pulse, active: true),
        Gap.s,
        Text('Tap to finish',
            style: Theme.of(context).textTheme.bodySmall),
        Gap.l,
        const _Waveform(),
        Gap.l,
      ],
    );
  }

  Widget _buildReview(BuildContext context) {
    final capture = _capture!;
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Check before saving',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            ],
          ),
          Gap.s,
          Text(
            'Nothing is saved until you confirm. Edit the transcript and the '
            'fields update.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          Gap.m,
          TextField(
            controller: _transcript,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Transcript',
              alignLabelWithHint: true,
            ),
            onChanged: (_) => _reparse(),
          ),
          Gap.m,
          Text('Picked out of the note',
              style: Theme.of(context).textTheme.labelLarge),
          Gap.s,
          if (capture.extracted.isEmpty)
            Text(
              'Nothing recognised — you can still save the note and fill the '
              'fields in by hand.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.error),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if ((capture.name ?? '').isNotEmpty)
                  _Pill(icon: Icons.person_outline, text: capture.name!),
                if ((capture.phone ?? '').isNotEmpty)
                  _Pill(icon: Icons.call_outlined, text: capture.phone!),
                if (capture.budgetMax > 0 || capture.budgetMin > 0)
                  _Pill(
                    icon: Icons.account_balance_wallet_outlined,
                    text: formatBudgetRange(
                        capture.budgetMin, capture.budgetMax),
                  ),
                if ((capture.location ?? '').isNotEmpty)
                  _Pill(
                      icon: Icons.place_outlined, text: capture.location!),
                if (capture.propertyType != null)
                  _Pill(
                    icon: capture.propertyType!.icon,
                    text: capture.propertyType!.label,
                  ),
                if (capture.bedrooms > 0)
                  _Pill(
                      icon: Icons.bed_outlined,
                      text: formatBedrooms(capture.bedrooms)),
                if (capture.followUpAt != null)
                  _Pill(
                    icon: Icons.event_outlined,
                    text:
                        'Follow up ${formatRelativeDay(capture.followUpAt)}',
                  ),
              ],
            ),
          Gap.l,
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _phase = _Phase.idle),
                  child: const Text('Try again'),
                ),
              ),
              Gap.m,
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, capture),
                  icon: const Icon(Icons.check),
                  label: const Text('Use this'),
                ),
              ),
            ],
          ),
          Gap.s,
        ],
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.onTap,
    required this.animation,
    required this.active,
  });

  final VoidCallback? onTap;
  final Animation<double> animation;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final scale = active ? 1 + 0.12 * math.sin(animation.value * 2 * math.pi) : 1.0;
          return Container(
            width: 104 * scale,
            height: 104 * scale,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? scheme.error : scheme.primary,
              boxShadow: [
                BoxShadow(
                  color: (active ? scheme.error : scheme.primary)
                      .withValues(alpha: 0.28),
                  blurRadius: 24 * scale,
                  spreadRadius: 4 * scale,
                ),
              ],
            ),
            child: Icon(
              active ? Icons.graphic_eq : Icons.mic,
              color: Colors.white,
              size: 44,
            ),
          );
        },
      ),
    );
  }
}

class _Waveform extends StatefulWidget {
  const _Waveform();

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(18, (i) {
          final phase = (_c.value * 2 * math.pi) + i * 0.6;
          final h = 8 + 26 * (0.5 + 0.5 * math.sin(phase)).abs();
          return Container(
            width: 4,
            height: h,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.35 + 0.5 * (h / 34)),
              borderRadius: BorderRadius.circular(999),
            ),
          );
        }),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
