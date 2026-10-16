import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../services/attachment_service.dart';
import '../state/app_state.dart';
import '../utils/formatters.dart';
import 'common.dart';

enum _AttachChoice { file, camera, gallery, placeholder }

/// Asks how to attach, then copies the file into the diary.
/// Returns the stored file, or null if the broker backed out.
Future<StoredAttachment?> pickAttachment(BuildContext context,
    {bool allowPlaceholder = false}) async {
  final choice = await showModalBottomSheet<_AttachChoice>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text('Attach a document',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('A copy is kept inside the diary, so it stays '
                'even if the original is deleted.'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('Choose a file'),
            subtitle: const Text('PDF, photo, Word…'),
            onTap: () => Navigator.pop(context, _AttachChoice.file),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            subtitle: const Text('Agreement page, ID, receipt'),
            onTap: () => Navigator.pop(context, _AttachChoice.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('From gallery'),
            onTap: () => Navigator.pop(context, _AttachChoice.gallery),
          ),
          if (allowPlaceholder)
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Still to collect'),
              subtitle: const Text('Add a reminder-style placeholder'),
              onTap: () => Navigator.pop(context, _AttachChoice.placeholder),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return null;
  if (choice == _AttachChoice.placeholder) {
    return const StoredAttachment(
        file: '', displayName: '', sizeKb: 0, kind: DocumentKind.other);
  }
  try {
    final service = AttachmentService.instance;
    return switch (choice) {
      _AttachChoice.file => await service.pickDocument(),
      _AttachChoice.camera => await service.pickPhoto(camera: true),
      _ => await service.pickPhoto(camera: false),
    };
  } catch (e) {
    if (context.mounted) showToast(context, 'Could not attach the file: $e');
    return null;
  }
}

/// Name, type and expiry for a newly attached file.
Future<DocumentRecord?> _describe(BuildContext context, StoredAttachment picked,
    {required bool placeholder}) {
  return showModalBottomSheet<DocumentRecord>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DescribeSheet(picked: picked, placeholder: placeholder),
  );
}

class _DescribeSheet extends StatefulWidget {
  const _DescribeSheet({required this.picked, required this.placeholder});

  final StoredAttachment picked;
  final bool placeholder;

  @override
  State<_DescribeSheet> createState() => _DescribeSheetState();
}

class _DescribeSheetState extends State<_DescribeSheet> {
  late final _name = TextEditingController(text: widget.picked.displayName);
  late DocumentKind _kind = widget.picked.kind;
  DateTime? _expiry;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.placeholder ? 'Document to collect' : 'About this file',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              autofocus: widget.placeholder,
              decoration: InputDecoration(
                labelText: widget.placeholder
                    ? 'What is needed, e.g. "Society NOC"'
                    : 'Name',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<DocumentKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final kind in DocumentKind.values)
                  DropdownMenuItem(value: kind, child: Text(kind.label)),
              ],
              onChanged: (v) => setState(() => _kind = v ?? _kind),
            ),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_busy_outlined),
              title: Text(_expiry == null
                  ? 'No expiry date'
                  : 'Expires ${formatDate(_expiry)}'),
              subtitle: const Text('You get a reminder a week before'),
              trailing: _expiry == null
                  ? const Icon(Icons.add)
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _expiry = null),
                    ),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _expiry ?? now.add(const Duration(days: 365)),
                  firstDate: now.subtract(const Duration(days: 365)),
                  lastDate: now.add(const Duration(days: 365 * 30)),
                );
                if (picked != null) setState(() => _expiry = picked);
              },
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                final name = _name.text.trim();
                Navigator.pop(
                  context,
                  DocumentRecord(
                    id: state.nextId('doc'),
                    name: name.isEmpty
                        ? (widget.placeholder ? 'Document to collect' : 'Untitled')
                        : name,
                    kind: _kind,
                    sizeKb: widget.picked.sizeKb,
                    file: widget.placeholder ? null : widget.picked.file,
                    missing: widget.placeholder,
                    expiryDate: _expiry,
                  ),
                );
              },
              child: Text(widget.placeholder ? 'Add to the list' : 'Attach'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Documents attached to one record, with an attach button.
class DocumentsSection extends StatelessWidget {
  const DocumentsSection({
    super.key,
    required this.kind,
    required this.id,
    this.title = 'Documents',
  });

  final EntityKind kind;
  final String id;
  final String title;

  Future<void> _attach(BuildContext context) async {
    final picked = await pickAttachment(context, allowPlaceholder: true);
    if (picked == null || !context.mounted) return;
    final doc = await _describe(context, picked, placeholder: picked.file.isEmpty);
    if (doc == null || !context.mounted) return;
    doc
      ..propertyId = kind == EntityKind.property ? id : null
      ..contactId = kind == EntityKind.contact ? id : null
      ..dealId = kind == EntityKind.deal ? id : null;
    context.read<AppState>().addDocument(doc);
    showToast(context, doc.missing ? '${doc.name} added to collect' : '${doc.name} attached',
        icon: Icons.attach_file);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final docs = state.documentsFor(kind, id);

    return DetailCard(
      title: '$title (${docs.length})',
      trailing: TextButton.icon(
        onPressed: () => _attach(context),
        icon: const Icon(Icons.upload_file, size: 18),
        label: const Text('Attach'),
      ),
      children: [
        if (docs.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('No files linked to this record yet.'),
          )
        else
          for (final doc in docs) DocumentTile(document: doc),
      ],
    );
  }
}

class DocumentTile extends StatelessWidget {
  const DocumentTile({super.key, required this.document, this.showLinks = false});

  final DocumentRecord document;
  final bool showLinks;

  Future<void> _open(BuildContext context) async {
    final error = await AttachmentService.instance.open(document.file);
    if (error != null && context.mounted) showToast(context, error);
  }

  Future<void> _share(BuildContext context) async {
    final f = AttachmentService.instance.fileFor(document.file);
    if (f == null) {
      showToast(context, 'The file is no longer on this phone.');
      return;
    }
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path, name: document.name)],
      subject: document.name,
    ));
  }

  Future<void> _collect(BuildContext context) async {
    final picked = await pickAttachment(context);
    if (picked == null || !context.mounted) return;
    context.read<AppState>().markDocumentCollected(document,
        file: picked.file, sizeKb: picked.sizeKb);
    showToast(context, '${document.name} collected',
        icon: Icons.check_circle_outline);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;

    final linkLabel = [
      if (document.propertyId != null) state.propertyTitle(document.propertyId),
      if (document.contactId != null) state.contactName(document.contactId),
      if (document.dealId != null) state.deal(document.dealId)?.title ?? '',
    ].where((e) => e.isNotEmpty).join(' · ');

    return ListTile(
      onTap: document.missing ? () => _collect(context) : () => _open(context),
      leading: CircleAvatar(
        backgroundColor: document.missing
            ? scheme.errorContainer
            : scheme.surfaceContainerHighest,
        child: Icon(
          document.missing ? Icons.help_outline : document.kind.icon,
          size: 20,
          color: document.missing ? scheme.onErrorContainer : null,
        ),
      ),
      title: Text(
        document.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: document.missing ? scheme.error : null,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            document.missing
                ? 'Still to collect — tap to attach'
                : '${document.kind.label} · ${formatBytes(document.sizeKb * 1024)} · '
                    '${formatDate(document.uploadedAt)}',
            style: const TextStyle(fontSize: 12),
          ),
          if (showLinks && linkLabel.isNotEmpty)
            Text(
              linkLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          if (document.expiryDate != null)
            Text(
              'Expires ${formatDate(document.expiryDate)}'
              '${document.isExpiringSoon ? ' — soon' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: document.isExpiringSoon
                    ? scheme.error
                    : scheme.onSurfaceVariant,
                fontWeight:
                    document.isExpiringSoon ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'open':
              _open(context);
            case 'share':
              _share(context);
            case 'collected':
              _collect(context);
            case 'delete':
              final trashId = state.deleteDocument(document.id);
              if (trashId != null) {
                showDeletedToast(context, document.name,
                    () => state.restoreFromTrash(trashId));
              }
          }
        },
        itemBuilder: (context) => [
          if (!document.missing) ...const [
            PopupMenuItem(value: 'open', child: Text('Open')),
            PopupMenuItem(value: 'share', child: Text('Share')),
          ],
          if (document.missing)
            const PopupMenuItem(
                value: 'collected', child: Text('Attach the file')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}
