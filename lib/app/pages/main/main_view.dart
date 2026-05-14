import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../components/chat_components.dart';
import '../../components/liquid_background.dart';
import '../../components/menu_drawer.dart';
import '../../models/bridge_models.dart';
import '../../routes/app_pages.dart';
import '../settings/theme_controller.dart';
import 'bridge_controller.dart';
import 'git_diff_view.dart';
import 'widget/home_header.dart';
import 'widget/inline_error.dart';
import 'widget/main_helpers.dart';
import 'widget/welcome_timeline.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  static const double _headerReservedHeight = 142;
  static const Curve _composerDampedCurve = Cubic(0.18, 0.89, 0.32, 1.08);

  final BridgeController controller = Get.find();
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _timelineBottomKey = GlobalKey();
  double _headerBackgroundProgress = 0;
  bool _composerVisible = true;
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
      final mediaQuery = MediaQuery.of(context);
      final topInset = mediaQuery.padding.top;
      final bottomInset = mediaQuery.padding.bottom;
      final composerSlideDuration = mediaQuery.disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 430);
      final composerFadeDuration = mediaQuery.disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 300);
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
                NotificationListener<UserScrollNotification>(
                  onNotification: _handleUserScroll,
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: _headerReservedHeight + topInset,
                        ),
                      ),
                      if (controller.lastError.value.isNotEmpty)
                        SliverToBoxAdapter(
                          child: InlineError(
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
                              onFileTap: _openGitDiff,
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
                              return WelcomeTimeline(
                                connected: controller.connected.value,
                                connectionLabel:
                                    controller.connectionLabel.value,
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
                              onGitFileTap: _openGitDiff,
                            );
                          },
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(key: _timelineBottomKey, height: 210),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: HomeHeader(
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
                  bottom: 2 + bottomInset,
                  child: IgnorePointer(
                    ignoring: !_composerVisible,
                    child: AnimatedSlide(
                      offset: _composerVisible
                          ? Offset.zero
                          : const Offset(0, 1.28),
                      duration: composerSlideDuration,
                      curve: _composerDampedCurve,
                      child: AnimatedOpacity(
                        opacity: _composerVisible ? 1 : 0,
                        duration: composerFadeDuration,
                        curve: Curves.easeOutCubic,
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
                    ),
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
    final title = lastPathSegment(source);
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
      parseChangedFileCounts(controller.gitSnapshot.value).$1;

  int get _changedFilesRemoved =>
      parseChangedFileCounts(controller.gitSnapshot.value).$2;

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

  bool _handleUserScroll(UserScrollNotification notification) {
    if (notification.depth != 0) return false;
    final shouldShow = switch (notification.direction) {
      ScrollDirection.forward => false,
      ScrollDirection.reverse => false,
      ScrollDirection.idle => true,
    };
    if (shouldShow != _composerVisible) {
      setState(() => _composerVisible = shouldShow);
    }
    return false;
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

  void _openGitDiff(GitFileChange file) {
    Get.toNamed(
      Routes.gitDiff,
      arguments: GitDiffPageArgs(
        snapshot: controller.gitSnapshot.value,
        selectedPath: file.path,
      ),
    );
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
