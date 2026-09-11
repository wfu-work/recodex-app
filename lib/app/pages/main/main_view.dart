import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../components/chat_components.dart';
import '../../components/liquid_background.dart';
import '../../components/menu_drawer.dart';
import '../../models/bridge_models.dart';
import '../../services/timeline_events.dart';
import '../../routes/app_pages.dart';
import '../../theme/recodex_theme.dart';
import '../pairing/pairing_view.dart';
import '../settings/settings_preferences_controller.dart';
import '../settings/theme_controller.dart';
import 'bridge_controller.dart';
import 'git_diff_view.dart';
import 'widget/home_header.dart';
import 'widget/inline_error.dart';
import 'widget/pending_interaction_card.dart';
import 'widget/main_helpers.dart';
import 'widget/task_output_dialog.dart';
import 'widget/scroll_to_latest_button.dart';
import 'widget/timeline_load_state.dart';
import 'widget/welcome_timeline.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  static const double _headerReservedHeight = 142;
  static const double _composerReservedHeight = 286;
  static const double _scrollToLatestThreshold = 132;
  // Keep the jump-to-latest affordance close to the composer. The previous
  // offset left an unnecessarily large dead zone between the control and the
  // input surface, especially on compact windows.
  static const double _scrollToLatestBottom = 154;
  static const Curve _composerDampedCurve = Cubic(0.18, 0.89, 0.32, 1.08);

  final BridgeController controller = Get.find();
  final TextEditingController _promptController = TextEditingController();
  final FocusNode _composerFocusNode = FocusNode(debugLabel: 'composer');
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _timelineBottomKey = GlobalKey();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final List<GlobalKey> _timelineEntryKeys = <GlobalKey>[];
  double _headerBackgroundProgress = 0;
  bool _composerVisible = true;
  final _drafts = <String, String>{};
  late Worker _draftTaskWorker;
  late Worker _draftHostWorker;
  String _draftKey = '';
  bool _sendingSupplement = false;

  String get _currentDraftKey => '${controller.activePairingId.value}:${controller.selectedSessionId.value ?? 'new'}';

  void _switchDraft() {
    final next = _currentDraftKey;
    if (next == _draftKey) return;
    _drafts[_draftKey] = _promptController.text;
    _draftKey = next;
    _promptController.text = _drafts[next] ?? '';
  }
  bool _drawerOpen = false;
  bool _showScrollToLatest = false;
  bool _userDetachedFromLatest = false;
  bool? _lastAutoScrollEnabled;
  String _lastAutoScrollSignature = '';
  bool _scrollUiUpdateScheduled = false;
  double? _pendingHeaderProgress;
  bool? _pendingScrollToLatest;
  bool? _pendingComposerVisible;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateHeaderBackground);
    _scrollController.addListener(_updateScrollToLatestVisibility);
    _draftKey = _currentDraftKey;
    _draftTaskWorker = ever(controller.selectedSessionId, (_) => _switchDraft());
    _draftHostWorker = ever(controller.activePairingId, (_) => _switchDraft());
    controller.startLiveTimelineRefresh();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateHeaderBackground)
      ..removeListener(_updateScrollToLatestVisibility)
      ..dispose();
    controller.stopLiveTimelineRefresh();
    _draftTaskWorker.dispose();
    _draftHostWorker.dispose();
    _promptController.dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final themeController = Get.find<ThemeController>();
      themeController.fontScale.value;
      // Subscribe to the controller's one-second lifecycle ticker so an
      // in-progress turn's elapsed duration keeps updating even when the
      // user's auto-scroll preference is disabled.
      controller.timelineClock.value;
      final settingsPreferences =
          Get.isRegistered<SettingsPreferencesController>()
          ? Get.find<SettingsPreferencesController>()
          : null;
      final compactTimeline =
          settingsPreferences?.compactTimeline.value ?? false;
      final shortcutsEnabled =
          settingsPreferences?.shortcutsEnabled.value ?? true;
      final showConversationIndex =
          settingsPreferences?.showConversationIndex.value ?? true;
      final autoScrollToLatest =
          settingsPreferences?.autoScrollToLatest.value ?? true;
      final showReasoning = settingsPreferences?.showReasoning.value ?? true;
      final collapseReasoningByDefault =
          settingsPreferences?.collapseReasoningByDefault.value ?? true;
      final showToolCallDetails =
          settingsPreferences?.showToolCallDetails.value ?? true;
      final showUsageMetrics =
          settingsPreferences?.showUsageMetrics.value ?? true;
      final compactSidebar = settingsPreferences?.compactSidebar.value ?? false;
      final showTopTitleBar =
          settingsPreferences?.showTopTitleBar.value ?? true;
      final showIndexHoverPreview =
          settingsPreferences?.showIndexHoverPreview.value ?? true;
      final reduceAnimations =
          settingsPreferences?.reduceAnimations.value ?? false;
      final timelineIsRunning = controller.timelineStatus.value.isActive;
      // A running turn gets a persistent live-activity affordance even when
      // the reader is already at the bottom. Once the turn ends, the same
      // slot falls back to the jump-to-latest arrow only when the reader has
      // detached from the newest content.
      final showScrollControl = timelineIsRunning || _showScrollToLatest;
      final answerCardRadius =
          settingsPreferences?.answerCardRadius.value ?? 24;
      final answerMaxWidth = settingsPreferences?.answerMaxWidth.value ?? 960;
      // A prompt should visually read as a distinct request, not as a
      // full-width answer panel. It remains tied to the reader-width setting
      // while capping the desktop bubble at a comfortably scannable measure.
      final userMessageMaxWidth = math.min(answerMaxWidth * 0.8, 760.0);
      final answerHorizontalPadding =
          settingsPreferences?.answerHorizontalPadding.value ?? 16;
      if (_lastAutoScrollEnabled != autoScrollToLatest) {
        _lastAutoScrollEnabled = autoScrollToLatest;
        if (autoScrollToLatest) _lastAutoScrollSignature = '';
      }
      final timelineEntries = _timelineEntries;
      final timelineEntryKeys = _keysForTimelineEntries(timelineEntries.length);
      final effectiveMediaQuery = MediaQuery.of(context).copyWith(
        disableAnimations:
            MediaQuery.of(context).disableAnimations || reduceAnimations,
      );
      if (autoScrollToLatest &&
          (controller.events.isNotEmpty ||
              controller.currentSessionId.value != null)) {
        _scheduleScrollToLatest(_timelineSignature);
      }
      final mediaQuery = MediaQuery.of(context);
      final topInset = mediaQuery.padding.top;
      // The macOS titlebar is transparent/full-size now. Reserve a small
      // traffic-light-safe strip so the page menu remains draggable and does
      // not sit underneath the close/minimize controls.
      final windowTopInset =
          topInset +
          (defaultTargetPlatform == TargetPlatform.macOS ? 28.0 : 0.0);
      final headerReservedHeight = showTopTitleBar
          ? _headerReservedHeight
          : 0.0;
      final bottomInset = mediaQuery.padding.bottom;
      final composerSlideDuration = effectiveMediaQuery.disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 430);
      final composerFadeDuration = effectiveMediaQuery.disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 300);
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final useMetaModifier = defaultTargetPlatform == TargetPlatform.macOS;
      final shortcutMap = shortcutsEnabled
          ? <ShortcutActivator, Intent>{
              SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: useMetaModifier,
                control: !useMetaModifier,
              ): const _NewConversationIntent(),
              SingleActivator(
                LogicalKeyboardKey.keyK,
                meta: useMetaModifier,
                control: !useMetaModifier,
              ): const _CommandPaletteIntent(),
              SingleActivator(
                LogicalKeyboardKey.keyB,
                meta: useMetaModifier,
                control: !useMetaModifier,
              ): const _ToggleSidebarIntent(),
              SingleActivator(
                LogicalKeyboardKey.keyL,
                meta: useMetaModifier,
                control: !useMetaModifier,
              ): const _FocusComposerIntent(),
              SingleActivator(
                LogicalKeyboardKey.enter,
                meta: useMetaModifier,
                control: !useMetaModifier,
              ): const _SendPromptIntent(),
              const SingleActivator(LogicalKeyboardKey.escape):
                  const _StopTaskIntent(),
            }
          : const <ShortcutActivator, Intent>{};
      return MediaQuery(
        data: effectiveMediaQuery,
        child: Shortcuts(
          shortcuts: shortcutMap,
          child: Actions(
            actions: <Type, Action<Intent>>{
              _NewConversationIntent: CallbackAction<_NewConversationIntent>(
                onInvoke: (_) {
                  _startNewConversation();
                  return null;
                },
              ),
              _CommandPaletteIntent: CallbackAction<_CommandPaletteIntent>(
                onInvoke: (_) {
                  _showCommandPalette();
                  return null;
                },
              ),
              _ToggleSidebarIntent: CallbackAction<_ToggleSidebarIntent>(
                onInvoke: (_) {
                  _toggleSidebar();
                  return null;
                },
              ),
              _FocusComposerIntent: CallbackAction<_FocusComposerIntent>(
                onInvoke: (_) {
                  _focusComposer();
                  return null;
                },
              ),
              _SendPromptIntent: CallbackAction<_SendPromptIntent>(
                onInvoke: (_) {
                  _sendPrompt();
                  return null;
                },
              ),
              _StopTaskIntent: CallbackAction<_StopTaskIntent>(
                onInvoke: (_) {
                  controller.interrupt();
                  return null;
                },
              ),
            },
            child: LiquidBackground(
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: isDark
                      ? Brightness.light
                      : Brightness.dark,
                  statusBarBrightness: isDark
                      ? Brightness.dark
                      : Brightness.light,
                ),
                child: Scaffold(
                  key: _scaffoldKey,
                  backgroundColor: Colors.transparent,
                  drawerEnableOpenDragGesture: !compactSidebar,
                  drawer: RemodexDrawer(
                    connected: controller.connected.value,
                    pairings: controller.pairings,
                    activePairing: controller.activePairing,
                    workspaces: controller.workspaces,
                    selectedWorkspace: controller.selectedWorkspace.value,
                    sessions: controller.sessions,
                    selectedSessionId: controller.selectedSessionId.value,
                    onSelectPairing: (profile) {
                      controller.switchPairing(profile.id);
                    },
                    onSelectWorkspace: (workspace) {
                      controller.selectWorkspace(workspace);
                    },
                    onSelectSession: (session) {
                      controller.selectSession(session);
                      Navigator.of(context).pop();
                    },
                    onPairing: () => _openPage(Routes.pairing),
                    onNewPairing: () => _openPage(
                      Routes.pairing,
                      arguments: const PairingPageArgs(createNew: true),
                    ),
                    onSettings: () => _openPage(Routes.settings),
                    themePreference: themeController.preference.value,
                    onThemePreferenceChanged: themeController.setPreference,
                    onRefreshProjects: controller.connected.value
                        ? controller.refreshProjects
                        : null,
                    refreshing: controller.timelineRefreshing.value,
                    compact: compactSidebar,
                  ),
                  onDrawerChanged: (open) {
                    if (_drawerOpen == open || !mounted) return;
                    setState(() => _drawerOpen = open);
                  },
                  body: Stack(
                    children: [
                      NotificationListener<ScrollNotification>(
                        onNotification: _handleScrollNotification,
                        child: CustomScrollView(
                          controller: _scrollController,
                          slivers: [
                            SliverToBoxAdapter(
                              child: SizedBox(
                                height: headerReservedHeight + windowTopInset,
                              ),
                            ),
                            if (controller.lastError.value.isNotEmpty)
                              SliverToBoxAdapter(
                                child: InlineError(
                                  message: controller.lastError.value,
                                  onDismiss: () =>
                                      controller.lastError.value = '',
                                ),
                              ),
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                answerHorizontalPadding,
                                26,
                                answerHorizontalPadding,
                                0,
                              ),
                              sliver: SliverList.separated(
                                itemCount: controller.events.isEmpty
                                    ? 1
                                    : timelineEntries.length,
                                separatorBuilder: (context, index) =>
                                    SizedBox(height: compactTimeline ? 14 : 26),
                                itemBuilder: (context, index) {
                                  if (controller.events.isEmpty) {
                                    if (controller.selectedSessionId.value !=
                                        null) {
                                      return TimelineLoadState(
                                        loading:
                                            controller.timelineLoading.value,
                                        elapsedSeconds: controller
                                            .timelineLoadElapsedSeconds
                                            .value,
                                        error:
                                            controller.timelineLoadError.value,
                                        onRetry:
                                            controller.retrySelectedSession,
                                        cardRadius: answerCardRadius,
                                      );
                                    }
                                    return WelcomeTimeline(
                                      connected: controller.connected.value,
                                      connectionLabel:
                                          controller.connectionLabel.value,
                                      workspaceCount:
                                          controller.workspaces.length,
                                      maxWidth: answerMaxWidth,
                                      onPairing: () =>
                                          _openPage(Routes.pairing),
                                    );
                                  }
                                  final entry = timelineEntries[index];
                                  if (entry.userEvent != null) {
                                    return KeyedSubtree(
                                      key: timelineEntryKeys[index],
                                      child: AssistantBubble(
                                        event: entry.userEvent!,
                                        cardRadius: answerCardRadius,
                                        userMessageMaxWidth:
                                            userMessageMaxWidth,
                                      ),
                                    );
                                  }
                                  final isLatestEntry =
                                      index == timelineEntries.length - 1;
                                  return KeyedSubtree(
                                    key: timelineEntryKeys[index],
                                    child: AssistantAnswerBlock(
                                      events: entry.events,
                                      previousAnswerEvents:
                                          entry.previousAnswerEvents,
                                      completed:
                                          !isLatestEntry ||
                                          controller
                                              .timelineStatus
                                              .value
                                              .isTerminal,
                                      status: isLatestEntry
                                          ? controller.timelineStatus.value
                                          : TimelineTaskStatus.completed,
                                      startedAt: isLatestEntry
                                          ? controller
                                                .timelineTurnStartedAt
                                                .value
                                          : null,
                                      showReasoning: showReasoning,
                                      collapseReasoningByDefault:
                                          collapseReasoningByDefault,
                                      showToolCallDetails: showToolCallDetails,
                                      showUsageMetrics: showUsageMetrics,
                                      cardRadius: answerCardRadius,
                                      maxWidth: answerMaxWidth,
                                      gitChangeSummary: GitChangeSummary.tryParse(
                                        GitSnapshot.fromEvents(entry.events).numstat,
                                      ),
                                      onGitFileTap: (file) =>
                                          _openGitDiff(file, entry.events),
                                      onUndoGitChanges: _confirmUndoChanges,
                                    ),
                                  );
                                },
                              ),
                            ),
                            SliverPadding(
                              padding: EdgeInsets.symmetric(horizontal: answerHorizontalPadding),
                              sliver: SliverToBoxAdapter(child: Column(children: [
                                if (controller.interactionNotice.value.isNotEmpty)
                                  Padding(padding: const EdgeInsets.all(12), child: Text(controller.interactionNotice.value)),
                                if (controller.selectedInteractions.isEmpty &&
                                    (controller.timelineStatus.value == TimelineTaskStatus.waitingApproval ||
                                     controller.timelineStatus.value == TimelineTaskStatus.waitingUserInput))
                                  const Padding(padding: EdgeInsets.all(12),
                                    child: Text('Codex 正在等待处理，请在桌面端完成或刷新任务。')),
                                for (final item in controller.selectedInteractions)
                                  PendingInteractionCard(
                                    key: ValueKey(item.id), item: item,
                                    enabled: controller.connected.value && controller.backendReady.value,
                                    submitted: controller.submittedInteractions.contains(item.id),
                                    onRespond: (response) => controller.respondToInteraction(item, response),
                                  ),
                              ])),
                            ),
                            SliverToBoxAdapter(
                              child: SizedBox(
                                key: _timelineBottomKey,
                                height: _composerReservedHeight + bottomInset,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (showTopTitleBar)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          child: HomeHeader(
                            title: _taskHeaderTitle,
                            subtitle: _projectHeaderSubtitle,
                            backgroundProgress: _headerBackgroundProgress,
                            topPadding: windowTopInset,
                            onRefreshTasks: controller.connected.value
                                ? controller.refreshProjectTasks
                                : null,
                            refreshing: controller.timelineRefreshing.value,
                            onShowTaskOutput: _taskOutputText.isEmpty
                                ? null
                                : _showTaskOutput,
                            onCopyTaskOutput: _taskOutputText.isEmpty
                                ? null
                                : _copyTaskOutput,
                            onRefreshGit: controller.canUseWorkspace
                                ? () => controller.gitStatus(includeDiff: true)
                                : null,
                            taskOutputAvailable: _taskOutputText.isNotEmpty,
                          ),
                        ),
                      if (showConversationIndex &&
                          controller.events.isNotEmpty &&
                          timelineEntries.isNotEmpty &&
                          mediaQuery.size.width >= (_drawerOpen ? 700 : 760))
                        Positioned(
                          left: _drawerOpen ? 304 : 14,
                          top: windowTopInset + (showTopTitleBar ? 118 : 16),
                          height:
                              (mediaQuery.size.height -
                                      windowTopInset -
                                      _composerReservedHeight -
                                      (showTopTitleBar ? 132 : 30))
                                  .clamp(180.0, 380.0)
                                  .toDouble(),
                          width: 52,
                          child: _TimelineIndex(
                            key: const ValueKey('timeline-index'),
                            entries: timelineEntries,
                            entryKeys: timelineEntryKeys,
                            scrollController: _scrollController,
                            showHoverPreview: showIndexHoverPreview,
                          ),
                        ),
                      AnimatedPositioned(
                        duration: effectiveMediaQuery.disableAnimations
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        left: 0,
                        right: 0,
                        bottom: _scrollToLatestBottom + bottomInset,
                        child: IgnorePointer(
                          ignoring: !showScrollControl,
                          child: AnimatedOpacity(
                            duration: effectiveMediaQuery.disableAnimations
                                ? Duration.zero
                                : const Duration(milliseconds: 160),
                            opacity: showScrollControl ? 1 : 0,
                            child: AnimatedScale(
                              duration: effectiveMediaQuery.disableAnimations
                                  ? Duration.zero
                                  : const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              scale: showScrollControl ? 1 : 0.82,
                              child: ExcludeSemantics(
                                excluding: !showScrollControl,
                                child: TickerMode(
                                  enabled: showScrollControl,
                                  child: Center(
                                    child: ScrollToLatestButton(
                                      running: timelineIsRunning,
                                      reduceMotion: reduceAnimations,
                                      onPressed: _scrollToLatest,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 18 + bottomInset,
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
                                focusNode: _composerFocusNode,
                                enabled: controller.canUseWorkspace,
                                context: controller.composerContext.value,
                                contextWindowUsage:
                                    controller.contextWindowUsage,
                                permissionMode: controller.permissionMode.value,
                                onSend: _sendPrompt,
                                onSteer: _sendingSupplement ? null : _sendSupplement,
                                // Derive the composer state from the same
                                // canonical lifecycle used by the answer
                                // header.  The legacy boolean can otherwise
                                // briefly disagree and leave a stop button
                                // visible next to an "已中断/已完成" header.
                                running: timelineIsRunning,
                                onStop: controller.interrupt,
                                onModelChanged: controller.setComposerModel,
                                onReasoningChanged:
                                    controller.setReasoningEffort,
                                onPermissionModeChanged:
                                    controller.setPermissionMode,
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
            ),
          ),
        ),
      );
    });
  }

  List<GlobalKey> _keysForTimelineEntries(int count) {
    while (_timelineEntryKeys.length < count) {
      _timelineEntryKeys.add(GlobalKey(debugLabel: 'timeline-entry'));
    }
    if (_timelineEntryKeys.length > count) {
      _timelineEntryKeys.removeRange(count, _timelineEntryKeys.length);
    }
    return List<GlobalKey>.unmodifiable(_timelineEntryKeys);
  }

  List<_TimelineEntry> get _timelineEntries {
    final entries = <_TimelineEntry>[];
    final answerEvents = <SessionEvent>[];
    var previousAnswerEvents = const <SessionEvent>[];

    void flushAnswer() {
      if (answerEvents.isEmpty) {
        previousAnswerEvents = const [];
        return;
      }
      final currentEvents = List<SessionEvent>.of(answerEvents);
      entries.add(_TimelineEntry.answer(currentEvents, previousAnswerEvents));
      previousAnswerEvents = currentEvents;
      answerEvents.clear();
    }

    String? answerTurnId;
    for (final event in orderTimelineEvents(controller.events)) {
      if (event.kind == 'user') {
        flushAnswer();
        answerTurnId = event.turnId;
        entries.add(_TimelineEntry.user(event));
      } else {
        if (event.turnId != null && answerTurnId != null &&
            event.turnId != answerTurnId) {
          flushAnswer();
        }
        answerTurnId = event.turnId ?? answerTurnId;
        answerEvents.add(event);
      }
    }
    flushAnswer();
    return entries;
  }

  String get _taskHeaderTitle {
    final selectedId = controller.selectedSessionId.value?.trim();
    if (selectedId != null && selectedId.isNotEmpty) {
      for (final session in controller.sessions) {
        if (session.id.trim() == selectedId) return session.displayTitle;
      }
    }
    return '新对话';
  }

  String get _projectHeaderSubtitle {
    final workspace = controller.selectedWorkspace.value;
    if (workspace == null) return '';
    final name = workspace.name.trim();
    if (name.isNotEmpty) return lastPathSegment(name);
    final path = workspace.path.trim();
    return path.isEmpty ? '' : lastPathSegment(path);
  }

  String get _taskOutputText {
    final sections = <String>[];
    for (final event in controller.events) {
      final text = event.text.trim();
      final kind = event.kind.trim().toLowerCase();
      if (text.isEmpty || kind == 'token_usage') continue;
      final label = switch (kind) {
        'user' => '用户',
        'assistant' => '助手',
        'reasoning' => '思考',
        'tool_call' => '工具',
        'file_change' => '文件',
        'running' => '状态',
        'interrupted' => '状态',
        _ => '事件',
      };
      sections.add('$label\n$text');
    }
    return sections.join('\n\n');
  }

  void _showTaskOutput() {
    final output = _taskOutputText;
    if (output.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (_) =>
          TaskOutputDialog(output: output, subtitle: _selectedTaskTitle),
    );
  }

  Future<void> _copyTaskOutput() async {
    final output = _taskOutputText;
    if (output.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: output));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('任务输出已复制')));
  }

  String get _selectedTaskTitle {
    final selectedId = controller.selectedSessionId.value;
    if (selectedId != null) {
      for (final session in controller.sessions) {
        if (session.id == selectedId) return session.displayTitle;
      }
    }
    return '当前任务';
  }

  String get _timelineSignature {
    final last = controller.events.isEmpty ? '' : controller.events.last.text;
    final workspace =
        controller.selectedWorkspace.value?.path ??
        controller.selectedWorkspace.value?.name ??
        '';
    return '$workspace:${controller.timelineRevision.value}:${controller.events.length}:${controller.currentSessionId.value}:$last';
  }

  void _updateHeaderBackground() {
    if (!_scrollController.hasClients || !_scrollController.position.hasPixels) {
      return;
    }
    final next = (_scrollController.offset / 72).clamp(0.0, 1.0);
    _pendingHeaderProgress = next;
    _scheduleScrollUiUpdate();
  }

  void _updateScrollToLatestVisibility() {
    if (!_scrollController.hasClients ||
        !_scrollController.position.hasContentDimensions) {
      return;
    }
    final distance =
        _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    final shouldShow =
        _userDetachedFromLatest && distance > _scrollToLatestThreshold;
    _pendingScrollToLatest = shouldShow;
    _scheduleScrollUiUpdate();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final distance =
        notification.metrics.maxScrollExtent - notification.metrics.pixels;
    // Only a user-originated scroll detaches auto-follow. Changes to the
    // content extent while a task streams must not make the button appear or
    // interrupt the user's reading position by themselves.
    if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle) {
      _userDetachedFromLatest = distance > _scrollToLatestThreshold;
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _userDetachedFromLatest = distance > _scrollToLatestThreshold;
    }
    _updateScrollToLatestVisibility();
    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification ||
        notification is OverscrollNotification) {
      _setComposerVisible(false);
      return false;
    }
    if (notification is ScrollEndNotification) {
      _setComposerVisible(true);
    }
    return false;
  }

  void _setComposerVisible(bool visible) {
    _pendingComposerVisible = visible;
    _scheduleScrollUiUpdate();
  }

  void _scheduleScrollUiUpdate() {
    if (!mounted) return;
    // Resizing can start/end a ballistic scroll inside applyContentDimensions.
    // Rebuilding here interrupts ScrollPosition before it saves its metrics.
    // Coalesce notifications and apply the latest values after layout.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_scrollUiUpdateScheduled) return;
      _scrollUiUpdateScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _applyScrollUiUpdate(),
      );
    } else {
      _applyScrollUiUpdate();
    }
  }

  void _applyScrollUiUpdate() {
    _scrollUiUpdateScheduled = false;
    if (!mounted) return;
    final header = _pendingHeaderProgress ?? _headerBackgroundProgress;
    final showLatest = _pendingScrollToLatest ?? _showScrollToLatest;
    final composer = _pendingComposerVisible ?? _composerVisible;
    _pendingHeaderProgress = null;
    _pendingScrollToLatest = null;
    _pendingComposerVisible = null;
    if ((header - _headerBackgroundProgress).abs() < 0.02 &&
        showLatest == _showScrollToLatest &&
        composer == _composerVisible) {
      return;
    }
    setState(() {
      _headerBackgroundProgress = header;
      _showScrollToLatest = showLatest;
      _composerVisible = composer;
    });
  }

  void _scheduleScrollToLatest(String signature) {
    if (signature == _lastAutoScrollSignature) return;
    if (_userDetachedFromLatest) return;
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
    Future<void>.delayed(
      const Duration(milliseconds: 360),
      _scrollToLatestAfterLayout,
    );
    Future<void>.delayed(
      const Duration(milliseconds: 700),
      _scrollToLatestAfterLayout,
    );
  }

  void _scrollToLatestAfterLayout({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_userDetachedFromLatest && !force) return;
      if (!_scrollController.position.hasContentDimensions) return;
      final target = _scrollController.position.maxScrollExtent;
      if (_reduceMotionEnabled) {
        _scrollController.jumpTo(target);
        _updateScrollToLatestVisibility();
        return;
      }
      _scrollController
          .animateTo(
            target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (!mounted) return;
            _updateScrollToLatestVisibility();
          });
    });
  }

  void _scrollToLatest() {
    _userDetachedFromLatest = false;
    _lastAutoScrollSignature = '';
    _scrollToLatestAfterLayout(force: true);
  }

  bool get _reduceMotionEnabled {
    if (MediaQuery.of(context).disableAnimations) return true;
    final preferences = Get.isRegistered<SettingsPreferencesController>()
        ? Get.find<SettingsPreferencesController>()
        : null;
    return preferences?.reduceAnimations.value ?? false;
  }

  Future<void> _sendSupplement() async {
    final draft = _promptController.text;
    final key = _draftKey;
    if (draft.trim().isEmpty || _sendingSupplement) return;
    setState(() => _sendingSupplement = true);
    final accepted = await controller.steerCurrentTurn(draft.trim());
    if (!mounted) return;
    setState(() => _sendingSupplement = false);
    if (accepted) {
      if (_draftKey == key && _promptController.text == draft) _promptController.clear();
      if (_drafts[key] == draft) _drafts.remove(key);
    }
  }

  void _sendPrompt() {
    if (controller.timelineStatus.value.isActive) return;
    if (controller.timelineLoading.value) {
      controller.lastError.value = '任务对话仍在加载，请稍候再发送。';
      return;
    }
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;
    controller.startSession(prompt);
    _promptController.clear();
  }

  void _focusComposer() {
    if (!_composerVisible && mounted) {
      setState(() => _composerVisible = true);
    }
    _composerFocusNode.requestFocus();
  }

  void _startNewConversation() {
    controller.startNewConversation();
    _promptController.clear();
    _focusComposer();
  }

  void _toggleSidebar() {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold == null) return;
    if (scaffold.isDrawerOpen) {
      Navigator.of(context).pop();
    } else {
      scaffold.openDrawer();
    }
  }

  void _showCommandPalette() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('命令面板'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _startNewConversation();
            },
            child: const ListTile(
              leading: Icon(RecodexIcons.add),
              title: Text('新建任务'),
              subtitle: Text('清空当前对话并聚焦输入框'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _focusComposer();
            },
            child: const ListTile(
              leading: Icon(RecodexIcons.edit),
              title: Text('聚焦输入框'),
              subtitle: Text('将光标移动到任务输入框'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _toggleSidebar();
            },
            child: const ListTile(
              leading: Icon(RecodexIcons.menu),
              title: Text('显示/隐藏侧边栏'),
              subtitle: Text('展开或收起项目和任务列表'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _openPage(Routes.settings);
            },
            child: const ListTile(
              leading: Icon(RecodexIcons.settings),
              title: Text('打开设置'),
              subtitle: Text('管理外观、连接和任务偏好'),
            ),
          ),
        ],
      ),
    );
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

  void _openPage(String route, {Object? arguments}) {
    if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
    Get.toNamed(route, arguments: arguments);
  }

  void _openGitDiff(GitFileChange file, List<SessionEvent> answerEvents) {
    final snapshot = GitSnapshot.fromEvents(answerEvents);
    Get.toNamed(
      Routes.gitDiff,
      arguments: GitDiffPageArgs(
        snapshot: snapshot,
        selectedPath: file.path,
        followWorkspace: false,
      ),
    );
  }
}

