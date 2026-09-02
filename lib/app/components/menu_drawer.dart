import 'package:flutter/material.dart';

import '../models/bridge_models.dart';
import '../pages/settings/theme_controller.dart';
import '../theme/recodex_theme.dart';
import 'recodex_dropdown.dart';
import 'liquid_glass.dart';
import 'status_chips.dart';

class RemodexDrawer extends StatefulWidget {
  const RemodexDrawer({
    required this.connected,
    required this.pairings,
    required this.activePairing,
    required this.workspaces,
    required this.selectedWorkspace,
    required this.sessions,
    required this.selectedSessionId,
    required this.onSelectPairing,
    required this.onSelectWorkspace,
    required this.onSelectSession,
    required this.onPairing,
    required this.onNewPairing,
    required this.onSettings,
    required this.themePreference,
    required this.onThemePreferenceChanged,
    this.onRefreshProjects,
    this.compact = false,
    super.key,
  });

  final bool connected;
  final List<PairingProfile> pairings;
  final PairingProfile? activePairing;
  final List<WorkspaceInfo> workspaces;
  final WorkspaceInfo? selectedWorkspace;
  final List<SessionRecord> sessions;
  final String? selectedSessionId;
  final ValueChanged<PairingProfile> onSelectPairing;
  final ValueChanged<WorkspaceInfo> onSelectWorkspace;
  final ValueChanged<SessionRecord> onSelectSession;
  final VoidCallback onPairing;
  final VoidCallback onNewPairing;
  final VoidCallback onSettings;
  final RecodexThemePreference themePreference;
  final ValueChanged<RecodexThemePreference> onThemePreferenceChanged;
  final VoidCallback? onRefreshProjects;
  final bool compact;

  @override
  State<RemodexDrawer> createState() => _RemodexDrawerState();
}

class _RemodexDrawerState extends State<RemodexDrawer> {
  final ScrollController _sidebarScrollController = ScrollController();
  final Set<String> _expandedWorkspaceKeys = <String>{};
  final Map<String, GlobalKey> _workspaceItemKeys = <String, GlobalKey>{};
  String? _lastScrolledWorkspaceKey;

  @override
  void initState() {
    super.initState();
    _expandSelectedWorkspace();
    _scheduleScrollToSelected(jump: true);
  }

