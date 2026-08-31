import 'package:flutter/material.dart';

import '../../../components/chat_components.dart';
import '../../../models/bridge_models.dart';
import '../../../theme/recodex_theme.dart';

class WelcomeTimeline extends StatelessWidget {
  const WelcomeTimeline({
    required this.connected,
    required this.connectionLabel,
    required this.workspaceCount,
    required this.onPairing,
    super.key,
  });

  final bool connected;
  final String connectionLabel;
  final int workspaceCount;
  final VoidCallback onPairing;

  @override
  Widget build(BuildContext context) {
    final status = connected
        ? '已连接'
        : connectionLabel == 'reconnecting'
        ? '重连中'
        : '待命';
    final title = connected
        ? 'Relay 已连接，已加载 $workspaceCount 个工作区'
        : connectionLabel == 'connecting' || connectionLabel == 'auth'
        ? '正在连接 Relay'
        : connectionLabel == 'reconnecting'
        ? '正在重新连接 Relay'
        : '等待 Relay 连接';
    final icon = connected
        ? RecodexIcons.checkCircle
        : connectionLabel == 'connecting' ||
              connectionLabel == 'auth' ||
              connectionLabel == 'reconnecting'
        ? RecodexIcons.sync
        : RecodexIcons.circle;

    return Column(
      children: [
        AssistantBubble(
          event: SessionEvent(
            kind: 'message',
            text: '我已准备好在当前工作区执行任务。你可以直接描述要改的功能、要排查的问题，或让我先检查项目和 Git 状态。',
          ),
        ),
        const SizedBox(height: 26),
        ToolCallRow(
          title: title,
          status: status,
          icon: icon,
          onTap: connected ? null : onPairing,
        ),
      ],
    );
  }
}
