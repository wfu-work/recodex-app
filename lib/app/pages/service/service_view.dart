import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../theme/recodex_theme.dart';
import '../main/bridge_controller.dart';
import '../settings/settings_widgets.dart';

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
                        ? RecodexIcons.cloudDone
                        : RecodexIcons.cloudOff,
                    title: 'Relay 连接',
                    subtitle: controller.connected.value ? '在线' : '未连接',
                    trailing: _StatusDot(connected: controller.connected.value),
                  ),
                  _DividerLine(),
                  _ServiceTile(
                    icon: RecodexIcons.link,
                    title: 'Relay 连接地址',
                    subtitle: controller.baseUrl.value,
                  ),
                  _DividerLine(),
                  _ServiceTile(
                    icon: RecodexIcons.info,
                    title: '协议状态',
                    subtitle: controller.connectionLabel.value,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _ServiceGroup(
                title: '诊断',
                children: [
                  _ServiceTile(
                    icon: RecodexIcons.network,
                    title: '测试 Relay 连接',
                    subtitle: controller.activePairing == null
                        ? '请先创建一个配对'
                        : '验证当前地址、令牌和接入端凭证',
                    trailing: TextButton(
                      onPressed: controller.activePairing == null
                          ? null
                          : () => _testConnection(context, controller),
                      child: const Text('测试'),
                    ),
                  ),
                  if (controller.lastError.value.isNotEmpty) ...[
                    _DividerLine(),
                    _ServiceTile(
                      icon: RecodexIcons.warning,
                      title: '最近错误',
                      subtitle: controller.lastError.value,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              _ServiceGroup(
                title: '工作区',
                children: [
                  _ServiceTile(
                    icon: RecodexIcons.workspaces,
                    title: '工作区',
                    subtitle: '${controller.workspaces.length} 个工作区',
                    trailingText: controller.selectedWorkspace.value?.name,
                  ),
                  _DividerLine(),
                  _ServiceTile(
                    icon: RecodexIcons.accountTree,
                    title: 'Git 分支',
                    subtitle: controller.composerContext.value.branch.isEmpty
                        ? '未读取'
                        : controller.composerContext.value.branch,
                  ),
                  _DividerLine(),
                  _ServiceTile(
                    icon: RecodexIcons.security,
                    title: '权限策略',
                    subtitle: controller.composerContext.value.approvalPolicy,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _ServiceGroup(
                title: '接入端',
                children: [
                  _ServiceTile(
                    icon: controller.hasDeviceKey
                        ? RecodexIcons.verified
                        : RecodexIcons.shieldOff,
                    title: '本机接入端 ID',
                    subtitle: controller.deviceId.value,
                  ),
                  _DividerLine(),
                  _ServiceTile(
                    icon: RecodexIcons.key,
                    title: '接入端私钥',
                    subtitle: controller.hasDeviceKey ? '已保存在安全存储' : '未生成',
                    trailing: TextButton(
                      onPressed: controller.clearStoredCredentials,
                      child: const Text('清除'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _testConnection(
    BuildContext context,
    BridgeController controller,
  ) async {
    final profile = controller.activePairing;
    if (profile == null) return;
    final error = await controller.testConnection(
      inputBaseUrl: profile.baseUrl,
      token: profile.pairingToken,
      inputDeviceName: profile.deviceName,
      inputSpaceId: profile.spaceId,
      inputTargetDeviceId: profile.targetDeviceId,
      inputEndpointId: profile.deviceId,
      inputEndpointType: profile.endpointType,
      inputDeviceKey: profile.deviceKey,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? '连接测试成功，Relay 已接受当前配置。'),
        duration: const Duration(seconds: 3),
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
    return SettingsCard(
      radius: 20,
      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          Icon(
            connected ? RecodexIcons.checkCircle : RecodexIcons.cloudOff,
            color: connected ? colors.success : colors.textMuted,
            size: 30,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected ? 'Relay 在线' : 'Relay 未连接',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  connected ? '可以操作远程 Codex 主机' : '检查 Relay 连接地址和接入端凭证',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w400,
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
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SettingsCard(
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
          Icon(icon, color: colors.icon, size: 21),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
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
                    height: 1.35,
                    fontWeight: FontWeight.w400,
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
      RecodexIcons.circle,
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
