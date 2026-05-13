import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../components/chat_components.dart';
import '../components/liquid_background.dart';
import '../components/liquid_glass.dart';
import '../components/menu_drawer.dart';
import '../components/status_chips.dart';
import '../controllers/bridge_controller.dart';
import '../models/bridge_models.dart';
import 'about_page.dart';
import 'settings_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final BridgeController controller = Get.find();
  final TextEditingController _promptController = TextEditingController();

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => LiquidBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          drawer: RemodexDrawer(
            connected: controller.connected.value,
            workspaces: controller.workspaces,
            selectedWorkspace: controller.selectedWorkspace.value,
            onSelectWorkspace: (workspace) {
              controller.selectWorkspace(workspace);
              Navigator.of(context).pop();
            },
            onSettings: () => _openPage(const SettingsPage()),
            onAbout: () => _openPage(const AboutPage()),
          ),
          body: SafeArea(
            child: Stack(
              children: [
                CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _HomeHeader(
                        path: _workspacePath,
                        added: _diffAdded,
                        removed: _diffRemoved,
                        onRefreshGit: controller.canUseWorkspace
                            ? () => controller.gitStatus(includeDiff: true)
                            : null,
                      ),
                    ),
                    if (controller.lastError.value.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _InlineError(
                          message: controller.lastError.value,
                          onDismiss: () => controller.lastError.value = '',
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(36, 26, 36, 140),
                      sliver: SliverList.separated(
                        itemCount: _timelineCount,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 26),
                        itemBuilder: (context, index) {
                          if (controller.events.isEmpty) {
                            return _WelcomeTimeline(
                              connected: controller.connected.value,
                              connectionLabel: controller.connectionLabel.value,
                              workspaceCount: controller.workspaces.length,
                            );
                          }
                          final event = controller.events[index];
                          if (event.kind == 'tool') {
                            return ToolCallRow(title: event.text, status: '完成');
                          }
                          return AssistantBubble(event: event);
                        },
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 36,
                  right: 36,
                  bottom: 20,
                  child: ComposerBar(
                    controller: _promptController,
                    enabled: controller.canUseWorkspace,
                    onSend: _sendPrompt,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int get _timelineCount =>
      controller.events.isEmpty ? 1 : controller.events.length;

  String get _workspacePath {
    final workspace = controller.selectedWorkspace.value;
    if (workspace == null) return '未选择工作区';
    return workspace.path.isEmpty ? workspace.name : workspace.path;
  }

  int get _diffAdded => _parseDiffStat(controller.gitSnapshot.value?.stat).$1;

  int get _diffRemoved => _parseDiffStat(controller.gitSnapshot.value?.stat).$2;

  void _sendPrompt() {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;
    controller.startSession(prompt);
    _promptController.clear();
  }

  void _openPage(Widget page) {
    if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.path,
    required this.added,
    required this.removed,
    required this.onRefreshGit,
  });

  final String path;
  final int added;
  final int removed;
  final VoidCallback? onRefreshGit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 32, 24, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Builder(
            builder: (context) => LiquidIconButton(
              icon: Icons.menu,
              tooltip: '菜单',
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Remodex',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 34,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  path,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xff747878),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.08,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onRefreshGit,
            child: DiffChip(added: added, removed: removed),
          ),
        ],
      ),
    );
  }
}

(int, int) _parseDiffStat(String? stat) {
  if (stat == null || stat.trim().isEmpty) return (0, 0);
  var added = 0;
  var removed = 0;
  for (final line in stat.split('\n')) {
    final insertions = RegExp(r'(\d+)\s+insertion').firstMatch(line);
    final deletions = RegExp(r'(\d+)\s+deletion').firstMatch(line);
    if (insertions != null) {
      added += int.tryParse(insertions.group(1) ?? '') ?? 0;
    }
    if (deletions != null) {
      removed += int.tryParse(deletions.group(1) ?? '') ?? 0;
    }
  }
  return (added, removed);
}

class _WelcomeTimeline extends StatelessWidget {
  const _WelcomeTimeline({
    required this.connected,
    required this.connectionLabel,
    required this.workspaceCount,
  });

  final bool connected;
  final String connectionLabel;
  final int workspaceCount;

  @override
  Widget build(BuildContext context) {
    final status = connected
        ? '已连接'
        : connectionLabel == 'reconnecting'
        ? '重连中'
        : '待命';
    final title = connected
        ? 'Bridge 已连接，已加载 $workspaceCount 个工作区'
        : connectionLabel == 'connecting' || connectionLabel == 'auth'
        ? '正在连接本地 Bridge'
        : connectionLabel == 'reconnecting'
        ? '正在重新连接本地 Bridge'
        : '等待本地 Bridge 连接';
    final icon = connected
        ? Icons.check_circle_outline
        : connectionLabel == 'connecting' ||
              connectionLabel == 'auth' ||
              connectionLabel == 'reconnecting'
        ? Icons.sync
        : Icons.radio_button_unchecked;

    return Column(
      children: [
        AssistantBubble(
          event: SessionEvent(
            kind: 'message',
            text: '选择一个工作区，然后输入任务。你可以让我分析项目结构、修改代码、运行测试，或在提交前检查 Git 状态。',
          ),
        ),
        const SizedBox(height: 26),
        ToolCallRow(title: title, status: status, icon: icon),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 8, 36, 0),
      child: LiquidGlass(
        radius: 24,
        opacity: 0.78,
        padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xffba1a1a)),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            IconButton(onPressed: onDismiss, icon: const Icon(Icons.close)),
          ],
        ),
      ),
    );
  }
}
