import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/share_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'common.dart';

/// Pick a template, check the filled-in message, then hand it to WhatsApp.
/// Nothing is sent by the app — WhatsApp opens with the text pre-filled.
Future<void> showWhatsAppSheet(
  BuildContext context, {
  required String phone,
  Lead? lead,
  Contact? contact,
  Property? property,
  DateTime? visitAt,
  String? initialTemplateId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _WhatsAppSheet(
      phone: phone,
      lead: lead,
      contact: contact,
      property: property,
      visitAt: visitAt,
      initialTemplateId: initialTemplateId,
    ),
  );
}

class _WhatsAppSheet extends StatefulWidget {
  const _WhatsAppSheet({
    required this.phone,
    this.lead,
    this.contact,
    this.property,
    this.visitAt,
    this.initialTemplateId,
  });

  final String phone;
  final Lead? lead;
  final Contact? contact;
  final Property? property;
  final DateTime? visitAt;
  final String? initialTemplateId;

  @override
  State<_WhatsAppSheet> createState() => _WhatsAppSheetState();
}

class _WhatsAppSheetState extends State<_WhatsAppSheet> {
  final _message = TextEditingController();
  late MessageTemplate _template;
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    _template = whatsAppTemplates.firstWhere(
      (t) => t.id == widget.initialTemplateId,
      orElse: () => widget.property != null
          ? whatsAppTemplates.first
          : whatsAppTemplates[2],
    );
    _message.text = _render(_template);
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  String _render(MessageTemplate template) {
    final state = context.read<AppState>();
    return template.render(templateValues(
      lead: widget.lead,
      contact: widget.contact,
      property: widget.property,
      broker: state.profile,
      visitAt: widget.visitAt,
    ));
  }

  void _select(MessageTemplate template) {
    setState(() {
      _template = template;
      _message.text = _render(template);
      _edited = false;
    });
  }

  Future<void> _send() async {
    const service = ShareService();
    final outcome = await service.openWhatsApp(
      phone: widget.phone,
      message: _message.text,
    );
    if (!mounted) return;
    final state = context.read<AppState>();
    final who = widget.lead?.name ?? widget.contact?.name ?? widget.phone;

    switch (outcome) {
      case LaunchOutcome.opened:
        state.recordActivity('WhatsApp opened', 'Message prepared for $who',
            EntityKind.contact, widget.contact?.id);
        if (mounted) Navigator.pop(context);
      case LaunchOutcome.unavailable:
      case LaunchOutcome.failed:
        await Clipboard.setData(ClipboardData(text: _message.text));
        if (!mounted) return;
        showToast(
          context,
          'WhatsApp is not available here — the message was copied to the '
          'clipboard instead.',
          icon: Icons.content_copy,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.chat_outlined, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Send on WhatsApp',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ],
              ),
              Gap.xs,
              Text(
                'To ${widget.phone}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              Gap.m,
              Text('Template', style: Theme.of(context).textTheme.labelLarge),
              Gap.s,
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final template in whatsAppTemplates)
                    ChoiceChip(
                      label: Text(template.title),
                      selected: template.id == _template.id,
                      onSelected: (_) => _select(template),
                    ),
                ],
              ),
              Gap.m,
              TextField(
                controller: _message,
                maxLines: 7,
                onChanged: (_) => setState(() => _edited = true),
                decoration: const InputDecoration(
                  labelText: 'Message',
                  alignLabelWithHint: true,
                ),
              ),
              Gap.s,
              Text(
                _edited
                    ? 'Edited — the template is unchanged.'
                    : 'Placeholders were filled in from this record.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              Gap.m,
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: _message.text));
                        if (context.mounted) {
                          showToast(context, 'Message copied',
                              icon: Icons.content_copy);
                        }
                      },
                      icon: const Icon(Icons.content_copy, size: 18),
                      label: const Text('Copy'),
                    ),
                  ),
                  Gap.m,
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _send,
                      icon: const Icon(Icons.send, size: 18),
                      label: const Text('Open WhatsApp'),
                    ),
                  ),
                ],
              ),
              Gap.s,
            ],
          ),
        ),
      ),
    );
  }
}

/// Call / WhatsApp / SMS row used on lead, contact and deal detail screens.
class QuickContactActions extends StatelessWidget {
  const QuickContactActions({
    super.key,
    required this.phone,
    this.lead,
    this.contact,
    this.property,
  });

  final String phone;
  final Lead? lead;
  final Contact? contact;
  final Property? property;

  @override
  Widget build(BuildContext context) {
    const service = ShareService();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () async {
                final outcome = await service.call(phone);
                if (outcome != LaunchOutcome.opened && context.mounted) {
                  showToast(context, 'No dialler available on this device',
                      icon: Icons.info_outline);
                }
              },
              icon: const Icon(Icons.call, size: 18),
              label: const Text('Call'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () => showWhatsAppSheet(
                context,
                phone: phone,
                lead: lead,
                contact: contact,
                property: property,
              ),
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: const Text('WhatsApp'),
            ),
          ),
        ],
      ),
    );
  }
}
