import 'dart:async';

import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/models.dart';
import '../utils/formatters.dart';

/// What the broker said, already pulled apart into fields the broker can
/// check before anything is saved (report p. 4, 3.3: the broker must confirm
/// or edit the extracted information).
class VoiceCapture {
  VoiceCapture({
    required this.transcript,
    this.name,
    this.phone,
    this.budgetMin = 0,
    this.budgetMax = 0,
    this.location,
    this.propertyType,
    this.bedrooms = 0,
    this.followUpAt,
    this.notes = '',
  });

  final String transcript;
  String? name;
  String? phone;
  double budgetMin;
  double budgetMax;
  String? location;
  PropertyType? propertyType;
  int bedrooms;
  DateTime? followUpAt;
  String notes;

  /// Fields we managed to pull out, for the review screen's summary line.
  List<String> get extracted => [
        if ((name ?? '').isNotEmpty) 'name',
        if ((phone ?? '').isNotEmpty) 'phone',
        if (budgetMax > 0 || budgetMin > 0) 'budget',
        if ((location ?? '').isNotEmpty) 'location',
        if (propertyType != null) 'property type',
        if (bedrooms > 0) 'bedrooms',
        if (followUpAt != null) 'follow-up date',
      ];

  bool get isUsable => (name ?? '').isNotEmpty || (phone ?? '').isNotEmpty;
}

/// Pulls lead fields out of a dictated note.
///
/// Rule-based and deliberately forgiving: it only fills fields it is fairly
/// sure of, and the broker reviews everything before it is saved.
class VoiceParser {
  const VoiceParser();

  /// A deliberately imperfect, rule-based parse of a dictated note.
  VoiceCapture parse(String transcript) {
    final capture = VoiceCapture(transcript: transcript, notes: transcript);
    final lower = transcript.toLowerCase();

    capture.phone = _phone(transcript);
    capture.name = _name(transcript);
    final budget = _budget(lower);
    capture.budgetMin = budget.$1;
    capture.budgetMax = budget.$2;
    capture.location = _location(transcript);
    capture.propertyType = _propertyType(lower);
    capture.bedrooms = _bedrooms(lower);
    capture.followUpAt = _followUp(lower);
    return capture;
  }

  static String? _phone(String text) {
    final m = RegExp(r'(\d[\d\s-]{8,14}\d)').firstMatch(text);
    if (m == null) return null;
    final digits = m.group(1)!.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return null;
    final last10 = digits.substring(digits.length - 10);
    return '${last10.substring(0, 5)} ${last10.substring(5)}';
  }

  static String? _name(String text) {
    final m = RegExp(
      r'(?:lead|enquiry|client|buyer|seller|name is|add|walk in)\s+'
      r'([A-Z][a-z]+(?:\s[A-Z][a-z]+)?)',
    ).firstMatch(text);
    return m?.group(1);
  }

  /// Returns (min, max) in rupees.
  static (double, double) _budget(String lower) {
    double unitValue(String n, String unit) {
      final v = double.tryParse(n) ?? 0;
      return unit.startsWith('c') ? v * 10000000 : v * 100000;
    }

    // Each side carries its own unit: "80 lakh to 1 crore" is not 80 crore.
    // When the first side leaves the unit off ("80 to 90 lakh") it borrows
    // the second one.
    final range = RegExp(
      r'(\d+(?:\.\d+)?)\s*(lakh|lac|crore|cr)?\s*(?:\bto\b|-|–)\s*'
      r'(\d+(?:\.\d+)?)\s*(lakh|lac|crore|cr)',
    ).firstMatch(lower);
    if (range != null) {
      final maxUnit = range.group(4)!;
      final minUnit = range.group(2) ?? maxUnit;
      return (
        unitValue(range.group(1)!, minUnit),
        unitValue(range.group(3)!, maxUnit),
      );
    }

    final single = RegExp(
      r'(?:budget|around|about|asking|up ?to|under)?\s*'
      r'(\d+(?:\.\d+)?)\s*(lakh|lac|crore|cr)',
    ).firstMatch(lower);
    if (single != null) {
      final value = unitValue(single.group(1)!, single.group(2)!);
      final capped = RegExp(r'(up ?to|under|below)').hasMatch(lower);
      return capped ? (0, value) : (value * 0.9, value * 1.1);
    }
    return (0, 0);
  }

