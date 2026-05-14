import 'package:flutter/material.dart';

import '../models/bridge_models.dart';
import '../theme/recodex_theme.dart';
import 'liquid_glass.dart';
import 'status_chips.dart';

class RemodexDrawer extends StatelessWidget {
  const RemodexDrawer({
    required this.connected,
    required this.workspaces,
    required this.selectedWorkspace,
    required this.onSelectWorkspace,
    required this.onPairing,
    required this.onSettings,
    super.key,
  });

  final bool connected;
  final List<WorkspaceInfo> workspaces;
  final WorkspaceInfo? selectedWorkspace;
  final ValueChanged<WorkspaceInfo> onSelectWorkspace;
  final VoidCallback onPairing;
  final VoidCallback onSettings;

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
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 19,
                      backgroundColor: Color(0xffffe7d7),
                      child: Icon(Icons.person, color: Color(0xff4b4b4b)),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '主分支',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: colors.text,
                          ),
                        ),
                        ConnectionDot(
                          connected: connected,
                          label: connected ? '已连接到本地链接' : '未连接',
                        ),
                      ],
                    ),
                  ],
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
                      '${workspaces.length}',
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
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      if (workspaces.isEmpty)
                        const _WorkspaceLine(
                          name: '暂无工作区',
                          path: '连接 Bridge 后同步',
                        )
                      else
                        ...workspaces.map(
                          (workspace) => _WorkspaceLine(
                            name: workspace.name,
                            path: workspace.path,
                            active: selectedWorkspace?.name == workspace.name,
                            onTap: () => onSelectWorkspace(workspace),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _BottomDock(onPairing: onPairing, onSettings: onSettings),
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
