import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../components/chat_components.dart';
import '../../components/liquid_background.dart';
import '../../components/liquid_glass.dart';
import '../../components/menu_drawer.dart';
import '../../components/status_chips.dart';
import '../../controllers/bridge_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../models/bridge_models.dart';
import '../../routes/app_pages.dart';
import '../../theme/recodex_theme.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  static const double _headerReservedHeight = 142;

  final BridgeController controller = Get.find();
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _timelineBottomKey = GlobalKey();
  double _headerBackgroundProgress = 0;
  String _lastAutoScrollSignature = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateHeaderBackground);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateHeaderBackground)
      ..dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      Get.find<ThemeController>().fontScale.value;
      if (controller.events.isNotEmpty ||
          controller.currentSessionId.value != null) {
        _scheduleScrollToLatest(_timelineSignature);
      }
      final topInset = MediaQuery.paddingOf(context).top;
      final bottomInset = MediaQuery.paddingOf(context).bottom;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return LiquidBackground(
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          ),
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
              onPairing: () => _openPage(Routes.pairing),
              onSettings: () => _openPage(Routes.settings),
            ),
            body: Stack(
              children: [
                CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: SizedBox(height: _headerReservedHeight + topInset),
                    ),
                    if (controller.lastError.value.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _InlineError(
                          message: controller.lastError.value,
                          onDismiss: () => controller.lastError.value = '',
                        ),
                      ),
                    if (_gitChangeSummary != null)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(36, 26, 36, 0),
                        sliver: SliverToBoxAdapter(
                          child: GitChangeCard(
                            summary: _gitChangeSummary!,
                            onUndo: _confirmUndoChanges,
                          ),
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(36, 26, 36, 0),
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
                              onPairing: () => _openPage(Routes.pairing),
                            );
                          }
                          final entry = _timelineEntries[index];
                          if (entry.userEvent != null) {
                            return AssistantBubble(event: entry.userEvent!);
                          }
                          return AssistantAnswerBlock(
                            events: entry.events,
                            completed:
                                controller.currentSessionId.value == null,
                          );
                        },
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(key: _timelineBottomKey, height: 210),
                    ),
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: _HomeHeader(
                    title: _workspaceTitle,
                    subtitle: _workspaceSubtitle,
                    added: _changedFilesAdded,
                    removed: _changedFilesRemoved,
                    backgroundProgress: _headerBackgroundProgress,
                    topPadding: topInset,
                    onRefreshGit: controller.canUseWorkspace
                        ? () => controller.gitStatus(includeDiff: true)
                        : null,
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 20 + bottomInset,
                  child: ComposerBar(
                    controller: _promptController,
                    enabled: controller.canUseWorkspace,
                    context: controller.composerContext.value,
                    onSend: _sendPrompt,
                    onModelChanged: controller.setComposerModel,
                    onReasoningChanged: controller.setReasoningEffort,
                    onVoicePressed: _toggleVoiceInput,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  int get _timelineCount =>
      controller.events.isEmpty ? 1 : _timelineEntries.length;

  List<_TimelineEntry> get _timelineEntries {
    final entries = <_TimelineEntry>[];
    final answerEvents = <SessionEvent>[];

    void flushAnswer() {
      if (answerEvents.isEmpty) return;
      entries.add(_TimelineEntry.answer(List.of(answerEvents)));
      answerEvents.clear();
    }

    for (final event in controller.events) {
      if (event.kind == 'user') {
        flushAnswer();
        entries.add(_TimelineEntry.user(event));
      } else {
        answerEvents.add(event);
      }
    }
    flushAnswer();
    return entries;
  }

  String get _workspaceTitle {
    final workspace = controller.selectedWorkspace.value;
    if (workspace == null) return 'Recodex';
    final source = workspace.name.trim().isEmpty
        ? workspace.path
        : workspace.name;
    final title = _lastPathSegment(source);
    return title.isEmpty ? 'Recodex' : title;
  }

  String get _workspaceSubtitle {
    final workspace = controller.selectedWorkspace.value;
    if (workspace == null) return '';
    final path = workspace.path.trim();
    if (path.isEmpty || path == workspace.name.trim()) return '';
    return path;
  }

  int get _changedFilesAdded =>
      _parseChangedFileCounts(controller.gitSnapshot.value).$1;

  int get _changedFilesRemoved =>
      _parseChangedFileCounts(controller.gitSnapshot.value).$2;

  GitChangeSummary? get _gitChangeSummary {
    final snapshot = controller.gitSnapshot.value;
    if (snapshot == null) return null;
    return GitChangeSummary.tryParse(
      snapshot.numstat.isNotEmpty ? snapshot.numstat : snapshot.stat,
    );
  }

  String get _timelineSignature {
    final last = controller.events.isEmpty ? '' : controller.events.last.text;
    return '${controller.events.length}:${controller.currentSessionId.value}:$last';
  }

  void _updateHeaderBackground() {
    final next = (_scrollController.offset / 72).clamp(0.0, 1.0);
    if ((next - _headerBackgroundProgress).abs() < 0.02) return;
    setState(() => _headerBackgroundProgress = next);
  }

  void _scheduleScrollToLatest(String signature) {
    if (signature == _lastAutoScrollSignature) return;
    _lastAutoScrollSignature = signature;
    _scrollToLatestAfterLayout();
    Future<void>.delayed(
      const Duration(milliseconds: 80),
      _scrollToLatestAfterLayout,
    );
    Future<void>.delayed(
      const Duration(milliseconds: 180),
      _scrollToLatestAfterLayout,
    );
  }

  void _scrollToLatestAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final bottomContext = _timelineBottomKey.currentContext;
      if (bottomContext != null) {
        Scrollable.ensureVisible(
          bottomContext,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: 1,
        );
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _sendPrompt() {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;
    controller.startSession(prompt);
    _promptController.clear();
  }

  Future<void> _toggleVoiceInput() async {
    controller.lastError.value = '语音输入暂未启用。';
  }

  Future<void> _confirmUndoChanges() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤销当前修改？'),
        content: const Text('这会还原当前工作区中未提交的文件修改。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    controller.gitUndo(confirm: true);
  }

  void _openPage(String route) {
    if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
    Get.toNamed(route);
  }
}

class _TimelineEntry {
  const _TimelineEntry._({required this.events, this.userEvent});

  factory _TimelineEntry.user(SessionEvent event) {
    return _TimelineEntry._(events: const [], userEvent: event);
  }

  factory _TimelineEntry.answer(List<SessionEvent> events) {
    return _TimelineEntry._(events: events);
  }

  final List<SessionEvent> events;
  final SessionEvent? userEvent;
}

String _lastPathSegment(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  final normalized = trimmed.replaceAll('\\', '/');
  final parts = normalized
      .split('/')
      .where((part) => part.trim().isNotEmpty)
      .toList();
  return parts.isEmpty ? trimmed : parts.last;
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.title,
    required this.subtitle,
    required this.added,
    required this.removed,
    required this.backgroundProgress,
    required this.topPadding,
    required this.onRefreshGit,
  });

  final String title;
  final String subtitle;
  final int added;
  final int removed;
  final double backgroundProgress;
  final double topPadding;
  final VoidCallback? onRefreshGit;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.headerColor.withValues(
          alpha: 0.18 + backgroundProgress * 0.78,
        ),
        border: Border(
          bottom: BorderSide(
            color: colors.headerBorder.withValues(
              alpha: backgroundProgress * 0.52,
            ),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: colors.headerShadow.withValues(
              alpha: backgroundProgress * 0.11,
            ),
            offset: const Offset(0, 10),
            blurRadius: 24,
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(36, topPadding + 12, 24, 20),
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.headlineMedium?.copyWith(fontSize: 28),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.08,
                      ),
                    ),
                  ],
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
      ),
    );
  }
}

