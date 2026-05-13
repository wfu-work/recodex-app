import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../components/liquid_background.dart';
import '../components/liquid_glass.dart';
import '../components/liquid_page_app_bar.dart';
import '../controllers/bridge_controller.dart';

class PairingPage extends StatefulWidget {
  const PairingPage({super.key});

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final BridgeController controller = Get.find();
  late final TextEditingController _baseUrlController;
  late final TextEditingController _tokenController;
  bool _showToken = false;
  String _pairingStatus = '';

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
          appBar: const LiquidPageAppBar(title: '配对'),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(36, 92, 36, 40),
            children: [
              _PairingHero(connected: controller.connected.value),
              const SizedBox(height: 34),
              _PairingCard(
                icon: Icons.router_outlined,
                title: 'Bridge 连接',
                children: [
                  _TextSettingRow(
                    title: 'Bridge 地址',
                    subtitle: '本机或局域网网桥',
                    controller: _baseUrlController,
                    onSubmitted: (_) => _connect(),
                  ),
                  const SizedBox(height: 24),
                  _ConnectionStatusRow(
                    connected: controller.connected.value,
                    label: controller.connectionLabel.value,
                    error: controller.lastError.value,
                  ),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _pairingStatus,
                          style: TextStyle(
                            color: _pairingStatus.contains('失败')
                                ? const Color(0xffba1a1a)
                                : const Color(0xff747878),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      BluePillButton(
                        label: controller.busy.value ? '获取中' : '获取配对信息',
                        icon: controller.busy.value ? Icons.sync : Icons.link,
                        onPressed: controller.busy.value ? null : _fetchPairing,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '真机连接时 Bridge 地址应使用电脑局域网地址，例如 http://192.168.x.x:8765。',
                    style: TextStyle(
                      color: Color(0xff747878),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 34),
              _PairingCard(
                icon: Icons.key_outlined,
                title: '令牌认证',
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: _SettingLabel(
                          title: '配对令牌',
                          subtitle: 'Bridge 生成的短期令牌',
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: TextField(
                          controller: _tokenController,
                          obscureText: !_showToken,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            hintText: '输入配对令牌',
                            suffixIcon: IconButton(
                              tooltip: _showToken ? '隐藏令牌' : '显示令牌',
                              onPressed: () =>
                                  setState(() => _showToken = !_showToken),
                              icon: Icon(
                                _showToken
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Align(
                    alignment: Alignment.centerRight,
                    child: BluePillButton(
                      label: controller.busy.value ? '连接中' : '连接 Bridge',
                      icon: controller.busy.value
                          ? Icons.sync
                          : Icons.qr_code_2,
                      onPressed: controller.busy.value ? null : _connect,
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

  void _connect() {
    controller.connect(
      inputBaseUrl: _baseUrlController.text,
      token: _tokenController.text,
      inputDeviceName: controller.deviceName.value,
    );
  }

  Future<void> _fetchPairing() async {
    setState(() => _pairingStatus = '正在获取配对信息...');
    final info = await controller.fetchPairing(_baseUrlController.text);
    if (!mounted) return;
    if (info == null) {
      setState(() {
        _pairingStatus = controller.lastError.value.isEmpty
            ? '获取失败，请检查 Bridge 地址和后台是否启动。'
            : '获取失败：${controller.lastError.value}';
      });
      return;
    }
    _baseUrlController.text = info.baseUrl;
    _tokenController.text = info.token;
    setState(() {
      _showToken = true;
      _pairingStatus = info.token.isEmpty
          ? '未获取到令牌，请重启或刷新 Bridge 配对窗口。'
          : '已获取新令牌。';
    });
  }
}

class _PairingHero extends StatelessWidget {
  const _PairingHero({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      radius: 38,
      opacity: 0.72,
      padding: const EdgeInsets.fromLTRB(30, 28, 30, 28),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.84),
            ),
            child: Icon(
              connected ? Icons.link : Icons.link_off,
              color: const Color(0xff005fc7),
              size: 34,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected ? 'Bridge 已连接' : '连接你的本地 Bridge',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '完成配对后，App 会保存设备密钥并自动重连。',
                  style: TextStyle(
                    color: Color(0xff747878),
                    fontSize: 14,
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

class _PairingCard extends StatelessWidget {
  const _PairingCard({
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
      opacity: 0.72,
      padding: const EdgeInsets.fromLTRB(34, 32, 34, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xff005fc7), size: 30),
              const SizedBox(width: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xff005fc7),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 34),
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
          width: 260,
          child: TextField(
            controller: controller,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.url,
            onSubmitted: onSubmitted,
            style: const TextStyle(
              color: Color(0xff005fc7),
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
            decoration: const InputDecoration(border: InputBorder.none),
          ),
        ),
      ],
    );
  }
}

class _ConnectionStatusRow extends StatelessWidget {
  const _ConnectionStatusRow({
    required this.connected,
    required this.label,
    required this.error,
  });

  final bool connected;
  final String label;
  final String error;

  @override
  Widget build(BuildContext context) {
    final color = connected
        ? const Color(0xff0b7a3b)
        : label == 'connecting' || label == 'auth' || label == 'reconnecting'
        ? const Color(0xff005fc7)
        : const Color(0xffba1a1a);
    final text = connected
        ? '已连接'
        : label == 'connecting'
        ? '正在连接'
        : label == 'auth'
        ? '正在认证'
        : label == 'reconnecting'
        ? '正在重连'
        : label == 'failed'
        ? '连接失败'
        : '未连接';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: _SettingLabel(title: '连接状态', subtitle: 'Bridge 实时状态'),
        ),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      connected ? Icons.check_circle : Icons.info_outline,
                      size: 18,
                      color: color,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      text,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              if (error.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  error,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xffba1a1a),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
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
