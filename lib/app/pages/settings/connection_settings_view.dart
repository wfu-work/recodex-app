import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../components/recodex_dropdown.dart';
import '../../components/recodex_notice.dart';
import '../../routes/app_pages.dart';
import '../../theme/recodex_theme.dart';
import '../main/bridge_controller.dart';
import '../pairing/pairing_view.dart';
import 'settings_preferences_controller.dart';
import 'settings_widgets.dart';

class ConnectionSettingsPage extends StatelessWidget {
  const ConnectionSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bridge = Get.find<BridgeController>();
    final preferences = Get.isRegistered<SettingsPreferencesController>()
        ? Get.find<SettingsPreferencesController>()
        : Get.put(SettingsPreferencesController(), permanent: true);
    return Obx(
      () => LiquidBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: const LiquidPageAppBar(title: '连接与配对'),
          body: SettingsPageContent(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 34),
              children: [
                _ConnectionHero(
                  connected: bridge.connected.value,
                  pairingName: bridge.activePairing?.displayName,
                ),
                const SizedBox(height: 24),
                const SettingsSectionTitle(
                  title: '配对管理',
                  subtitle: '选择默认主机，并管理 Relay 接入凭证',
                ),
                const SizedBox(height: 10),
                SettingsGroup(
                  children: [
                    SettingsRow(
                      icon: RecodexIcons.devices,
                      title: '配对列表',
                      subtitle: bridge.pairings.isEmpty
                          ? '还没有保存的配对'
                          : '${bridge.pairings.length} 个配对配置',
                      showChevron: true,
                      onTap: () => Get.toNamed(Routes.pairing),
                    ),
                    const SettingsDivider(),
                    SettingsDropdownRow<String>(
                      icon: RecodexIcons.switcher,
                      title: '默认配对',
                      subtitle: bridge.activePairing?.displayName ?? '未选择',
                      value: bridge.activePairingId.value ?? '',
                      options: [
                        for (final profile in bridge.pairings)
                          RecodexDropdownOption<String>(
                            value: profile.id,
                            label: profile.displayName,
                          ),
                      ],
                      onChanged: bridge.switchPairing,
                    ),
                    const SettingsDivider(),
                    SettingsRow(
                      icon: RecodexIcons.addLink,
                      title: '新建配对',
                      subtitle: '连接另一台 Codex 主机',
                      showChevron: true,
                      onTap: () => Get.toNamed(
                        Routes.pairing,
                        arguments: const PairingPageArgs(createNew: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const SettingsSectionTitle(
                  title: '连接策略',
                  subtitle: '控制应用启动和网络恢复后的连接行为',
                ),
                const SizedBox(height: 10),
                SettingsGroup(
                  children: [
                    SettingsToggleRow(
                      icon: RecodexIcons.cloudDone,
                      title: '启动时自动连接',
                      subtitle: '打开应用后自动连接默认配对',
                      value: preferences.autoConnect.value,
                      onChanged: preferences.setAutoConnect,
                    ),
                    const SettingsDivider(),
                    SettingsToggleRow(
                      icon: RecodexIcons.sync,
                      title: '网络恢复后自动重连',
                      subtitle: 'Relay 中断后自动尝试恢复连接',
                      value: preferences.autoReconnect.value,
                      onChanged: preferences.setAutoReconnect,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const SettingsSectionTitle(
                  title: '快速诊断',
                  subtitle: '仅测试当前配对，不会修改保存的配置',
                ),
                const SizedBox(height: 10),
                SettingsCard(
                  padding: const EdgeInsets.fromLTRB(18, 17, 18, 17),
                  child: Row(
                    children: [
                      Icon(
                        bridge.connected.value
                            ? RecodexIcons.verified
                            : RecodexIcons.network,
                        color: bridge.connected.value
                            ? context.recodexColors.success
                            : context.recodexColors.icon,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          bridge.connected.value
                              ? '当前 Relay 已连接'
                              : '检查当前 Relay 和接入端凭证',
                          style: TextStyle(
                            color: context.recodexColors.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            _testCurrentConnection(context, bridge),
                        icon: const Icon(RecodexIcons.network, size: 18),
                        label: const Text('测试'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _testCurrentConnection(
    BuildContext context,
    BridgeController bridge,
  ) async {
    final profile = bridge.activePairing;
    if (profile == null) {
      RecodexNotice.show(
        context,
        '请先创建并选择一个配对。',
        tone: RecodexNoticeTone.warning,
      );
      return;
    }
    final error = bridge.connected.value
        ? await bridge.checkCurrentConnection()
        : await bridge.testConnection(
            inputBaseUrl: profile.baseUrl,
            token: profile.pairingToken,
            inputDeviceName: profile.deviceName,
            inputSpaceId: profile.spaceId,
            inputTargetDeviceId: profile.targetDeviceId,
            inputEndpointId: profile.deviceId,
            inputEndpointType: profile.endpointType,
            inputDeviceKey: profile.deviceKey,
            inputEndpointGrant: profile.endpointGrant,
            inputTokenExpiresAt: profile.tokenExpiresAt,
            inputGrantExpiresAt: profile.grantExpiresAt,
          );
    if (!context.mounted) return;
    RecodexNotice.show(
      context,
      error ?? '连接测试成功，Relay 连接正常。',
      tone: error == null ? RecodexNoticeTone.success : RecodexNoticeTone.error,
    );
  }
}

class _ConnectionHero extends StatelessWidget {
  const _ConnectionHero({required this.connected, this.pairingName});

  final bool connected;
  final String? pairingName;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return SettingsCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(20, 20, 18, 20),
      child: Row(
        children: [
          Icon(
            connected ? RecodexIcons.cloudDone : RecodexIcons.cloudOff,
            color: connected ? colors.success : colors.icon,
            size: 30,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected ? 'Relay 已连接' : '连接与配对',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  pairingName == null ? '还没有选择默认配对' : '当前配对：$pairingName',
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
        ],
      ),
    );
  }
}
