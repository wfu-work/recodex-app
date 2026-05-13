import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../components/liquid_background.dart';
import '../components/liquid_glass.dart';
import '../components/liquid_page_app_bar.dart';
import '../controllers/bridge_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final BridgeController controller = Get.find();

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => LiquidBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: const LiquidPageAppBar(title: '设置'),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(34, 92, 34, 40),
            children: [
              _SettingsOverview(
                connected: controller.connected.value,
                workspaceCount: controller.workspaces.length,
                deviceName: controller.deviceName.value,
              ),
              const SizedBox(height: 30),
              const _SettingsSection(
                icon: Icons.tune,
                title: '运行方式',
                children: [
                  _InfoRow(
                    title: '自动重连',
                    subtitle: '已启用，Bridge 断开后自动恢复连接',
                    icon: Icons.sync,
                  ),
                  SizedBox(height: 18),
                  _InfoRow(
                    title: '历史会话',
                    subtitle: '读取 Recodex 事件和本机 Codex 历史',
                    icon: Icons.history,
                  ),
                  SizedBox(height: 18),
                  _InfoRow(
                    title: '高风险二次确认',
                    subtitle: '提交、推送等写操作默认需要确认',
                    icon: Icons.verified_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 26),
              _SettingsSection(
                icon: Icons.security,
                title: '安全',
                children: [
                  _InfoRow(
                    title: '设备密钥',
                    subtitle: controller.hasDeviceKey ? '已保存' : '未保存',
                    icon: controller.hasDeviceKey
                        ? Icons.verified_user_outlined
                        : Icons.no_encryption_outlined,
                  ),
                  const SizedBox(height: 18),
                  _InfoRow(
                    title: '已授权设备',
                    subtitle: '${controller.devices.length} 台',
                    icon: Icons.devices_outlined,
                  ),
                  const SizedBox(height: 22),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: controller.clearStoredCredentials,
                      icon: const Icon(Icons.logout),
                      label: const Text('清除本机密钥'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              const _SettingsSection(
                icon: Icons.info_outline,
                title: '关于',
                children: [
                  _InfoRow(
                    title: '应用',
                    subtitle: 'Remodex Companion',
                    icon: Icons.terminal,
                  ),
                  SizedBox(height: 18),
                  _InfoRow(
                    title: '版本',
                    subtitle: 'v1.0.4',
                    icon: Icons.new_releases_outlined,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsOverview extends StatelessWidget {
  const _SettingsOverview({
    required this.connected,
    required this.workspaceCount,
    required this.deviceName,
  });

  final bool connected;
  final int workspaceCount;
  final String deviceName;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      radius: 38,
      opacity: 0.74,
      padding: const EdgeInsets.fromLTRB(30, 28, 30, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.86),
                ),
                child: Icon(
                  connected ? Icons.cloud_done_outlined : Icons.cloud_off,
                  color: const Color(0xff005fc7),
                  size: 32,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '应用控制台',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      connected ? 'Bridge 在线' : 'Bridge 未连接',
                      style: const TextStyle(
                        color: Color(0xff747878),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _MetricChip(label: '工作区', value: '$workspaceCount'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricChip(label: '设备', value: deviceName),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      radius: 34,
      opacity: 0.7,
      padding: const EdgeInsets.fromLTRB(30, 28, 30, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xff005fc7), size: 28),
              const SizedBox(width: 14),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xff005fc7),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xff5d6266), size: 24),
        const SizedBox(width: 14),
        Expanded(
          child: _Label(title: title, subtitle: subtitle),
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xff747878),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xff747878), fontSize: 14),
        ),
      ],
    );
  }
}