class _NewConversationIntent extends Intent {
  const _NewConversationIntent();
}

class _CommandPaletteIntent extends Intent {
  const _CommandPaletteIntent();
}

class _ToggleSidebarIntent extends Intent {
  const _ToggleSidebarIntent();
}

class _FocusComposerIntent extends Intent {
  const _FocusComposerIntent();
}

class _SendPromptIntent extends Intent {
  const _SendPromptIntent();
}

class _StopTaskIntent extends Intent {
  const _StopTaskIntent();
}

class _TimelineEntry {
  const _TimelineEntry._({
    required this.events,
    this.userEvent,
    this.previousAnswerEvents = const [],
  });

  factory _TimelineEntry.user(SessionEvent event) {
    return _TimelineEntry._(events: const [], userEvent: event);
  }

  factory _TimelineEntry.answer(
    List<SessionEvent> events,
    List<SessionEvent> previousAnswerEvents,
  ) {
    return _TimelineEntry._(
      events: events,
      previousAnswerEvents: previousAnswerEvents,
    );
  }

  final List<SessionEvent> events;
  final List<SessionEvent> previousAnswerEvents;
  final SessionEvent? userEvent;
}

/// A compact conversation index modelled after Codex's desktop transcript
/// rail. Each mark maps to one top-level user turn or answer block. Clicking a
/// mark reveals that block, while hovering it exposes a readable preview.
class _TimelineIndex extends StatefulWidget {
  const _TimelineIndex({
    required this.entries,
    required this.entryKeys,
    required this.scrollController,
    this.showHoverPreview = true,
    super.key,
  });

