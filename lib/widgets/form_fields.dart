import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../utils/formatters.dart';

/// Shared field widgets. The report asks for minimal typing, so every field
/// here is generously sized and the pickers do the work wherever possible.

class FormSection extends StatelessWidget {
  const FormSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        ...children,
      ],
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.maxLines = 1,
    this.prefixIcon,
    this.suffix,
    this.validator,
    this.textCapitalization = TextCapitalization.sentences,
    this.inputFormatters,
    this.autofocus = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final int maxLines;
  final IconData? prefixIcon;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator,
        autofocus: autofocus,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
          suffixIcon: suffix,
        ),
      ),
    );
  }
}

/// A money field that shows the amount in words as the broker types, so a
/// stray zero is obvious before saving.
class MoneyField extends StatefulWidget {
  const MoneyField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;

  @override
  State<MoneyField> createState() => _MoneyFieldState();
}

class _MoneyFieldState extends State<MoneyField> {
  @override
  Widget build(BuildContext context) {
    final raw = double.tryParse(widget.controller.text.replaceAll(',', '')) ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: widget.controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: widget.label,
          prefixText: '₹ ',
          helperText: raw > 0 ? formatMoney(raw) : widget.helper,
        ),
      ),
    );
  }
}

class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
    this.icon,
  });

  final String label;
  final T value;
  final List<T> items;
  final String Function(T) labelBuilder;
  final ValueChanged<T?> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon == null ? null : Icon(icon),
        ),
        items: [
          for (final item in items)
            DropdownMenuItem<T>(
              value: item,
              child: Text(labelBuilder(item), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

/// A horizontal row of choice chips — faster than a dropdown for short lists
/// and much better on a phone.
class ChipPicker<T> extends StatelessWidget {
  const ChipPicker({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
    this.colorBuilder,
  });

  final String label;
  final T value;
  final List<T> items;
  final String Function(T) labelBuilder;
  final ValueChanged<T> onChanged;
  final Color Function(T)? colorBuilder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          Gap.s,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in items)
                ChoiceChip(
                  label: Text(labelBuilder(item)),
                  selected: item == value,
                  selectedColor:
                      colorBuilder?.call(item).withValues(alpha: 0.18),
                  onSelected: (_) => onChanged(item),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tile that opens a date (and optionally time) picker.
class DateTimeField extends StatelessWidget {
  const DateTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.includeTime = true,
    this.icon = Icons.event_outlined,
    this.clearable = false,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool includeTime;
  final IconData icon;
  final bool clearable;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
    );
    if (date == null) return;
    if (!includeTime) {
      onChanged(DateTime(date.year, date.month, date.day, 9));
      return;
    }
    if (!context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value ?? now),
    );
    onChanged(DateUtilsX.combine(date, time?.hour ?? 10, time?.minute ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _pick(context),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            suffixIcon: clearable && value != null
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear',
                    onPressed: () => onChanged(null),
                  )
                : const Icon(Icons.edit_calendar_outlined),
          ),
          child: Text(
            value == null
                ? 'Not set'
                : includeTime
                    ? '${formatDate(value)} · ${formatTime(value)}'
                    : formatDate(value),
            style: TextStyle(
              fontSize: 16,
              color: value == null ? scheme.onSurfaceVariant : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens a searchable single-select list — used for picking a property,
/// contact or broker without typing.
Future<T?> showRecordPicker<T>({
  required BuildContext context,
  required String title,
  required List<T> items,
  required String Function(T) titleBuilder,
  String Function(T)? subtitleBuilder,
  Widget Function(T)? leadingBuilder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _RecordPicker<T>(
      title: title,
      items: items,
      titleBuilder: titleBuilder,
      subtitleBuilder: subtitleBuilder,
      leadingBuilder: leadingBuilder,
    ),
  );
}

class _RecordPicker<T> extends StatefulWidget {
  const _RecordPicker({
    required this.title,
    required this.items,
    required this.titleBuilder,
    this.subtitleBuilder,
    this.leadingBuilder,
  });

  final String title;
  final List<T> items;
  final String Function(T) titleBuilder;
  final String Function(T)? subtitleBuilder;
  final Widget Function(T)? leadingBuilder;

  @override
  State<_RecordPicker<T>> createState() => _RecordPickerState<T>();
}

class _RecordPickerState<T> extends State<_RecordPicker<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final filtered = widget.items.where((item) {
      if (q.isEmpty) return true;
      final haystack =
          '${widget.titleBuilder(item)} ${widget.subtitleBuilder?.call(item) ?? ''}'
              .toLowerCase();
      return haystack.contains(q);
    }).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop<T>(context),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  autofocus: false,
                  decoration: const InputDecoration(
                    hintText: 'Search',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('Nothing matches that search'))
                    : ListView.separated(
                        padding: const EdgeInsets.only(top: 8, bottom: 24),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final item = filtered[i];
                          return ListTile(
                            leading: widget.leadingBuilder?.call(item),
                            title: Text(widget.titleBuilder(item)),
                            subtitle: widget.subtitleBuilder == null
                                ? null
                                : Text(widget.subtitleBuilder!(item)),
                            onTap: () => Navigator.pop<T>(context, item),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Read-only tile that opens a picker, showing the current selection.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.icon,
    this.onClear,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;
  final IconData? icon;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = value == null || value!.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: icon == null ? null : Icon(icon),
            suffixIcon: !empty && onClear != null
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear',
                    onPressed: onClear,
                  )
                : const Icon(Icons.unfold_more),
          ),
          child: Text(
            empty ? 'Tap to choose' : value!,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              color: empty ? scheme.onSurfaceVariant : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

String? requiredField(String? value, [String field = 'This field']) =>
    (value == null || value.trim().isEmpty) ? '$field is required' : null;

String? phoneField(String? value) {
  if (value == null || value.trim().isEmpty) return 'Phone number is required';
  final digits = value.replaceAll(RegExp(r'\D'), '');
  return digits.length < 10 ? 'Enter at least 10 digits' : null;
}
