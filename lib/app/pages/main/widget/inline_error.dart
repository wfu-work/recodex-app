import 'package:flutter/material.dart';

import '../../../components/liquid_glass.dart';
import '../../../theme/recodex_theme.dart';

class InlineError extends StatelessWidget {
  const InlineError({
    required this.message,
    required this.onDismiss,
    super.key,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 8, 36, 0),
      child: LiquidGlass(
        radius: 24,
        opacity: 0.78,
        padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: colors.error),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            IconButton(onPressed: onDismiss, icon: const Icon(Icons.close)),
          ],
        ),
      ),
    );
  }
}
