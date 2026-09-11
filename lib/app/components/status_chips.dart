import 'package:flutter/material.dart';

import '../theme/recodex_theme.dart';

class DiffChip extends StatelessWidget {
  const DiffChip({
    required this.changedFiles,
    required this.added,
    required this.removed,
    super.key,
  });

  final int changedFiles;
  final int added;
  final int removed;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final isClean = changedFiles == 0 && added == 0 && removed == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceOverlay,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.glassBorder),
      ),
      child: isClean
          ? Text(
              'Clean',
              style: TextStyle(
                color: colors.success,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$changedFiles changed',
                  maxLines: 1,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '+$added',
                        style: TextStyle(color: colors.success),
                      ),
                      TextSpan(
                        text: '  -$removed',
                        style: TextStyle(color: colors.error),
                      ),
                    ],
                  ),
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.05,
                  ),
                ),
              ],
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
        _ConnectionLight(color: connected ? colors.success : colors.textMuted),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: TextStyle(
              fontSize: 12,
              color: colors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// An explicit connection state for service and settings rows.
class ConnectionStatusBadge extends StatelessWidget {
  const ConnectionStatusBadge({required this.connected, super.key});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final color = connected ? colors.success : colors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: connected ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ConnectionLight(color: color),
          const SizedBox(width: 6),
          Text(
            connected ? '在线' : '未连接',
            style: TextStyle(
              color: color,
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionLight extends StatelessWidget {
  const _ConnectionLight({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
