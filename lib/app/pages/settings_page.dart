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
  late final TextEditingController _baseUrlController;
  late final TextEditingController _tokenController;
  bool _confirmRisk = true;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: controller.baseUrl.value);
    _tokenController = TextEditingController();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => LiquidBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: const LiquidPageAppBar(title: '设置', showMore: true),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(36, 92, 36, 40),
            children: [
              _SettingsCard(
                icon: Icons.router_outlined,
                title: '连接设置',
                children: [
                  _TextSettingRow(
                    title: 'Bridge 地址',
                    subtitle: '本地网桥连接',
                    controller: _baseUrlController,
                    onSubmitted: (_) => _connect(),
                  ),
                  const SizedBox(height: 34),
                  const _ValueRow(
                    title: 'Relay 服务',
                    subtitle: '远程中继代理',
                    value: '已禁用',
                    mutedDot: true,
                  ),
                ],
              ),
              const SizedBox(height: 44),
              _SettingsCard(
                icon: Icons.shield_outlined,
                title: '安全与配对',
                children: [
                  _ValueRow(
                    title: '已授权设备',
                    subtitle: '当前配对设备',
                    value: controller.deviceName.value,
                    icon: Icons.phone_iphone,
                  ),
                  const SizedBox(height: 34),
                  Row(
                    children: [
                      const Expanded(
                        child: _SettingLabel(
                          title: '重新配对',
                          subtitle: '使用 Bridge 生成的令牌',
                        ),
                      ),
                      SizedBox(
                        width: 230,
                        child: TextField(
                          controller: _tokenController,
                          obscureText: true,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(hintText: '输入配对令牌'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: BluePillButton(
                      label: '连接 Bridge',
                      icon: Icons.qr_code_2,
                      onPressed: _connect,
                    ),
                  ),
                  const SizedBox(height: 34),
                  Row(
                    children: [
                      const Expanded(
                        child: _SettingLabel(
                          title: '二次确认',
                          subtitle: '高风险操作需确认',
                        ),
                      ),
                      Switch(
                        value: _confirmRisk,
                        activeThumbColor: const Color(0xff005fc7),
                        onChanged: (value) =>
                            setState(() => _confirmRisk = value),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _connect() {
    controller.connect(
      inputBaseUrl: _baseUrlController.text,
      token: _tokenController.text,
      inputDeviceName: controller.deviceName.value,
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
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
      radius: 54,
      opacity: 0.72,
      padding: const EdgeInsets.fromLTRB(48, 46, 48, 42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xff005fc7), size: 34),
              const SizedBox(width: 22),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xff005fc7),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 66),
          ...children,
        ],
      ),
    );
  }
}

class _TextSettingRow extends StatelessWidget {
  const _TextSettingRow({
    required this.title,
    required this.subtitle,
    required this.controller,
    required this.onSubmitted,
  });

  final String title;
  final String subtitle;
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SettingLabel(title: title, subtitle: subtitle),
        ),
        SizedBox(
          width: 230,
          child: TextField(
            controller: controller,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.url,
            onSubmitted: onSubmitted,
            style: const TextStyle(
              color: Color(0xff005fc7),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
            decoration: const InputDecoration(border: InputBorder.none),
          ),
        ),
      ],
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.title,
    required this.subtitle,
    required this.value,
    this.icon,
    this.mutedDot = false,
  });

  final String title;
  final String subtitle;
  final String value;
  final IconData? icon;
  final bool mutedDot;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SettingLabel(title: title, subtitle: subtitle),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xffeef3fb),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: const Color(0xff005fc7)),
                const SizedBox(width: 8),
              ],
              if (mutedDot) ...[
                const Icon(Icons.circle, size: 13, color: Color(0xffc3c8cc)),
                const SizedBox(width: 12),
              ],
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xff005fc7),
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingLabel extends StatelessWidget {
  const _SettingLabel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xff747878), fontSize: 15),
        ),
      ],
    );
  }
}
