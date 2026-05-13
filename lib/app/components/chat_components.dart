import 'package:flutter/material.dart';

import '../models/bridge_models.dart';
import 'liquid_glass.dart';

class AssistantBubble extends StatelessWidget {
  const AssistantBubble({required this.event, super.key});

  final SessionEvent event;

  @override
  Widget build(BuildContext context) {
    final isError = event.kind == 'error';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xffdfe9ff),
          ),
          child: Icon(
            isError ? Icons.warning_amber_rounded : Icons.smart_toy_outlined,
            color: const Color(0xff005fc7),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: LiquidGlass(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
            radius: 28,
            opacity: 0.66,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _eventTitle(event.kind),
                  style: TextStyle(
                    color: isError
                        ? const Color(0xffba1a1a)
                        : const Color(0xff1c1b1b),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  event.text.isEmpty ? '暂无输出' : event.text,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.62,
                    color: Color(0xff303132),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ToolCallRow extends StatelessWidget {
  const ToolCallRow({
    required this.title,
    required this.status,
    this.icon = Icons.check_circle_outline,
    super.key,
  });

  final String title;
  final String status;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 66),
      child: Row(
        children: [
          Icon(icon, size: 22, color: const Color(0xff747878)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xff747878),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            status,
            style: const TextStyle(
              color: Color(0xff747878),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class ComposerBar extends StatelessWidget {
  const ComposerBar({
    required this.controller,
    required this.enabled,
    required this.onSend,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      radius: 34,
      opacity: 0.82,
      child: Row(
        children: [
          IconButton(
            onPressed: enabled ? () {} : null,
            icon: const Icon(Icons.add),
            color: const Color(0xff202124),
            iconSize: 30,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '输入任务...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
            ),
          ),
          const Icon(Icons.bolt, color: Color(0xff747878), size: 22),
          const SizedBox(width: 6),
          const Text(
            'GPT-4',
            style: TextStyle(
              color: Color(0xff747878),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox.square(
            dimension: 56,
            child: FilledButton(
              onPressed: enabled ? onSend : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff005fc7),
                foregroundColor: Colors.white,
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
              ),
              child: const Icon(Icons.arrow_upward, size: 30),
            ),
          ),
        ],
      ),
    );
  }
}

String _eventTitle(String kind) {
  return switch (kind) {
    'error' => '执行出错',
    'interrupted' => '已中断',
    'done' => '任务完成',
    'tool' => '工具调用',
    _ => 'Codex',
  };
}