(int, int) _parseChangedFileCounts(GitSnapshot? snapshot) {
  if (snapshot == null) return (0, 0);
  var addedFiles = 0;
  var removedFiles = 0;
  final seenAdded = <String>{};
  final seenRemoved = <String>{};

  for (final line in snapshot.numstat.split('\n')) {
    final parts = line.split('\t');
    if (parts.length < 3) continue;
    final path = parts.sublist(2).join('\t').trim();
    if (path.isEmpty) continue;
    final added = int.tryParse(parts[0]) ?? 0;
    final removed = int.tryParse(parts[1]) ?? 0;
    if (added > 0 && seenAdded.add(path)) addedFiles += 1;
    if (removed > 0 && seenRemoved.add(path)) removedFiles += 1;
  }

  if (addedFiles != 0 || removedFiles != 0) return (addedFiles, removedFiles);

  for (final line in snapshot.status.split('\n')) {
    if (line.length < 3) continue;
    final code = line.substring(0, 2);
    final path = line.substring(3).trim();
    if (path.isEmpty) continue;
    final hasAddedChange =
        code.contains('A') || code.contains('M') || code.contains('?');
    final hasRemovedChange = code.contains('D');
    if (hasAddedChange && seenAdded.add(path)) addedFiles += 1;
    if (hasRemovedChange && seenRemoved.add(path)) removedFiles += 1;
  }

  return (addedFiles, removedFiles);
}

class _WelcomeTimeline extends StatelessWidget {
  const _WelcomeTimeline({
    required this.connected,
    required this.connectionLabel,
    required this.workspaceCount,
    required this.onPairing,
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

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onDismiss});

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
