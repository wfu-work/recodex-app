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
    required this.onSettings,
    required this.onAbout,
    super.key,
  });

  final bool connected;
  final List<WorkspaceInfo> workspaces;
  final WorkspaceInfo? selectedWorkspace;
  final ValueChanged<WorkspaceInfo> onSelectWorkspace;
  final VoidCallback onSettings;
  final VoidCallback onAbout;

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
                const Text(
                  '工作区',
                  style: TextStyle(
                    color: Color(0xff747878),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (workspaces.isEmpty)
                  const _WorkspaceLine(name: '暂无工作区', path: '连接 Bridge 后同步')
                else
                  ...workspaces
                      .take(4)
                      .map(
                        (workspace) => _WorkspaceLine(
                          name: workspace.name,
                          path: workspace.path,
                          active: selectedWorkspace?.name == workspace.name,
                          onTap: () => onSelectWorkspace(workspace),
                        ),
                      ),
                const SizedBox(height: 26),
                _MenuItem(
                  icon: Icons.folder,
                  label: '项目文件',
                  active: true,
                  onTap: () => Navigator.of(context).pop(),
                ),
                _MenuItem(icon: Icons.history, label: '历史记录', onTap: () {}),
                _MenuItem(
                  icon: Icons.menu_book_outlined,
                  label: '文档',
                  onTap: () {},
                ),
                _MenuItem(
                  icon: Icons.devices_outlined,
                  label: '配对',
                  onTap: onSettings,
                ),
                const Spacer(),
                _MenuItem(
                  icon: Icons.settings_outlined,
                  label: '设置',
                  onTap: onSettings,
                ),
                _MenuItem(
                  icon: Icons.info_outline,
                  label: '关于',
                  onTap: onAbout,
                ),
                const SizedBox(height: 10),
                const Text(
                  '项目：Remodex\nv1.0.4',
                  style: TextStyle(
                    color: Color(0xff747878),
                    fontSize: 11,
                    height: 1.35,
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

class _MenuItem extends StatelessWidget {
  const _MenuItem({
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: active
            ? Colors.white.withValues(alpha: 0.82)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          leading: Icon(
            icon,
            color: active ? const Color(0xff005fc7) : null,
            size: 20,
          ),
          title: Text(
            label,
            style: TextStyle(
              color: active ? const Color(0xff005fc7) : const Color(0xff303132),
              fontWeight: FontWeight.w800,
            ),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
