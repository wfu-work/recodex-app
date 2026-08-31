import 'package:flutter/material.dart';

import '../models/bridge_models.dart';
import '../theme/recodex_theme.dart';
import 'liquid_glass.dart';
import 'status_chips.dart';

class RemodexDrawer extends StatefulWidget {
  const RemodexDrawer({
    required this.connected,
    required this.pairings,
    required this.activePairing,
    required this.workspaces,
    required this.selectedWorkspace,
    required this.onSelectPairing,
    required this.onSelectWorkspace,
    required this.onPairing,
    required this.onNewPairing,
    required this.onSettings,
    super.key,
  });

  final bool connected;
  final List<PairingProfile> pairings;
  final PairingProfile? activePairing;
  final List<WorkspaceInfo> workspaces;
  final WorkspaceInfo? selectedWorkspace;
  final ValueChanged<PairingProfile> onSelectPairing;
  final ValueChanged<WorkspaceInfo> onSelectWorkspace;
  final VoidCallback onPairing;
  final VoidCallback onNewPairing;
  final VoidCallback onSettings;

  @override
  State<RemodexDrawer> createState() => _RemodexDrawerState();
}

class _RemodexDrawerState extends State<RemodexDrawer> {
  static const double _workspaceRowExtent = 56;
  static const double _selectedWorkspaceTopPadding = 34;

  final ScrollController _workspaceScrollController = ScrollController();
  String? _lastScrolledWorkspaceKey;

  @override
  void initState() {
    super.initState();
    _scheduleScrollToSelected(jump: true);
  }

  @override
  void didUpdateWidget(covariant RemodexDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleScrollToSelected(
      jump:
          oldWidget.selectedWorkspace == null ||
          oldWidget.workspaces.isEmpty != widget.workspaces.isEmpty,
    );
  }

  @override
  void dispose() {
    _workspaceScrollController.dispose();
    super.dispose();
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

  int get _selectedWorkspaceIndex =>
      widget.workspaces.indexWhere(_isSelectedWorkspace);

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
    if (!mounted || !_workspaceScrollController.hasClients) {
      return;
    }
    final index = _selectedWorkspaceIndex;
    if (index < 0) {
      return;
    }
    final position = _workspaceScrollController.position;
    final target = (index * _workspaceRowExtent - _selectedWorkspaceTopPadding)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();

    if (jump) {
      _workspaceScrollController.jumpTo(target);
      return;
    }
    _workspaceScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Drawer(
      width: 292,
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 12, 0),
          child: LiquidGlass(
            radius: 26,
            opacity: 0.78,
            padding: const EdgeInsets.fromLTRB(22, 22, 14, 18),
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
                const SizedBox(height: 30),
                Row(
                  children: [
                    Text(
                      '工作区',
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${widget.workspaces.length}',
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    controller: _workspaceScrollController,
                    padding: EdgeInsets.zero,
                    itemCount: widget.workspaces.isEmpty
                        ? 1
                        : widget.workspaces.length,
                    itemBuilder: (context, index) {
                      if (widget.workspaces.isEmpty) {
                        return const _WorkspaceLine(
                          name: '暂无工作区',
                          path: '连接 Relay 后同步',
                        );
                      }
                      final workspace = widget.workspaces[index];
                      return _WorkspaceLine(
                        name: workspace.name,
                        path: workspace.path,
                        active: _isSelectedWorkspace(workspace),
                        onTap: () => widget.onSelectWorkspace(workspace),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                _BottomDock(
                  onPairing: widget.onPairing,
                  onSettings: widget.onSettings,
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'Remodex v1.0.4',
                    style: TextStyle(
                      color: colors.textMuted.withValues(alpha: 0.86),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    return PopupMenuButton<String>(
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
                fontWeight: FontWeight.w800,
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
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
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
              Icon(Icons.add, size: 18),
              SizedBox(width: 10),
              Text('新建配对'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: '__manage',
          child: Row(
            children: [
              Icon(Icons.tune, size: 18),
              SizedBox(width: 10),
              Text('管理配对'),
            ],
          ),
        ),
      ],
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: const Color(0xffffe7d7),
            child: Icon(
              activePairing == null ? Icons.add_link : Icons.router,
              color: const Color(0xff4b4b4b),
            ),
          ),
          const SizedBox(width: 12),
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
                    fontWeight: FontWeight.w900,
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
          Icon(Icons.unfold_more, color: colors.textMuted, size: 20),
        ],
      ),
    );
  }
}

class _WorkspaceLine extends StatelessWidget {
  const _WorkspaceLine({
    required this.name,
    required this.path,
    this.active = false,
    this.onTap,
  });

  final String name;
  final String path;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final activeColor = colors.icon;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: active
            ? activeColor.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: active
            ? Border.all(color: activeColor.withValues(alpha: 0.26))
            : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(
                active ? Icons.folder : Icons.folder_outlined,
                size: 18,
                color: active ? activeColor : colors.textMuted,
              ),
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
                        fontWeight: FontWeight.w900,
                        color: active ? activeColor : colors.text,
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
        ),
      ),
    );
  }
}

class _BottomDock extends StatelessWidget {
  const _BottomDock({required this.onPairing, required this.onSettings});

  final VoidCallback onPairing;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceOverlay,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colors.glassBorder),
        boxShadow: [
          BoxShadow(
            color: colors.glassShadow,
            offset: const Offset(0, 14),
            blurRadius: 28,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DockButton(
              icon: Icons.devices_outlined,
              label: '配对',
              onTap: onPairing,
            ),
            const SizedBox(height: 6),
            _DockButton(
              icon: Icons.settings_outlined,
              label: '设置',
              onTap: onSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final color = colors.text;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: color, size: 19),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
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
