import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_glass.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../theme/recodex_theme.dart';
import '../main/bridge_controller.dart';
import 'settings_preferences_controller.dart';
import 'settings_widgets.dart';

class SecuritySettingsPage extends StatelessWidget {
  const SecuritySettingsPage({super.key});

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
          appBar: const LiquidPageAppBar(title: '数据与安全'),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 34),
                children: [
                  _SecurityHero(bridge: bridge),
                  const SizedBox(height: 24),
                  const SettingsSectionTitle(
                    title: '凭证管理',
                    subtitle: '私钥只保存在本机安全存储，不会上传到 Relay',
                  ),
                  const SizedBox(height: 10),
                  SettingsGroup(
                    children: [
                      SettingsRow(
                        icon: bridge.hasDeviceKey
                            ? RecodexIcons.verified
                            : RecodexIcons.shieldOff,
                        title: '接入端私钥',
                        subtitle: bridge.hasDeviceKey
                            ? '已保存在安全存储'
                            : '当前没有可用的接入端私钥',
                        trailing: TextButton(
                          onPressed: bridge.hasDeviceKey
                              ? () => _confirmClearCredentials(context, bridge)
                              : null,
                          child: const Text('清除'),
                        ),
                      ),
                      const SettingsDivider(),
                      SettingsRow(
                        icon: RecodexIcons.key,
                        title: '当前公钥',
                        subtitle: bridge.endpointPublicKey.value.isEmpty
                            ? '未生成'
                            : _shorten(bridge.endpointPublicKey.value),
                        trailing: TextButton(
                          onPressed: bridge.endpointPublicKey.value.isEmpty
                              ? null
                              : () => _copy(
                                  context,
                                  bridge.endpointPublicKey.value,
                                  '公钥已复制',
                                ),
                          child: const Text('复制'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const SettingsSectionTitle(
                    title: '配置数据',
                    subtitle: '导出时会自动移除私钥、令牌等敏感字段',
                  ),
                  const SizedBox(height: 10),
                  SettingsGroup(
                    children: [
                      SettingsRow(
                        icon: RecodexIcons.fileText,
                        title: '导出脱敏配置',
                        subtitle: bridge.pairings.isEmpty
                            ? '当前没有可导出的配对'
                            : '${bridge.pairings.length} 个配对配置',
                        showChevron: true,
                        onTap: () => _showExport(context, bridge),
                      ),
                      const SettingsDivider(),
                      SettingsRow(
                        icon: RecodexIcons.shield,
                        title: '敏感操作前确认',
                        subtitle: '清除凭证等操作需要再次确认',
                        trailing: Switch(
                          value: preferences.confirmSensitiveActions.value,
                          onChanged: preferences.setConfirmSensitiveActions,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  LiquidGlass(
                    radius: 24,
                    opacity: 0.60,
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    child: Text(
                      '如果你怀疑连接令牌已经泄露，请先在 relay-web 撤销旧令牌，再清除本机凭证并重新配对。',
                      style: TextStyle(
                        color: context.recodexColors.textMuted,
                        fontSize: 12,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClearCredentials(
    BuildContext context,
    BridgeController bridge,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除本机凭证？'),
        content: const Text('当前配对的私钥、连接令牌和授权凭证都会被移除，需要重新配对才能连接。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await bridge.clearStoredCredentials();
  }

  Future<void> _showExport(
    BuildContext context,
    BridgeController bridge,
  ) async {
    final profiles = bridge.pairings
        .map(
          (profile) => {
            'id': profile.id,
            'name': profile.name,
            'baseUrl': profile.baseUrl,
            'spaceId': profile.spaceId,
            'deviceName': profile.deviceName,
            'deviceId': profile.deviceId,
            'targetDeviceId': profile.targetDeviceId,
            'endpointType': profile.endpointType,
          },
        )
        .toList(growable: false);
    final encoded = const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'activePairingId': bridge.activePairingId.value,
      'pairings': profiles,
    });
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('脱敏配置'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: SelectableText(
              encoded,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: encoded));
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('复制配置'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _shorten(String value) {
    if (value.length <= 22) return value;
    return '${value.substring(0, 10)}…${value.substring(value.length - 8)}';
  }
}

class _SecurityHero extends StatelessWidget {
  const _SecurityHero({required this.bridge});

  final BridgeController bridge;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return LiquidGlass(
      radius: 28,
      opacity: 0.72,
      padding: const EdgeInsets.fromLTRB(20, 20, 18, 20),
      child: Row(
        children: [
          Icon(RecodexIcons.security, color: colors.icon, size: 30),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '数据与安全',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  bridge.hasDeviceKey ? '本机凭证已受安全存储保护' : '尚未生成本机接入端凭证',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