  static String? _location(String text) {
    final m = RegExp(r'\b(?:in|at|near)\s+([A-Z][A-Za-z]+(?:\s[A-Z][A-Za-z]+)?)')
        .firstMatch(text);
    return m?.group(1)?.trim();
  }

  static PropertyType? _propertyType(String lower) {
    if (lower.contains('villa')) return PropertyType.villa;
    if (lower.contains('plot')) return PropertyType.plot;
    if (lower.contains('office')) return PropertyType.office;
    if (lower.contains('shop')) return PropertyType.shop;
    if (lower.contains('independent house') || lower.contains('row house')) {
      return PropertyType.house;
    }
    if (lower.contains('apartment') || lower.contains('flat')) {
      return PropertyType.apartment;
    }
    return null;
  }

  static int _bedrooms(String lower) {
    final m = RegExp(r'(\d)\s*(?:bhk|bed)').firstMatch(lower);
    if (m != null) return int.tryParse(m.group(1)!) ?? 0;
    const words = {'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5};
    for (final entry in words.entries) {
      if (lower.contains('${entry.key} bhk') ||
          lower.contains('${entry.key} bedroom')) {
        return entry.value;
      }
    }
    return 0;
  }

  static DateTime? _followUp(String lower) {
    final now = DateTime.now();
    final today = DateUtilsX.startOfDay(now);

    final inDays = RegExp(r'in (\d+) days?').firstMatch(lower);
    if (inDays != null) {
      return today
          .add(Duration(days: int.tryParse(inDays.group(1)!) ?? 1))
          .add(const Duration(hours: 10));
    }
    if (lower.contains('day after tomorrow')) {
      return today.add(const Duration(days: 2, hours: 10));
    }
    if (lower.contains('tomorrow')) {
      final hour = lower.contains('evening') ? 18 : 10;
      return today.add(Duration(days: 1, hours: hour));
    }
    if (lower.contains('next week')) {
      return today.add(const Duration(days: 7, hours: 10));
    }

    const weekdays = {
      'monday': DateTime.monday,
      'tuesday': DateTime.tuesday,
      'wednesday': DateTime.wednesday,
      'thursday': DateTime.thursday,
      'friday': DateTime.friday,
      'saturday': DateTime.saturday,
      'sunday': DateTime.sunday,
    };
    for (final entry in weekdays.entries) {
      if (lower.contains(entry.key)) {
        var delta = (entry.value - today.weekday) % 7;
        if (delta == 0) delta = 7;
        return today.add(Duration(days: delta, hours: 10));
      }
    }
    return null;
  }
}

/// The phone's own speech recogniser (Google's on Android). It runs in the
/// recogniser app, not in Broker Diary; with the offline language pack
/// installed it needs no internet at all.
class SpeechService {
  final SpeechToText _speech = SpeechToText();
  bool _ready = false;
  String? _localeId;

  /// Null when ready, otherwise why speech can't be used.
  Future<String?> init({void Function(String error)? onError}) async {
    if (_ready) return null;
    try {
      _ready = await _speech.initialize(
        onError: (e) => onError?.call(e.errorMsg),
      );
    } catch (e) {
      return 'Speech recognition failed to start: $e';
    }
    if (!_ready) {
      return 'Speech recognition is not available on this phone. '
          'Check that the Google app is installed and microphone access '
          'is allowed.';
    }
    // Prefer Indian English, which handles "lakh", "crore" and local names.
    try {
      final locales = await _speech.locales();
      final indian = locales.where((l) => l.localeId.toLowerCase().replaceAll('-', '_') == 'en_in');
      _localeId = indian.isNotEmpty ? indian.first.localeId : null;
    } catch (_) {}
    return null;
  }

  bool get isListening => _speech.isListening;

  /// Whether the microphone has already been allowed.
  Future<bool> get hasPermission async {
    try {
      return await _speech.hasPermission;
    } catch (_) {
      return false;
    }
  }

  Future<void> start({
    required void Function(String words, bool isFinal) onText,
    void Function(double level)? onSoundLevel,
  }) async {
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) =>
          onText(r.recognizedWords, r.finalResult),
      onSoundLevelChange: onSoundLevel,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 5),
        localeId: _localeId,
      ),
    );
  }

  Future<void> stop() => _speech.stop();

  Future<void> cancel() => _speech.cancel();
}
