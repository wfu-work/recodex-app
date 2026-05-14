import 'package:flutter/material.dart';

import '../theme/recodex_theme.dart';

class DiffChip extends StatelessWidget {
  const DiffChip({required this.added, required this.removed, super.key});

  final int added;
  final int removed;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceOverlay,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.glassBorder),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '+$added',
              style: TextStyle(color: colors.icon),
            ),
            const TextSpan(text: '  '),
            TextSpan(
              text: '-$removed',
              style: TextStyle(color: colors.error),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class ConnectionDot extends StatelessWidget {
  const ConnectionDot({
    required this.connected,
    required this.label,
    super.key,
  });

  final bool connected;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.circle,
          size: 8,
          color: connected ? colors.success : colors.textMuted,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: colors.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
