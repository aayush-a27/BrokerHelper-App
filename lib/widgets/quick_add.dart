import 'package:flutter/material.dart';

import '../screens/contact_form_screen.dart';
import '../screens/deal_form_screen.dart';
import '../screens/lead_form_screen.dart';
import '../screens/property_form_screen.dart';
import '../screens/task_form_screen.dart';
import '../screens/visit_form_screen.dart';
import '../theme.dart';
import 'voice_capture_sheet.dart';

/// The "+ Add" action the report asks to keep visible on every main screen
/// (p. 6). One tap opens the sheet, a second tap is on the form.
class QuickAddFab extends StatelessWidget {
  const QuickAddFab({super.key, this.extended = false});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    // HomeShell keeps every tab alive in an IndexedStack, so several FABs are
    // mounted at once. Without a null hero tag they all claim Flutter's
    // default one and any route transition throws.
    if (extended) {
      return FloatingActionButton.extended(
        key: const Key('quick-add-fab'),
        heroTag: null,
        onPressed: () => showQuickAddSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      );
    }
    return FloatingActionButton(
      key: const Key('quick-add-fab'),
      heroTag: null,
      onPressed: () => showQuickAddSheet(context),
      tooltip: 'Quick add',
      child: const Icon(Icons.add),
    );
  }
}

/// Opens the five-option quick-add sheet.
Future<void> showQuickAddSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    // Seven options do not fit the default half-height sheet on a small
    // phone, so let it grow and scroll.
    isScrollControlled: true,
    builder: (sheetContext) => _QuickAddSheet(parentContext: context),
  );
}

class _QuickAddSheet extends StatelessWidget {
  const _QuickAddSheet({required this.parentContext});

  /// The screen that opened the sheet — forms are pushed onto its navigator
  /// so they survive the sheet closing.
  final BuildContext parentContext;

  void _open(BuildContext sheetContext, Widget screen) {
    Navigator.pop(sheetContext);
    Navigator.of(parentContext).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  Future<void> _dictateLead(BuildContext sheetContext) async {
    Navigator.pop(sheetContext);
    final capture = await showVoiceCaptureSheet(parentContext);
    if (capture == null || !parentContext.mounted) return;
    await Navigator.of(parentContext).push(
      MaterialPageRoute<void>(
        builder: (_) => LeadFormScreen(prefill: capture),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              'Quick add',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Capture it now, fill in the rest later.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          _QuickAddTile(
            key: const Key('quick-add-lead'),
            icon: Icons.person_add_alt_1_outlined,
            title: 'Lead',
            subtitle: 'A new enquiry from a call, portal or referral',
            onTap: () => _open(context, const LeadFormScreen()),
          ),
          _QuickAddTile(
            key: const Key('quick-add-contact'),
            icon: Icons.contacts_outlined,
            title: 'Contact',
            subtitle: 'A buyer or seller to keep on file',
            onTap: () => _open(context, const ContactFormScreen()),
          ),
          _QuickAddTile(
            key: const Key('quick-add-property'),
            icon: Icons.home_work_outlined,
            title: 'Property',
            subtitle: 'Add a unit to your inventory',
            onTap: () => _open(context, const PropertyFormScreen()),
          ),
          _QuickAddTile(
            key: const Key('quick-add-task'),
            icon: Icons.task_alt,
            title: 'Task / follow-up',
            subtitle: 'A reminder so the next action is not missed',
            onTap: () => _open(context, const TaskFormScreen()),
          ),
          _QuickAddTile(
            key: const Key('quick-add-visit'),
            icon: Icons.event_outlined,
            title: 'Site visit',
            subtitle: 'Book a viewing and set a reminder',
            onTap: () => _open(context, const VisitFormScreen()),
          ),
          const Divider(height: 24),
          _QuickAddTile(
            key: const Key('quick-add-deal'),
            icon: Icons.handshake_outlined,
            title: 'Deal',
            subtitle: 'Record a transaction and its commission',
            onTap: () => _open(context, const DealFormScreen()),
          ),
          _QuickAddTile(
            key: const Key('quick-add-voice'),
            icon: Icons.mic_none,
            title: 'Dictate a lead',
            subtitle: 'Voice-to-record (simulated)',
            tint: AppTheme.accent,
              onTap: () => _dictateLead(context),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _QuickAddTile extends StatelessWidget {
  const _QuickAddTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tint,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? Theme.of(context).colorScheme.primary;
    return ListTile(
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}
