import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_glass.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../theme/recodex_theme.dart';
import '../main/bridge_controller.dart';

class ServicePage extends StatelessWidget {
  const ServicePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<BridgeController>();
    return Obx(
      () => LiquidBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: const LiquidPageAppBar(title: '服务状态'),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
            children: [
              _StatusHero(connected: controller.connected.value),
              const SizedBox(height: 18),
              _ServiceGroup(
                title: '连接',
                children: [
                  _ServiceTile(
                    icon: controller.connected.value
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off,
                    title: 'Relay 连接',
                    subtitle: controller.connected.value ? '在线' : '未连接',
                    trailing: _StatusDot(connected: controller.connected.value),
                  ),
                  _DividerLine(),
                  _ServiceTile(
                    icon: Icons.link_outlined,
                    title: 'Relay 地址',
                    subtitle: controller.baseUrl.value,
                  ),
                  _DividerLine(),
                  _ServiceTile(
                    icon: Icons.info_outline,
                    title: '协议状态',
                    subtitle: controller.connectionLabel.value,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _ServiceGroup(
                title: '工作区',
                children: [
                  _ServiceTile(
                    icon: Icons.workspaces_outline,
                    title: '工作区',
                    subtitle: '${controller.workspaces.length} 个工作区',
                    trailingText: controller.selectedWorkspace.value?.name,
                  ),
                  _DividerLine(),
                  _ServiceTile(
                    icon: Icons.account_tree_outlined,
                    title: 'Git 分支',
                    subtitle: controller.composerContext.value.branch.isEmpty
                        ? '未读取'
                        : controller.composerContext.value.branch,
                  ),
                  _DividerLine(),
                  _ServiceTile(
                    icon: Icons.security_outlined,
                    title: '权限策略',
                    subtitle: controller.composerContext.value.approvalPolicy,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _ServiceGroup(
                title: 'Endpoint',
                children: [
                  _ServiceTile(
                    icon: controller.hasDeviceKey
                        ? Icons.verified_user_outlined
                        : Icons.no_encryption_outlined,
                    title: '本机 App Endpoint',
                    subtitle: controller.deviceId.value,
                  ),
                  _DividerLine(),
                  _ServiceTile(
                    icon: Icons.key_outlined,
                    title: 'Endpoint 私钥',
                    subtitle: controller.hasDeviceKey ? '已保存在安全存储' : '未生成',
                    trailing: TextButton(
                      onPressed: controller.clearStoredCredentials,
                      child: const Text('清除'),
                    ),
                  ),
                ],
              ),
              if (controller.lastError.value.isNotEmpty) ...[
                const SizedBox(height: 18),
                _ServiceGroup(
                  title: '错误',
                  children: [
                    _ServiceTile(
                      icon: Icons.warning_amber_rounded,
                      title: '最近错误',
                      subtitle: controller.lastError.value,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return LiquidGlass(
      radius: 28,
      opacity: 0.7,
      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (connected ? colors.success : colors.textMuted).withValues(
                alpha: 0.16,
              ),
            ),
            child: Icon(
              connected ? Icons.check_circle_outline : Icons.cloud_off,
              color: connected ? colors.success : colors.textMuted,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected ? 'Relay 在线' : 'Relay 未连接',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  connected ? '可以操作远程 Codex 主机' : '检查 Relay 地址和 Endpoint 凭证',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceGroup extends StatelessWidget {
  const _ServiceGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Text(
            title,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        LiquidGlass(
          radius: 24,
          opacity: 0.66,
          padding: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.trailingText,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
      child: Row(
        children: [
          Icon(icon, color: colors.icon, size: 23),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
          if (trailingText != null)
            Flexible(
              child: Text(
                trailingText!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Icon(
      Icons.circle,
      size: 12,
      color: connected ? colors.success : colors.textMuted,
    );
  }
}

class _DividerLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Divider(
      height: 1,
      indent: 53,
      color: colors.textMuted.withValues(alpha: 0.16),
    );
  }
}
