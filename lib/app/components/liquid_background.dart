import 'package:flutter/material.dart';

import '../theme/recodex_theme.dart';

class LiquidBackground extends StatelessWidget {
  const LiquidBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return ColoredBox(color: colors.backgroundGradient.first, child: child);
  }
}