  final List<_TimelineEntry> entries;
  final List<GlobalKey> entryKeys;
  final ScrollController scrollController;
  final bool showHoverPreview;

  @override
  State<_TimelineIndex> createState() => _TimelineIndexState();
}

class _TimelineIndexState extends State<_TimelineIndex> {
  int _activeIndex = 0;
  int? _hoveredIndex;
  bool _activeIndexUpdateScheduled = false;

  List<_TimelineIndexMarker> get _markers {
    final markers = <_TimelineIndexMarker>[];
    var hasUserQuestion = false;
    for (var entryIndex = 0; entryIndex < widget.entries.length; entryIndex++) {
      final entry = widget.entries[entryIndex];
      if (entry.userEvent != null) {
        hasUserQuestion = true;
        markers.add(
          _TimelineIndexMarker(
            entryIndex: entryIndex,
            preview: entry.userEvent!.text,
          ),
        );
      }
    }
    // A newly-created turn briefly contains only assistant events while the
    // user message is being acknowledged. Keep the index useful during that
    // hand-off, but avoid adding one mark for every tool/reasoning event once
    // a real question is available.
    if (!hasUserQuestion) {
      for (
        var entryIndex = 0;
        entryIndex < widget.entries.length;
        entryIndex++
      ) {
        final entry = widget.entries[entryIndex];
        markers.add(
          _TimelineIndexMarker(
            entryIndex: entryIndex,
            preview: entry.events
                .map((event) => event.text)
                .firstWhere(
                  (text) => text.trim().isNotEmpty,
                  orElse: () => '回答内容',
                ),
          ),
        );
      }
    }
    return markers;
  }

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_updateActiveIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateActiveIndex());
  }

  @override
  void didUpdateWidget(covariant _TimelineIndex oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_updateActiveIndex);
      widget.scrollController.addListener(_updateActiveIndex);
    }
    final markers = _markers;
    if (markers.isEmpty) {
      _activeIndex = 0;
      _hoveredIndex = null;
    } else if (_activeIndex >= markers.length) {
      _activeIndex = markers.length - 1;
    }
    if (!widget.showHoverPreview) _hoveredIndex = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateActiveIndex());
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_updateActiveIndex);
    super.dispose();
  }

  void _updateActiveIndex() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (!_activeIndexUpdateScheduled) {
        _activeIndexUpdateScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _activeIndexUpdateScheduled = false;
          _updateActiveIndex();
        });
      }
      return;
    }
    final markers = _markers;
    if (markers.isEmpty) return;
    final scroll = widget.scrollController;
    var next = 0;
    if (scroll.hasClients &&
        scroll.position.hasContentDimensions &&
        scroll.position.maxScrollExtent > 0) {
      final progress =
          (scroll.position.pixels / scroll.position.maxScrollExtent).clamp(
            0.0,
            1.0,
          );
      next = (progress * (markers.length - 1)).round();
    }
    if (next == _activeIndex) return;
    setState(() => _activeIndex = next);
  }

  Future<void> _reveal(int index) async {
    final markers = _markers;
    if (index < 0 || index >= markers.length) return;
    final entryIndex = markers[index].entryIndex;
    final targetContext = entryIndex < widget.entryKeys.length
        ? widget.entryKeys[entryIndex].currentContext
        : null;
    if (targetContext != null) {
      await Scrollable.ensureVisible(
        targetContext,
        duration: MediaQuery.of(context).disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        // The selected question should land in the visual center of the
        // transcript, matching Codex's index navigation behavior.
        alignment: 0.5,
      );
      return;
    }
    final scroll = widget.scrollController;
    if (!scroll.hasClients ||
        !scroll.position.hasContentDimensions ||
        markers.length < 2) {
      return;
    }
    final target =
        scroll.position.maxScrollExtent * (index / (markers.length - 1));
    if (MediaQuery.of(context).disableAnimations) {
      scroll.jumpTo(target);
      return;
    }
    await scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  String _previewFor(_TimelineIndexMarker marker) {
    final raw = marker.preview;
    final normalized = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return '回答内容';
    return normalized.length > 72
        ? '${normalized.substring(0, 72).trimRight()}…'
        : normalized;
  }

  double _barWidth(int index) {
    // Codex keeps the rail quiet at rest and only expands the mark under the
    // pointer. The active question is distinguished by color instead of by a
    // permanently oversized bar.
    if (index == _hoveredIndex) return 32;
    return 10;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final reduceAnimations = MediaQuery.of(context).disableAnimations;
    final markers = _markers;
    if (markers.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = markers.length;
        // Keep the index rail compact when a transcript has many turns. A
        // tighter 8–14px rhythm keeps the marks visually attached to the
        // conversation while preserving enough separation to scan them.
        final itemExtent = (constraints.maxHeight / count)
            .clamp(8.0, 14.0)
            .toDouble();
        final railHeight = itemExtent * count;
        final railTop = (constraints.maxHeight - railHeight) / 2;
        final hovered = _hoveredIndex;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: railTop,
              width: 48,
              height: railHeight,
              child: Column(
                children: [
                  for (var index = 0; index < count; index++)
                    SizedBox(
                      height: itemExtent,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) => setState(() => _hoveredIndex = index),
                          onExit: (_) {
                            if (_hoveredIndex == index) {
                              setState(() => _hoveredIndex = null);
                            }
                          },
                          child: Semantics(
                            button: true,
                            label: '对话索引 ${index + 1}',
                            onTap: () => _reveal(index),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _reveal(index),
                              child: SizedBox(
                                width: 48,
                                height: itemExtent,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: AnimatedContainer(
                                    duration: reduceAnimations
                                        ? Duration.zero
                                        : const Duration(milliseconds: 140),
                                    curve: Curves.easeOut,
                                    width: _barWidth(index),
                                    height: index == _activeIndex ? 3 : 2,
                                    decoration: BoxDecoration(
                                      color: index == _activeIndex
                                          ? colors.text
                                          : colors.textMuted.withValues(
                                              alpha: index == _hoveredIndex
                                                  ? 0.9
                                                  : 0.55,
                                            ),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (hovered != null && widget.showHoverPreview)
              Positioned(
                left: 56,
                top: (railTop + hovered * itemExtent - 34)
                    .clamp(0.0, constraints.maxHeight - 112)
                    .toDouble(),
                width: 292,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.glassColor.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colors.glassBorder.withValues(alpha: 0.7),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors.glassShadow.withValues(alpha: 0.24),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
                      child: Text(
                        _previewFor(markers[hovered]),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TimelineIndexMarker {
  const _TimelineIndexMarker({required this.entryIndex, required this.preview});

  final int entryIndex;
  final String preview;
}
