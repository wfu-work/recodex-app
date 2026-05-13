import 'package:flutter/material.dart';

class DiffChip extends StatelessWidget {
  const DiffChip({required this.added, required this.removed, super.key});

  final int added;
  final int removed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '+$added',
              style: const TextStyle(color: Color(0xff0069c7)),
            ),
            const TextSpan(text: '  '),
            TextSpan(
              text: '-$removed',
              style: const TextStyle(color: Color(0xffb00020)),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.circle,
          size: 8,
          color: connected ? const Color(0xff0a8f43) : const Color(0xffa2a7ae),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xff747878),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
