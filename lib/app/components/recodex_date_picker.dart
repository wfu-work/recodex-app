import 'package:flutter/material.dart';

import '../theme/recodex_theme.dart';

/// A compact, content-sized date selector used across settings and reports.
/// The trigger follows the same glass surface, border, and typography as the
/// other Recodex controls while keeping the platform date dialog accessible.
class RecodexDatePicker extends StatelessWidget {
  const RecodexDatePicker({
    required this.value,
    required this.firstDate,
    required this.lastDate,
    required this.onChanged,
    this.label,
    this.placeholder = '选择日期',
    this.enabled = true,
    this.tooltip = '选择日期',
    super.key,
  });

  final DateTime? value;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onChanged;
  final String? label;
  final String placeholder;
  final bool enabled;
  final String tooltip;

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  Future<void> _pick(BuildContext context) async {
    final first = _day(firstDate);
    final last = _day(lastDate);
    var initial = _day(value ?? last);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final colors = context.recodexColors;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      builder: (context, child) {
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            datePickerTheme: theme.datePickerTheme.copyWith(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              headerBackgroundColor: colors.surfaceOverlay,
              headerForegroundColor: colors.text,
              dayForegroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? theme.colorScheme.onPrimary
                    : colors.text,
              ),
              todayForegroundColor: WidgetStatePropertyAll(colors.text),
              todayBorder: BorderSide(color: colors.glassBorder),
              dividerColor: colors.glassBorder,
            ),
          ),
          child: child!,
        );
      },
    );
    if (selected != null) onChanged(_day(selected));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final theme = Theme.of(context);
    final hasValue = value != null;
    final radius = BorderRadius.circular(12);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          RecodexIcons.calendar,
          size: 17,
          color: hasValue ? theme.colorScheme.primary : colors.textMuted,
        ),
        const SizedBox(width: 8),
        if (label != null) ...[
          Text(label!, style: TextStyle(color: colors.textMuted, fontSize: 12)),
          const SizedBox(width: 8),
        ],
        Text(
          hasValue ? _formatDate(value!) : placeholder,
          style: TextStyle(
            color: hasValue ? colors.text : colors.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        Icon(RecodexIcons.chevronDown, size: 16, color: colors.textMuted),
      ],
    );
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? () => _pick(context) : null,
            borderRadius: radius,
            child: Ink(
              decoration: BoxDecoration(
                color: colors.surfaceOverlay.withValues(alpha: 0.72),
                borderRadius: radius,
                border: Border.all(color: colors.glassBorder),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
