import 'dart:math' as math;
import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../components/chat_components.dart';
import '../../components/composer_images.dart';
import '../../components/liquid_background.dart';
import '../../components/menu_drawer.dart';
import '../../components/recodex_notice.dart';
import '../../models/bridge_models.dart';
import '../../services/timeline_events.dart';
import '../../services/composer_images.dart';
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
import 'widget/task_inbox_panel.dart';
import 'widget/scroll_to_latest_button.dart';
import 'widget/timeline_load_state.dart';
import 'widget/welcome_timeline.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
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
  final _imageDrafts = <String, _ImageDraft>{};
  final _referenceDrafts = <String, _ReferenceDraft>{};
  _ImageDraft get _imageDraft =>
      _imageDrafts.putIfAbsent(_draftKey, _ImageDraft.new);
  _ReferenceDraft get _referenceDraft =>
      _referenceDrafts.putIfAbsent(_draftKey, _ReferenceDraft.new);
  double get _composerAttachmentHeight =>
      (_imageDraft.images.isNotEmpty ||
          _referenceDraft.files.isNotEmpty ||
          _referenceDraft.skills.isNotEmpty)
      ? 140
      : 0;
  bool _pickingImage = false;
  late Worker _draftTaskWorker;
  late Worker _draftHostWorker;
  late Worker _draftWorkspaceWorker;
  String _draftKey = '';
  bool _sendingSupplement = false;
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechInitialized = false;
  bool _listening = false;
  bool _voiceStopping = false;
  String _voiceBaseText = '';

  String get _currentDraftKey =>
      '${controller.activePairingId.value}:${controller.selectedSessionId.value ?? 'new:${controller.selectedWorkspace.value?.path}'}';

  void _switchDraft() {
    final next = _currentDraftKey;
    if (next == _draftKey) return;
    _composerFocusNode.unfocus();
    _drafts[_draftKey] = _promptController.text;
    _draftKey = next;
    _promptController.text = _drafts[next] ?? '';
  }

  bool _drawerOpen = false;
  bool _showScrollToLatest = false;
  bool _userDetachedFromLatest = false;
  bool _userScrollingTimeline = false;
  bool? _lastAutoScrollEnabled;
  String _lastAutoScrollSignature = '';
  bool _scrollUiUpdateScheduled = false;
  double? _pendingHeaderProgress;
  bool? _pendingScrollToLatest;
  bool? _pendingComposerVisible;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_updateHeaderBackground);
    _scrollController.addListener(_updateScrollToLatestVisibility);
    _draftKey = _currentDraftKey;
    _draftTaskWorker = ever(
      controller.selectedSessionId,
      (_) => _switchDraft(),
    );
    _draftHostWorker = ever(controller.activePairingId, (_) => _switchDraft());
    _draftWorkspaceWorker = ever(
      controller.selectedWorkspace,
      (_) => _switchDraft(),
    );
    controller.startLiveTimelineRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_speech.cancel());
    _scrollController
      ..removeListener(_updateHeaderBackground)
      ..removeListener(_updateScrollToLatestVisibility)
      ..dispose();
    controller.stopLiveTimelineRefresh();
    _draftTaskWorker.dispose();
    _draftHostWorker.dispose();
    _draftWorkspaceWorker.dispose();
    _promptController.dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopVoiceInput(cancel: true);
    }
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
      final supportsDesktopShortcuts = switch (defaultTargetPlatform) {
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux => true,
        _ => false,
      };
      final shortcutsEnabled =
          supportsDesktopShortcuts &&
          (settingsPreferences?.shortcutsEnabled.value ?? true);
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
                    if (open) _composerFocusNode.unfocus();
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
                                      gitChangeSummary:
                                          GitChangeSummary.tryParse(
                                            GitSnapshot.fromEvents(
                                              entry.events,
                                            ).numstat,
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
                              padding: EdgeInsets.symmetric(
                                horizontal: answerHorizontalPadding,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: Column(
                                  children: [
                                    if (controller
                                        .interactionNotice
                                        .value
                                        .isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Text(
                                          controller.interactionNotice.value,
                                        ),
                                      ),
                                    if (controller
                                            .selectedInteractions
                                            .isEmpty &&
                                        (controller.timelineStatus.value ==
                                                TimelineTaskStatus
                                                    .waitingApproval ||
                                            controller.timelineStatus.value ==
                                                TimelineTaskStatus
                                                    .waitingUserInput))
                                      const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: Text(
                                          'Codex 正在等待处理，请在桌面端完成或刷新任务。',
                                        ),
                                      ),
                                    for (final item
                                        in controller.selectedInteractions)
                                      PendingInteractionCard(
                                        key: ValueKey(item.id),
                                        item: item,
                                        enabled:
                                            controller.connected.value &&
                                            controller.backendReady.value,
                                        submitted: controller
                                            .submittedInteractions
                                            .contains(item.id),
                                        onRespond: (response) =>
                                            controller.respondToInteraction(
                                              item,
                                              response,
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: SizedBox(
                                key: _timelineBottomKey,
                                height:
                                    _composerReservedHeight +
                                    bottomInset +
                                    _composerAttachmentHeight,
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
                            onShowTaskInbox: _showTaskInbox,
                            taskInboxCount: controller.unreadCompletedTaskCount,
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
                        bottom:
                            _scrollToLatestBottom +
                            bottomInset +
                            _composerAttachmentHeight,
                        child: IgnorePointer(
                          ignoring: !showScrollControl,
                          child: AnimatedSlide(
                            // Keep this utility attached to the composer
                            // while it slides out of the way during reading.
                            // Using the same curve and duration makes the
                            // loading dots and the latest-content arrow feel
                            // like part of one surface.
                            offset: _composerVisible
                                ? Offset.zero
                                : const Offset(0, 1.28),
                            duration: composerSlideDuration,
                            curve: _composerDampedCurve,
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
                              child: DropTarget(
                                enable:
                                    _composerVisible &&
                                    !_drawerOpen &&
                                    !_imageDraft.busy &&
                                    (ModalRoute.of(context)?.isCurrent ?? true),
                                onDragDone: (details) =>
                                    _addImageFiles(details.files),
                                child: ComposerBar(
                                  controller: _promptController,
                                  focusNode: _composerFocusNode,
                                  enabled: controller.canUseWorkspace,
                                  context: controller.composerContext.value,
                                  contextWindowUsage:
                                      controller.contextWindowUsage,
                                  permissionMode:
                                      controller.permissionMode.value,
                                  onSend: _sendPrompt,
                                  onSteer:
                                      _sendingSupplement ||
                                          _imageDraft.images.isNotEmpty
                                      ? null
                                      : _sendSupplement,
                                  imageButton: ComposerImageButton(
                                    enabled:
                                        controller.canUseWorkspace &&
                                        !_imageDraft.busy &&
                                        !_pickingImage &&
                                        !_imageDraft.unknown,
                                    onSelected: _pickImages,
                                    onFiles: _pickWorkspaceReferences,
                                    onSkills: _pickSkills,
                                  ),
                                  referenceTray:
                                      (_referenceDraft.files.isEmpty &&
                                          _referenceDraft.skills.isEmpty)
                                      ? null
                                      : ComposerReferenceTray(
                                          files: _referenceDraft.files,
                                          skills: _referenceDraft.skills,
                                          onRemoveFile: (file) => setState(
                                            () => _referenceDraft.files.remove(
                                              file,
                                            ),
                                          ),
                                          onRemoveSkill: (skill) => setState(
                                            () => _referenceDraft.skills.remove(
                                              skill,
                                            ),
                                          ),
                                        ),
                                  imageTray: _imageDraft.images.isEmpty
                                      ? null
                                      : ComposerImageTray(
                                          images: _imageDraft.images,
                                          busy: _imageDraft.busy,
                                          progress: _imageDraft.progress,
                                          error: _imageDraft.error,
                                          unknown: _imageDraft.unknown,
                                          onRemove: _removeImage,
                                          onReview: _reviewImageSend,
                                        ),
                                  hasAttachments:
                                      _imageDraft.images.isNotEmpty ||
                                      _referenceDraft.files.isNotEmpty ||
                                      _referenceDraft.skills.isNotEmpty,
                                  busy: _imageDraft.busy,
                                  sendBlocked: _imageDraft.unknown,
                                  onPaste: () => _pasteImageOrText(),
                                  listening: _listening,
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
        if (event.turnId != null &&
            answerTurnId != null &&
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

  void _showTaskInbox() {
    final compact = MediaQuery.sizeOf(context).width < 600;
    Widget buildPanel() => Obx(() {
      final sessions = List<SessionRecord>.from(controller.sessions);
      return TaskInboxPanel(
        sessions: sessions,
        selectedSessionId: controller.selectedSessionId.value,
        onSelect: (session) {
          controller.selectSession(session);
          Navigator.of(context).pop();
        },
        onRefresh: controller.connected.value
            ? controller.refreshProjects
            : null,
        showRefresh: controller.connected.value,
      );
    });

    if (compact) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(10, 24, 10, 10),
          child: buildPanel(),
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (_) => Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 76, right: 22),
          child: buildPanel(),
        ),
      ),
    );
  }

  Future<void> _copyTaskOutput() async {
    final output = _taskOutputText;
    if (output.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: output));
    if (!mounted) return;
    RecodexNotice.show(context, '任务输出已复制', tone: RecodexNoticeTone.success);
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
    if (!_scrollController.hasClients ||
        !_scrollController.position.hasPixels) {
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
    final userScroll =
        (notification is UserScrollNotification &&
            notification.direction != ScrollDirection.idle) ||
        (notification is ScrollStartNotification &&
            notification.dragDetails != null) ||
        (notification is ScrollUpdateNotification &&
            notification.dragDetails != null) ||
        (notification is OverscrollNotification &&
            notification.dragDetails != null);
    if (userScroll) {
      // animateTo, jumpTo, and layout corrections emit scroll notifications
      // too. Only a user gesture should hide the composer; retain that state
      // through its ballistic scrolling, whose updates have no dragDetails.
      _userScrollingTimeline = true;
      _setComposerVisible(false);
    } else if (notification is ScrollEndNotification &&
        _userScrollingTimeline) {
      _userScrollingTimeline = false;
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
    if (_userDetachedFromLatest || _userScrollingTimeline) return;
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
      if ((_userDetachedFromLatest || _userScrollingTimeline) && !force) return;
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
      if (_draftKey == key && _promptController.text == draft) {
        _promptController.clear();
      }
      if (_drafts[key] == draft) _drafts.remove(key);
    }
  }

  void _sendPrompt() {
    if (_listening) unawaited(_stopVoiceInput());
    if (_imageDraft.busy || _imageDraft.unknown) return;
    if (controller.timelineStatus.value.isActive) return;
    if (controller.timelineLoading.value) {
      controller.lastError.value = '任务对话仍在加载，请稍候再发送。';
      return;
    }
    final prompt = _promptController.text.trim();
    final refs = _referenceDraft.files
        .map((item) => item.path)
        .toList(growable: false);
    final skills = _referenceDraft.skills
        .map((item) => item.name)
        .toList(growable: false);
    if (_imageDraft.images.isNotEmpty) {
      unawaited(_sendImagePrompt(prompt));
      return;
    }
    if (prompt.isEmpty && refs.isEmpty && skills.isEmpty) return;
    if (refs.isEmpty && skills.isEmpty) {
      // Preserve the small overridable API used by platform integrations.
      controller.startSession(prompt);
    } else {
      controller.startSessionWithContext(
        prompt,
        workspaceRefs: refs,
        skills: skills,
      );
    }
    _promptController.clear();
    setState(() {
      _referenceDraft.files.clear();
      _referenceDraft.skills.clear();
    });
  }

  Future<void> _pickWorkspaceReferences() async {
    if (!controller.canUseWorkspace) return;
    final selected = {..._referenceDraft.files.map((item) => item.path)};
    final entriesByPath = <String, WorkspaceEntry>{
      for (final item in _referenceDraft.files) item.path: item,
    };
    final queryController = TextEditingController();
    var results = <WorkspaceEntry>[];
    var loading = true;
    var started = false;
    final confirmed = await showDialog<List<WorkspaceEntry>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> search() async {
            setDialogState(() => loading = true);
            try {
              results = await controller.searchWorkspace(queryController.text);
              entriesByPath.addAll({
                for (final item in results) item.path: item,
              });
            } catch (error) {
              if (mounted) controller.lastError.value = error.toString();
            }
            if (context.mounted) setDialogState(() => loading = false);
          }

          if (!started) {
            started = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) search();
            });
          }
          return AlertDialog(
            title: const Text('引用工作区文件'),
            content: SizedBox(
              width: 420,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    controller: queryController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(RecodexIcons.search),
                      hintText: '搜索文件或文件夹',
                    ),
                    onChanged: (_) => search(),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (_, index) {
                              final item = results[index];
                              final checked = selected.contains(item.path);
                              return CheckboxListTile(
                                dense: true,
                                value: checked,
                                onChanged: (_) => setDialogState(
                                  () => checked
                                      ? selected.remove(item.path)
                                      : selected.add(item.path),
                                ),
                                secondary: Icon(
                                  item.kind == 'directory'
                                      ? RecodexIcons.folder
                                      : RecodexIcons.fileText,
                                ),
                                title: Text(
                                  item.path,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  entriesByPath.values
                      .where((item) => selected.contains(item.path))
                      .toList(),
                ),
                child: Text('添加 ${selected.length} 项'),
              ),
            ],
          );
        },
      ),
    );
    queryController.dispose();
    if (!mounted || confirmed == null) return;
    setState(() {
      _referenceDraft.files
        ..clear()
        ..addAll(confirmed);
    });
  }

  Future<void> _pickSkills() async {
    if (!controller.canUseWorkspace) return;
    try {
      await controller.loadSkills();
    } catch (error) {
      controller.lastError.value = error.toString();
      return;
    }
    if (!mounted) return;
    final selected = {..._referenceDraft.skills.map((item) => item.name)};
    final confirmed = await showDialog<List<SkillInfo>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final colors = context.recodexColors;
          final theme = Theme.of(context);
          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 4),
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            backgroundColor: colors.glassColor.withValues(alpha: 0.98),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                color: colors.glassBorder.withValues(alpha: 0.7),
              ),
            ),
            title: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(9),
                    child: Icon(
                      RecodexIcons.fast,
                      size: 19,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '选择 Skill',
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        selected.isEmpty
                            ? '为下一条消息添加能力'
                            : '已选择 ${selected.length} 项',
                        style: TextStyle(color: colors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              height: 420,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: controller.skills.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final skill = controller.skills[index];
                  final isSelected = selected.contains(skill.name);
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setDialogState(() {
                        if (isSelected) {
                          selected.remove(skill.name);
                        } else {
                          selected.add(skill.name);
                        }
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? theme.colorScheme.primary.withValues(
                                  alpha: 0.10,
                                )
                              : colors.surfaceOverlay.withValues(alpha: 0.46),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.42,
                                  )
                                : colors.glassBorder.withValues(alpha: 0.56),
                          ),
                        ),
                        child: Row(
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? theme.colorScheme.primary.withValues(
                                        alpha: 0.16,
                                      )
                                    : colors.glassColor.withValues(alpha: 0.72),
                                shape: BoxShape.circle,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(9),
                                child: Icon(
                                  RecodexIcons.fast,
                                  size: 18,
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : colors.textMuted,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '\$${skill.name}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colors.text,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    skill.description.isEmpty
                                        ? '暂无描述'
                                        : skill.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colors.textMuted,
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Checkbox(
                              value: isSelected,
                              onChanged: (_) => setDialogState(() {
                                if (isSelected) {
                                  selected.remove(skill.name);
                                } else {
                                  selected.add(skill.name);
                                }
                              }),
                              visualDensity: VisualDensity.compact,
                              activeColor: theme.colorScheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  controller.skills
                      .where((skill) => selected.contains(skill.name))
                      .toList(),
                ),
                icon: const Icon(RecodexIcons.check, size: 17),
                label: Text(
                  selected.isEmpty ? '不添加' : '添加 ${selected.length} 项',
                ),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || confirmed == null) return;
    setState(() {
      _referenceDraft.skills
        ..clear()
        ..addAll(confirmed);
    });
  }

  Future<void> _pickImages(ComposerImageSource source) async {
    if (_pickingImage || _imageDraft.busy) return;
    if (!controller.imageAttachmentsAvailable.value) {
      controller.lastError.value = '当前主机未启用图片发送，请更新并重启 Codex Relay 插件';
      return;
    }
    final key = _draftKey;
    final draft = _imageDraft;
    _composerFocusNode.unfocus();
    setState(() => _pickingImage = true);
    try {
      if (source == ComposerImageSource.clipboard) {
        final bytes = await Pasteboard.image;
        if (bytes == null) throw const FormatException('剪贴板中没有图片');
        await _addImageFiles([
          XFile.fromData(bytes, name: '截图.png'),
        ], draftKey: key);
      } else {
        final platform = Theme.of(context).platform;
        final mobile =
            platform == TargetPlatform.iOS ||
            platform == TargetPlatform.android;
        final List<XFile> files;
        if (source == ComposerImageSource.camera) {
          final file = await ImagePicker().pickImage(
            source: ImageSource.camera,
            maxWidth: 2048,
            maxHeight: 2048,
            imageQuality: 90,
          );
          files = file == null ? [] : [file];
        } else if (mobile) {
          files = await ImagePicker().pickMultiImage(
            maxWidth: 2048,
            maxHeight: 2048,
            imageQuality: 90,
            limit: ComposerImage.maxCount,
          );
        } else {
          files = await openFiles(
            acceptedTypeGroups: [
              const XTypeGroup(
                label: '图片',
                extensions: ['png', 'jpg', 'jpeg', 'webp'],
                uniformTypeIdentifiers: [
                  'public.png',
                  'public.jpeg',
                  'org.webmproject.webp',
                ],
              ),
            ],
          );
        }
        await _addImageFiles(files, draftKey: key);
      }
    } catch (error) {
      draft.error = error is PlatformException
          ? '无法访问图片，请检查相册或相机权限'
          : error.toString().replaceFirst('FormatException: ', '');
      if (_draftKey == key) controller.lastError.value = draft.error!;
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _addImageFiles(List<XFile> files, {String? draftKey}) async {
    if (!mounted || files.isEmpty) return;
    final key = draftKey ?? _draftKey;
    final draft = _imageDrafts.putIfAbsent(key, _ImageDraft.new);
    if (draft.busy || draft.unknown) return;
    try {
      if (files.length + draft.images.length > ComposerImage.maxCount) {
        throw const FormatException('每条消息最多添加 4 张图片');
      }
      for (final file in files) {
        final image = await ComposerImage.fromFile(file);
        if (!mounted) return;
        if (draft.images.length >= ComposerImage.maxCount) {
          throw const FormatException('每条消息最多添加 4 张图片');
        }
        final total = _imageDrafts.values
            .expand((draft) => draft.images)
            .fold<int>(0, (sum, image) => sum + image.bytes.length);
        if (total + image.bytes.length > 48 * 1024 * 1024) {
          throw const FormatException('图片草稿过多，请先发送或移除已有图片');
        }
        if (draft.busy || draft.unknown) return;
        setState(() {
          draft.images.add(image);
          draft.error = null;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(
        () => draft.error = error.toString().replaceFirst(
          'FormatException: ',
          '',
        ),
      );
      if (_draftKey == key) controller.lastError.value = draft.error!;
    }
  }

  Future<void> _pasteImageOrText() async {
    if (_imageDraft.busy) return;
    final key = _draftKey;
    final value = _promptController.value;
    try {
      final bytes = await Pasteboard.image;
      if (!mounted) return;
      if (bytes != null) {
        await _addImageFiles([
          XFile.fromData(bytes, name: '截图.png'),
        ], draftKey: key);
        return;
      }
    } catch (_) {
      /* Text paste remains available if image paste is unsupported. */
    }
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted ||
        _draftKey != key ||
        _promptController.value != value ||
        clipboard?.text == null) {
      return;
    }
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    _promptController.value = TextEditingValue(
      text: value.text.replaceRange(
        selection.start,
        selection.end,
        clipboard!.text!,
      ),
      selection: TextSelection.collapsed(
        offset: selection.start + clipboard.text!.length,
      ),
    );
  }

  void _removeImage(ComposerImage image) {
    final scope = controller.imageMessageContext;
    setState(() {
      _imageDraft.images.remove(image);
      _imageDraft.error = null;
    });
    unawaited(controller.removeUploadedImage(image, scope));
  }

  Future<void> _reviewImageSend() async {
    final draft = _imageDraft;
    final key = _draftKey;
    controller.refreshProjectTasks();
    final sent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('核对发送结果'),
        content: const Text('正在刷新任务记录。请关闭此提示查看最新对话；确认结果后，可以清除已发送的草稿，或保留为待发送。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('先查看对话'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('确认未发送'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('已发送，清除草稿'),
          ),
        ],
      ),
    );
    if (!mounted || sent == null) return;
    setState(() {
      draft.unknown = false;
      if (sent) {
        draft.images.clear();
        _drafts.remove(key);
        if (_draftKey == key) _promptController.clear();
      }
    });
  }

  Future<void> _sendImagePrompt(String prompt) async {
    final draft = _imageDraft;
    var key = _draftKey;
    final scope = controller.imageMessageContext;
    final images = List<ComposerImage>.of(draft.images);
    setState(() {
      draft.busy = true;
      draft.error = null;
      draft.progress = 0;
    });
    try {
      final ids = <String>[];
      for (var i = 0; i < images.length; i++) {
        ids.add(
          await controller.uploadImage(images[i], scope, (progress) {
            if (mounted) {
              setState(() => draft.progress = (i + progress) / images.length);
            }
          }),
        );
      }
      final refs = _referenceDraft.files
          .map((item) => item.path)
          .toList(growable: false);
      final skills = _referenceDraft.skills
          .map((item) => item.name)
          .toList(growable: false);
      final outcome = (refs.isEmpty && skills.isEmpty)
          ? await controller.sendImageMessage(
              prompt,
              images,
              ids,
              scope,
              onThreadCreated: () {
                if (!mounted) return;
                _imageDrafts.remove(key);
                _drafts.remove(key);
                key = _currentDraftKey;
                _imageDrafts[key] = draft;
                _drafts[key] = prompt;
                _promptController.text = prompt;
              },
            )
          : await controller.sendImageMessageWithContext(
              prompt,
              images,
              ids,
              scope,
              workspaceRefs: refs,
              skills: skills,
              onThreadCreated: () {
                // The new server id replaces the local "new task" draft key. Move
                // exactly this draft, keeping unrelated host/task drafts intact.
                if (!mounted) return;
                _imageDrafts.remove(key);
                _drafts.remove(key);
                key = _currentDraftKey;
                _imageDrafts[key] = draft;
                _drafts[key] = prompt;
                _promptController.text = prompt;
              },
            );
      if (!mounted) return;
      if (outcome == ImageSendOutcome.accepted) {
        draft.images.clear();
        _referenceDrafts[key]?.files.clear();
        _referenceDrafts[key]?.skills.clear();
        _drafts.remove(key);
        if (_draftKey == key) _promptController.clear();
      } else {
        draft.unknown = outcome == ImageSendOutcome.unknown;
        draft.error = draft.unknown ? null : controller.lastError.value;
      }
    } catch (error) {
      draft.error =
          '上传未完成，图片已保留。${error.toString().replaceFirst('FormatException: ', '')}';
    } finally {
      if (mounted) setState(() => draft.busy = false);
    }
  }

  void _focusComposer() {
    if (!_composerVisible && mounted) {
      setState(() => _composerVisible = true);
    }
    _composerFocusNode.requestFocus();
  }

  void _startNewConversation() {
    _composerFocusNode.unfocus();
    controller.startNewConversation();
    _promptController.clear();
    if (!_composerVisible && mounted) {
      setState(() => _composerVisible = true);
    }
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
    _composerFocusNode.unfocus();
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
              subtitle: Text('清空当前对话，准备新任务'),
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
    if (_listening) {
      await _stopVoiceInput();
      return;
    }
    _composerFocusNode.unfocus();
    if (!_speechInitialized) {
      _speechInitialized = await _speech.initialize(
        onError: (error) {
          if (!mounted) return;
          setState(() => _listening = false);
          controller.lastError.value = '语音识别失败：${error.errorMsg}';
        },
        onStatus: (status) {
          if (!mounted) return;
          if (status == stt.SpeechToText.notListeningStatus ||
              status == stt.SpeechToText.doneStatus) {
            setState(() => _listening = false);
          }
        },
      );
    }
    if (!_speechInitialized) {
      controller.lastError.value = '当前设备不支持语音识别，或麦克风权限未开启。';
      return;
    }
    _voiceBaseText = _promptController.text.trimRight();
    try {
      _voiceStopping = false;
      await _speech.listen(
        onResult: _onVoiceResult,
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
          autoPunctuation: true,
          pauseFor: const Duration(seconds: 3),
          listenFor: const Duration(minutes: 2),
        ),
      );
      if (mounted) setState(() => _listening = true);
    } catch (_) {
      if (mounted) setState(() => _listening = false);
      controller.lastError.value = '无法启动语音识别，请检查麦克风权限。';
    }
  }

  void _onVoiceResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    final recognized = result.recognizedWords.trim();
    if (recognized.isEmpty) return;
    final separator = _voiceBaseText.isEmpty ? '' : ' ';
    _promptController.value = TextEditingValue(
      text: '$_voiceBaseText$separator$recognized',
      selection: TextSelection.collapsed(
        offset: _voiceBaseText.length + separator.length + recognized.length,
      ),
    );
    if (!_voiceStopping) setState(() => _listening = true);
  }

  Future<void> _stopVoiceInput({bool cancel = false}) async {
    if (!_speechInitialized) return;
    _voiceStopping = true;
    if (cancel) {
      await _speech.cancel();
    } else {
      await _speech.stop();
    }
    if (mounted) setState(() => _listening = false);
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
    // Clear the route's saved input focus as well as hiding the keyboard, so
    // returning from settings or pairing does not reopen it automatically.
    _composerFocusNode.unfocus();
    _scaffoldKey.currentState?.closeDrawer();
    Get.toNamed(route, arguments: arguments);
  }

  void _openGitDiff(GitFileChange file, List<SessionEvent> answerEvents) {
    _composerFocusNode.unfocus();
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

class _ImageDraft {
  final images = <ComposerImage>[];
  bool busy = false;
  bool unknown = false;
  double progress = 0;
  String? error;
}

class _ReferenceDraft {
  final files = <WorkspaceEntry>[];
  final skills = <SkillInfo>[];
}
