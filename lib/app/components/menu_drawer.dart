import 'package:flutter/material.dart';

import '../models/bridge_models.dart';
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
                        const Text(
                          '主分支',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
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
                    const Text(
                      '工作区',
                      style: TextStyle(
                        color: Color(0xff747878),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${workspaces.length}',
                      style: const TextStyle(
                        color: Color(0xff747878),
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
                      color: const Color(0xff747878).withValues(alpha: 0.86),
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
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              active ? Icons.folder : Icons.folder_outlined,
              size: 18,
              color: active ? const Color(0xff005fc7) : const Color(0xff747878),
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
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xff747878),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff9da8b7).withValues(alpha: 0.14),
            offset: const Offset(0, 14),
            blurRadius: 28,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            Expanded(
              child: _DockButton(
                icon: Icons.devices_outlined,
                label: '配对',
                onTap: onPairing,
                active: true,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _DockButton(
                icon: Icons.settings_outlined,
                label: '设置',
                onTap: onSettings,
              ),
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
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xff005fc7) : const Color(0xff303132);
    return Material(
      color: active ? Colors.white.withValues(alpha: 0.86) : Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 19),
              const SizedBox(width: 7),
              Flexible(
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