  @override
  void didUpdateWidget(covariant RemodexDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_workspaceKey(oldWidget.selectedWorkspace) !=
        _workspaceKey(widget.selectedWorkspace)) {
      _expandSelectedWorkspace();
    }
    _scheduleScrollToSelected(
      jump:
          oldWidget.selectedWorkspace == null ||
          oldWidget.workspaces.isEmpty != widget.workspaces.isEmpty,
    );
  }

  @override
  void dispose() {
    _sidebarScrollController.dispose();
    super.dispose();
  }

  void _expandSelectedWorkspace() {
    final key = _workspaceKey(widget.selectedWorkspace);
    if (key != null) {
      _expandedWorkspaceKeys.add(key);
    }
  }

  String? _workspaceKey(WorkspaceInfo? workspace) {
    if (workspace == null) {
      return null;
    }
    if (workspace.path.isNotEmpty) {
      return workspace.path;
    }
    if (workspace.name.isNotEmpty) {
      return workspace.name;
    }
    return null;
  }

  bool _isSelectedWorkspace(WorkspaceInfo workspace) {
    final selected = widget.selectedWorkspace;
    if (selected == null) {
      return false;
    }
    if (selected.path.isNotEmpty && workspace.path == selected.path) {
      return true;
    }
    return selected.path.isEmpty &&
        selected.name.isNotEmpty &&
        workspace.name == selected.name;
  }

  bool _sameSession(String left, String? right) {
    final normalizedRight = right?.trim();
    return normalizedRight != null &&
        normalizedRight.isNotEmpty &&
        left.trim() == normalizedRight;
  }

  void _scheduleScrollToSelected({required bool jump}) {
    final selectedKey = _workspaceKey(widget.selectedWorkspace);
    if (selectedKey == null) {
      return;
    }
    final scrollKey = '$selectedKey:${widget.workspaces.length}';
    if (scrollKey == _lastScrolledWorkspaceKey) {
      return;
    }
    _lastScrolledWorkspaceKey = scrollKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollSelectedIntoView(jump: jump);
    });
  }

  void _scrollSelectedIntoView({required bool jump}) {
    if (!mounted || !_sidebarScrollController.hasClients) {
      return;
    }
    final selectedKey = _workspaceKey(widget.selectedWorkspace);
    if (selectedKey == null) return;
    final itemContext = _workspaceItemKeys[selectedKey]?.currentContext;
    if (itemContext == null) return;
    Scrollable.ensureVisible(
      itemContext,
      duration: jump || MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: 0.18,
    );
  }

  GlobalKey _workspaceItemKey(WorkspaceInfo workspace) {
    final key = _workspaceKey(workspace);
    if (key == null) return GlobalKey();
    return _workspaceItemKeys.putIfAbsent(key, () => GlobalKey());
  }

  bool _isWorkspaceExpanded(WorkspaceInfo workspace) {
    final key = _workspaceKey(workspace);
    return key != null && _expandedWorkspaceKeys.contains(key);
  }

  void _toggleWorkspace(WorkspaceInfo workspace) {
    final key = _workspaceKey(workspace);
    if (key == null) return;
    final selected = _isSelectedWorkspace(workspace);
    setState(() {
      if (_expandedWorkspaceKeys.contains(key)) {
        _expandedWorkspaceKeys.remove(key);
      } else {
        _expandedWorkspaceKeys.add(key);
      }
    });
    // Keep the active conversation when toggling its project. Selecting a
    // different project still switches the working context.
    if (!selected) {
      widget.onSelectWorkspace(workspace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final verticalGap = widget.compact ? 14.0 : 22.0;
    return Drawer(
      width: widget.compact ? 272 : 292,
      backgroundColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 12, 0),
          child: LiquidGlass(
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            // Keep the drawer surface opaque so the modal barrier does not
            // wash the sidebar into the page content beneath it.
            opacity: 1,
            padding: EdgeInsets.fromLTRB(
              widget.compact ? 16 : 22,
              widget.compact ? 16 : 22,
              widget.compact ? 10 : 14,
              8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PairingSwitcher(
                  pairings: widget.pairings,
                  activePairing: widget.activePairing,
                  connected: widget.connected,
                  onSelectPairing: widget.onSelectPairing,
                  onPairing: widget.onPairing,
                  onNewPairing: widget.onNewPairing,
                ),
                SizedBox(height: verticalGap),
                Expanded(
                  child: ListView(
                    controller: _sidebarScrollController,
                    padding: EdgeInsets.zero,
                    children: [
                      if (_pinnedSessions.isNotEmpty) ...[
                        const _SidebarSectionTitle(title: '置顶'),
                        SizedBox(height: widget.compact ? 5 : 8),
                        for (final session in _pinnedSessions)
                          _SidebarSessionLine(
                            session: session,
                            active: _sameSession(
                              session.id,
                              widget.selectedSessionId,
                            ),
                            icon: RecodexIcons.message,
                            compact: widget.compact,
                            onTap: () => widget.onSelectSession(session),
                          ),
                        SizedBox(height: widget.compact ? 12 : 18),
                      ],
                      _SidebarSectionTitle(
                        title: '项目',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${widget.workspaces.length}',
                              style: TextStyle(
                                color: colors.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 2),
                            LiquidIconButton(
                              icon: RecodexIcons.sync,
                              tooltip: '刷新项目',
                              onPressed: widget.onRefreshProjects,
                              size: 32,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: widget.compact ? 5 : 8),
                      if (widget.workspaces.isEmpty)
                        _WorkspaceLine(
                          name: '暂无项目',
                          path: widget.connected
                              ? '点击右侧刷新按钮重新获取'
                              : '连接 Relay 后同步',
                        )
                      else
                        for (final workspace in widget.workspaces)
                          _WorkspaceBranch(
                            key: _workspaceItemKey(workspace),
                            workspace: workspace,
                            active: _isSelectedWorkspace(workspace),
                            expanded: _isWorkspaceExpanded(workspace),
                            sessions: _sessionsForWorkspace(workspace),
                            selectedSessionId: widget.selectedSessionId,
                            compact: widget.compact,
                            onTap: () => _toggleWorkspace(workspace),
                            onSelectSession: widget.onSelectSession,
                          ),
                      if (_archivedSessions.isNotEmpty) ...[
                        SizedBox(height: widget.compact ? 12 : 18),
                        const _SidebarSectionTitle(title: '归档'),
                        SizedBox(height: widget.compact ? 5 : 8),
                        for (final session in _archivedSessions)
                          _SidebarSessionLine(
                            session: session,
                            active: _sameSession(
                              session.id,
                              widget.selectedSessionId,
                            ),
                            icon: RecodexIcons.archive,
                            compact: widget.compact,
                            onTap: () => widget.onSelectSession(session),
                          ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: widget.compact ? 6 : 10),
                _BottomDock(
                  onSettings: widget.onSettings,
                  themePreference: widget.themePreference,
                  onThemePreferenceChanged: widget.onThemePreferenceChanged,
                ),
                SizedBox(height: widget.compact ? 2 : 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<SessionRecord> get _pinnedSessions => widget.sessions
      .where((session) => session.isPinned && !session.isArchived)
      .toList(growable: false);

  List<SessionRecord> get _archivedSessions => widget.sessions
      .where((session) => session.isArchived)
      .toList(growable: false);

  List<SessionRecord> _sessionsForWorkspace(WorkspaceInfo workspace) {
    final path = _normalizeWorkspaceKey(workspace.path);
    final name = _normalizeWorkspaceKey(workspace.name);
    final strict = widget.sessions.where((session) {
      if (session.isPinned || session.isArchived) return false;
      final value = _normalizeWorkspaceKey(session.workspace);
      return (path.isNotEmpty && value == path) ||
          (name.isNotEmpty && value == name);
    }).toList();
    if (strict.isNotEmpty) return _dedupeSessions(strict);
    final selectedBase = _lastPathSegment(path.isNotEmpty ? path : name);
    if (selectedBase.isEmpty) return const [];
    return _dedupeSessions(
      widget.sessions
          .where(
            (session) =>
                !session.isPinned &&
                !session.isArchived &&
                _lastPathSegment(_normalizeWorkspaceKey(session.workspace)) ==
                    selectedBase,
          )
          .toList(),
    );
  }

  List<SessionRecord> _dedupeSessions(Iterable<SessionRecord> records) {
    final byId = <String, SessionRecord>{};
    final order = <String>[];
    for (final session in records) {
      final id = session.id.trim();
      if (id.isEmpty) continue;
      final previous = byId[id];
      if (previous == null) {
        order.add(id);
        byId[id] = session;
      } else if (session.updatedAtDate.isAfter(previous.updatedAtDate)) {
        byId[id] = session;
      }
    }
    return [for (final id in order) byId[id]!];
  }

  String _normalizeWorkspaceKey(String value) {
    var normalized = value.trim().replaceAll('\\', '/');
    while (normalized.endsWith('/') && normalized.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  String _lastPathSegment(String value) {
    final parts = value.split('/').where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? value : parts.last;
  }
}

class _PairingSwitcher extends StatelessWidget {
  const _PairingSwitcher({
    required this.pairings,
    required this.activePairing,
    required this.connected,
    required this.onSelectPairing,
    required this.onPairing,
    required this.onNewPairing,
  });

  final List<PairingProfile> pairings;
  final PairingProfile? activePairing;
  final bool connected;
  final ValueChanged<PairingProfile> onSelectPairing;
  final VoidCallback onPairing;
  final VoidCallback onNewPairing;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final activeName = activePairing?.displayName ?? '尚未配对';
    final activeSummary = activePairing == null
        ? '添加 Codex 主机'
        : (activePairing!.targetDeviceId.isEmpty
              ? activePairing!.spaceId
              : activePairing!.targetDeviceId);
    return RecodexPopupMenuButton<String>(
      tooltip: '切换配对',
      onSelected: (value) {
        if (value == '__new') {
          onNewPairing();
          return;
        }
        if (value == '__manage') {
          onPairing();
          return;
        }
        final selected = pairings.cast<PairingProfile?>().firstWhere(
          (profile) => profile?.id == value,
          orElse: () => null,
        );
        if (selected != null) onSelectPairing(selected);
      },
      itemBuilder: (context) => [
        if (pairings.isNotEmpty)
          PopupMenuItem<String>(
            enabled: false,
            child: Text(
              '切换配对',
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        for (final profile in pairings)
          PopupMenuItem<String>(
            value: profile.id,
            child: Row(
              children: [
                Icon(
                  profile.id == activePairing?.id
                      ? RecodexIcons.selectedCircle
                      : RecodexIcons.circle,
                  size: 18,
                  color: profile.id == activePairing?.id
                      ? colors.icon
                      : colors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(profile.displayName)),
              ],
            ),
          ),
        if (pairings.isNotEmpty) const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: '__new',
          child: Row(
            children: [
              Icon(RecodexIcons.add, size: 18),
              SizedBox(width: 10),
              Text('新建配对'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: '__manage',
          child: Row(
            children: [
              Icon(RecodexIcons.tune, size: 18),
              SizedBox(width: 10),
              Text('管理配对'),
            ],
          ),
        ),
      ],
      child: Row(
        children: [
          Icon(
            activePairing == null ? RecodexIcons.addLink : RecodexIcons.router,
            color: colors.text,
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                ConnectionDot(
                  connected: connected,
                  label: connected
                      ? '已连接到 Relay'
                      : activeSummary.isEmpty
                      ? '未连接'
                      : activeSummary,
                ),
              ],
            ),
          ),
          Icon(RecodexIcons.switcher, color: colors.textMuted, size: 20),
        ],
      ),
    );
  }
}

class _WorkspaceBranch extends StatelessWidget {
  const _WorkspaceBranch({
    super.key,
    required this.workspace,
    required this.active,
    required this.expanded,
    required this.sessions,
    required this.selectedSessionId,
    required this.onTap,
    required this.onSelectSession,
    this.compact = false,
  });

  final WorkspaceInfo workspace;
  final bool active;
  final bool expanded;
  final List<SessionRecord> sessions;
  final String? selectedSessionId;
  final VoidCallback onTap;
  final ValueChanged<SessionRecord> onSelectSession;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                7,
                compact ? 5 : 8,
                8,
                compact ? 5 : 8,
              ),
              child: Row(
                children: [
                  Icon(
                    expanded ? RecodexIcons.folderOpen : RecodexIcons.folder,
                    size: 19,
                    color: colors.textMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      workspace.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                        color: colors.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(
                  padding: EdgeInsets.only(
                    left: 29,
                    top: compact ? 1 : 2,
                    bottom: compact ? 3 : 5,
                  ),
                  child: sessions.isEmpty
                      ? const _EmptySessionLine()
                      : Column(
                          children: [
                            for (final session in sessions)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: _SessionLine(
                                  session: session,
                                  active:
                                      _sameSession(
                                        session.id,
                                        selectedSessionId,
                                      ) &&
                                      active,
                                  compact: compact,
                                  onTap: () => onSelectSession(session),
                                ),
                              ),
                          ],
                        ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  bool _sameSession(String left, String? right) {
    final normalizedRight = right?.trim();
    return normalizedRight != null &&
        normalizedRight.isNotEmpty &&
        left.trim() == normalizedRight;
  }
}

class _WorkspaceLine extends StatelessWidget {
  const _WorkspaceLine({required this.name, required this.path});

  final String name;
  final String path;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Icon(RecodexIcons.folderOpen, size: 18, color: colors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                Text(
                  path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarSectionTitle extends StatelessWidget {
  const _SidebarSectionTitle({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (trailing != null) ...[const Spacer(), trailing!],
        ],
      ),
    );
  }
}

class _SidebarSessionLine extends StatelessWidget {
  const _SidebarSessionLine({
    required this.session,
    required this.active,
    required this.onTap,
    this.icon = RecodexIcons.message,
    this.compact = false,
  });

  final SessionRecord session;
  final bool active;
  final VoidCallback onTap;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final radius = BorderRadius.circular(9);
    return AnimatedContainer(
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: active
            ? colors.surfaceOverlay.withValues(alpha: 0.86)
            : Colors.transparent,
        borderRadius: radius,
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(7, compact ? 5 : 7, 9, compact ? 5 : 7),
          child: Row(
            children: [
              if (session.isRunning)
                _RunningTaskIndicator(color: colors.icon)
              else
                Icon(icon, size: 19, color: colors.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  session.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.25,
                    fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                    color: colors.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySessionLine extends StatelessWidget {
  const _EmptySessionLine();

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 6, 10, 7),
      child: Text(
        '当前项目暂无任务',
        style: TextStyle(color: colors.textMuted, fontSize: 12.5),
      ),
    );
  }
}

class _SessionLine extends StatelessWidget {
  const _SessionLine({
    required this.session,
    required this.active,
    required this.onTap,
    this.compact = false,
  });

  final SessionRecord session;
  final bool active;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return AnimatedContainer(
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: active
            ? colors.surfaceOverlay.withValues(alpha: 0.86)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(9, compact ? 5 : 7, 9, compact ? 5 : 7),
          child: Row(
            children: [
              if (session.isRunning) ...[
                _RunningTaskIndicator(color: colors.icon),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  session.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.25,
                    fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                    color: colors.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact running-state marker used in the sidebar task rows.
///
/// [CircularProgressIndicator] provides the same subtle rotation treatment as
/// Codex's desktop task list while keeping the marker narrow enough that task
/// titles retain their available width.
class _RunningTaskIndicator extends StatelessWidget {
  const _RunningTaskIndicator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '任务运行中',
      liveRegion: true,
      child: SizedBox(
        width: 15,
        height: 15,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
      ),
    );
  }
}

class _BottomDock extends StatelessWidget {
  const _BottomDock({
    required this.onSettings,
    required this.themePreference,
    required this.onThemePreferenceChanged,
  });

  final VoidCallback onSettings;
  final RecodexThemePreference themePreference;
  final ValueChanged<RecodexThemePreference> onThemePreferenceChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _DockIconButton(
          icon: RecodexIcons.settings,
          tooltip: '设置',
          onTap: onSettings,
        ),
        _ThemeModeToggle(
          preference: themePreference,
          onChanged: onThemePreferenceChanged,
        ),
      ],
    );
  }
}

class _ThemeModeToggle extends StatelessWidget {
  const _ThemeModeToggle({required this.preference, required this.onChanged});

  // Match the compact desktop control order: light, dark, then system.
  static const _options = <RecodexThemePreference>[
    RecodexThemePreference.light,
    RecodexThemePreference.dark,
    RecodexThemePreference.system,
  ];

  final RecodexThemePreference preference;
  final ValueChanged<RecodexThemePreference> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Tooltip(
      message: '当前主题：${preference.label}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceOverlay.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final value in _options)
                _ThemeModeSegment(
                  key: ValueKey<String>('theme-mode-${value.name}'),
                  preference: value,
                  selected:
                      value == preference ||
                      (value == RecodexThemePreference.system &&
                          preference == RecodexThemePreference.scheduled),
                  onPressed: () => onChanged(value),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeModeSegment extends StatelessWidget {
  const _ThemeModeSegment({
    super.key,
    required this.preference,
    required this.selected,
    required this.onPressed,
  });

  final RecodexThemePreference preference;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final radius = BorderRadius.circular(7);
    return Semantics(
      button: true,
      selected: selected,
      label: preference.label,
      child: Tooltip(
        message: preference.label,
        child: Material(
          color: selected
              ? colors.text.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: onPressed,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Icon(
                _themeIcon(preference),
                size: 18,
                color: selected ? colors.icon : colors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _themeIcon(RecodexThemePreference preference) {
    return switch (preference) {
      RecodexThemePreference.system => RecodexIcons.monitor,
      RecodexThemePreference.light => RecodexIcons.sun,
      RecodexThemePreference.dark => RecodexIcons.darkMode,
      RecodexThemePreference.scheduled => RecodexIcons.calendar,
    };
  }
}

class _DockIconButton extends StatelessWidget {
  const _DockIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        iconSize: 22,
        icon: Icon(icon, color: colors.icon),
      ),
    );
  }
}
