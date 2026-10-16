import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../utils/formatters.dart';

/// A reusable WhatsApp message with `{{placeholders}}` the broker can reuse
/// across clients (report p. 5, "reusable message templates").
class MessageTemplate {
  const MessageTemplate({
    required this.id,
    required this.title,
    required this.body,
    this.needsProperty = false,
  });

  final String id;
  final String title;
  final String body;
  final bool needsProperty;

  /// Fills `{{clientName}}`-style placeholders. Anything still unfilled is
  /// left visible so the broker notices before sending.
  String render(Map<String, String> values) {
    var out = body;
    values.forEach((key, value) {
      out = out.replaceAll('{{$key}}', value);
    });
    return out;
  }

  List<String> get placeholders => RegExp(r'\{\{(\w+)\}\}')
      .allMatches(body)
      .map((m) => m.group(1)!)
      .toSet()
      .toList();
}

const whatsAppTemplates = <MessageTemplate>[
  MessageTemplate(
    id: 'match',
    title: 'Property match',
    needsProperty: true,
    body: 'Hi {{clientName}}, I found a property matching your criteria — '
        '{{propertyTitle}} in {{propertyLocation}}, {{propertyPrice}}. '
        'Shall I arrange a site visit this week?\n\n– {{brokerName}}, {{agency}}',
  ),
  MessageTemplate(
    id: 'visit',
    title: 'Visit confirmation',
    needsProperty: true,
    body: 'Hi {{clientName}}, confirming our site visit to {{propertyTitle}} '
        'on {{visitTime}}. The address is {{propertyAddress}}. '
        'Please call me if the time needs to change.\n\n– {{brokerName}}',
  ),
  MessageTemplate(
    id: 'followup',
    title: 'Gentle follow-up',
    body: 'Hi {{clientName}}, following up on our conversation. '
        'Are you still looking in {{preferredLocation}} around '
        '{{budget}}? I have a few options I can send across.\n\n– {{brokerName}}',
  ),
  MessageTemplate(
    id: 'documents',
    title: 'Document request',
    body: 'Hi {{clientName}}, to move ahead I will need a copy of your ID '
        'proof and address proof. You can send them here whenever '
        'convenient.\n\n– {{brokerName}}, {{agency}}',
  ),
  MessageTemplate(
    id: 'thanks',
    title: 'Thank you after closing',
    body: 'Hi {{clientName}}, thank you for trusting me with this '
        'transaction. Do reach out any time you need help with property — '
        'referrals are always appreciated.\n\n– {{brokerName}}',
  ),
];

/// Builds the placeholder values available for a given lead/property pair.
Map<String, String> templateValues({
  Lead? lead,
  Contact? contact,
  Property? property,
  BrokerProfile? broker,
  DateTime? visitAt,
}) {
  return {
    'clientName': lead?.name ?? contact?.name ?? 'there',
    'preferredLocation': lead?.preferredLocation ??
        (contact?.buyer.preferredLocations.isNotEmpty ?? false
            ? contact!.buyer.preferredLocations.first
            : 'your preferred area'),
    'budget': lead != null
        ? formatBudgetRange(lead.budgetMin, lead.budgetMax)
        : contact != null
            ? formatBudgetRange(contact.buyer.budgetMin, contact.buyer.budgetMax)
            : 'your budget',
    'propertyTitle': property?.title ?? '',
    'propertyLocation': property?.shortAddress ?? '',
    'propertyAddress': property?.address ?? '',
    'propertyPrice': property == null ? '' : formatMoney(property.price),
    'visitTime': visitAt == null ? '' : formatDateTime(visitAt),
    'brokerName': broker?.name ?? 'Your broker',
    'agency': broker?.agency ?? '',
  };
}

/// What happened when we tried to hand off to another app.
enum LaunchOutcome { opened, unavailable, failed }

/// Deep links out to the dialler and to WhatsApp.
///
/// These are the only places the app hands off to another app. Nothing is sent
/// automatically — WhatsApp opens with the message pre-filled and the broker
/// presses send.
class ShareService {
  const ShareService();

  Future<LaunchOutcome> openWhatsApp({
    required String phone,
    required String message,
  }) async {
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '').replaceAll('+', '');
    final encoded = Uri.encodeComponent(message);

    // wa.me handles both the installed app and the web fallback.
    final uri = Uri.parse(
      digits.isEmpty
          ? 'https://wa.me/?text=$encoded'
          : 'https://wa.me/$digits?text=$encoded',
    );
    return _launch(uri);
  }

  Future<LaunchOutcome> call(String phone) =>
      _launch(Uri(scheme: 'tel', path: phone.replaceAll(' ', '')));

  Future<LaunchOutcome> sms(String phone, String body) => _launch(
        Uri(
          scheme: 'sms',
          path: phone.replaceAll(' ', ''),
          queryParameters: {'body': body},
        ),
      );

  Future<LaunchOutcome> email(String address, String subject) => _launch(
        Uri(
          scheme: 'mailto',
          path: address,
          queryParameters: {'subject': subject},
        ),
      );

  Future<LaunchOutcome> _launch(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return ok ? LaunchOutcome.opened : LaunchOutcome.unavailable;
    } catch (_) {
      return LaunchOutcome.failed;
    }
  }
}
