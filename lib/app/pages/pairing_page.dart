import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../components/liquid_background.dart';
import '../components/liquid_glass.dart';
import '../components/liquid_page_app_bar.dart';
import '../controllers/bridge_controller.dart';
import '../theme/recodex_theme.dart';

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
    return Obx(() {
      final connected = controller.connected.value;
      final connectionLabel = controller.connectionLabel.value;
      final lastError = controller.lastError.value;
      final busy = controller.busy.value;
      final serviceContext = controller.composerContext.value;
      return LiquidBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: const LiquidPageAppBar(title: '配对'),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding = constraints.maxWidth >= 720
                  ? 48.0
                  : 24.0;
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  92,
                  horizontalPadding,
                  40,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        children: [
                          _PairingHero(connected: connected),
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
                                connected: connected,
                                label: connectionLabel,
                                error: lastError,
                              ),
                              const SizedBox(height: 30),
                              _PairingActionRow(
                                status: _pairingStatus,
                                busy: busy,
                                onFetchPairing: _fetchPairing,
                              ),
                              const SizedBox(height: 12),
                              _PairingHint(
                                text:
                                    '真机连接时 Bridge 地址应使用电脑局域网地址，例如 http://192.168.x.x:8765。',
                                error: false,
                              ),
                            ],
                          ),
                          const SizedBox(height: 34),
                          _PairingCard(
                            icon: Icons.key_outlined,
                            title: '令牌认证',
                            children: [
                              _TokenSettingRow(
                                controller: _tokenController,
                                showToken: _showToken,
                                onToggleToken: () =>
                                    setState(() => _showToken = !_showToken),
                              ),
                              const SizedBox(height: 22),
                              Align(
                                alignment: Alignment.centerRight,
                                child: BluePillButton(
                                  label: busy ? '连接中' : '连接 Bridge',
                                  icon: busy ? Icons.sync : Icons.qr_code_2,
                                  onPressed: busy ? null : _connect,
                                ),
                              ),
                            ],
                          ),
                          if (connected) ...[
                            const SizedBox(height: 34),
                            _PairingCard(
                              icon: Icons.terminal,
                              title: '远程 Codex',
                              children: [
                                _ServiceInfoGrid(
                                  items: [
                                    _ServiceInfoItem(
                                      label: 'Bridge 版本',
                                      value:
                                          serviceContext.bridgeVersion.isEmpty
                                          ? '未知'
                                          : serviceContext.bridgeVersion,
                                      icon: Icons.hub_outlined,
                                    ),
                                    _ServiceInfoItem(
                                      label: 'Codex 版本',
                                      value: serviceContext.codexVersion.isEmpty
                                          ? '未检测到'
                                          : serviceContext.codexVersion,
                                      icon: Icons.terminal,
                                    ),
                                    _ServiceInfoItem(
                                      label: 'API Key',
                                      value: serviceContext.apiKeyConfigured
                                          ? '已配置'
                                          : '未配置',
                                      icon: serviceContext.apiKeyConfigured
                                          ? Icons.key
                                          : Icons.key_off_outlined,
                                      positive: serviceContext.apiKeyConfigured,
                                    ),
                                    _ServiceInfoItem(
                                      label: '默认模型',
                                      value: serviceContext.model,
                                      icon: Icons.memory_outlined,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    });
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

class _PairingActionRow extends StatelessWidget {
  const _PairingActionRow({
    required this.status,
    required this.busy,
    required this.onFetchPairing,
  });

  final String status;
  final bool busy;
  final VoidCallback onFetchPairing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 460;
        final statusText = _PairingHint(
          text: status,
          error: status.contains('失败'),
        );
        final button = BluePillButton(
          label: busy ? '获取中' : '获取配对信息',
          icon: busy ? Icons.sync : Icons.link,
          onPressed: busy ? null : onFetchPairing,
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              statusText,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: button),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: statusText),
            const SizedBox(width: 16),
            button,
          ],
        );
      },
    );
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
    return _ResponsiveSettingRow(
      label: _SettingLabel(title: title, subtitle: subtitle),
      field: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.url,
        onSubmitted: onSubmitted,
        style: TextStyle(
          color: context.recodexColors.icon,
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
        decoration: const InputDecoration(border: InputBorder.none),
      ),
    );
  }
}

class _TokenSettingRow extends StatelessWidget {
  const _TokenSettingRow({
    required this.controller,
    required this.showToken,
    required this.onToggleToken,
  });

  final TextEditingController controller;
  final bool showToken;
  final VoidCallback onToggleToken;

  @override
  Widget build(BuildContext context) {
    return _ResponsiveSettingRow(
      label: const _SettingLabel(title: '配对令牌', subtitle: 'Bridge 生成的短期令牌'),
      field: TextField(
        controller: controller,
        obscureText: !showToken,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          hintText: '输入配对令牌',
          suffixIcon: IconButton(
            tooltip: showToken ? '隐藏令牌' : '显示令牌',
            onPressed: onToggleToken,
            icon: Icon(showToken ? Icons.visibility_off : Icons.visibility),
          ),
        ),
      ),
    );
  }
}

class _ResponsiveSettingRow extends StatelessWidget {
  const _ResponsiveSettingRow({required this.label, required this.field});

  final Widget label;
  final Widget field;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [label, const SizedBox(height: 12), field],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 180, child: label),
            const SizedBox(width: 22),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: field,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PairingHint extends StatelessWidget {
  const _PairingHint({required this.text, required this.error});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Text(
      text,
      style: TextStyle(
        color: error ? colors.error : colors.textMuted,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
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
    final colors = context.recodexColors;
    final color = connected
        ? colors.success
        : label == 'connecting' || label == 'auth' || label == 'reconnecting'
        ? colors.icon
        : colors.error;
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final badge = Column(
          crossAxisAlignment: constraints.maxWidth < 520
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
                textAlign: constraints.maxWidth < 520
                    ? TextAlign.left
                    : TextAlign.right,
                style: TextStyle(
                  color: colors.error,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        );
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SettingLabel(title: '连接状态', subtitle: 'Bridge 实时状态'),
              const SizedBox(height: 12),
              badge,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: 180,
              child: _SettingLabel(title: '连接状态', subtitle: 'Bridge 实时状态'),
            ),
            const SizedBox(width: 22),
            Expanded(child: badge),
          ],
        );
      },
    );
  }
}

class _SettingLabel extends StatelessWidget {
  const _SettingLabel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.text,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.textMuted, fontSize: 15),
        ),
      ],
    );
  }
}

class _ServiceInfoItem {
  const _ServiceInfoItem({
    required this.label,
    required this.value,
    required this.icon,
    this.positive = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool positive;
}

class _ServiceInfoGrid extends StatelessWidget {
  const _ServiceInfoGrid({required this.items});

  final List<_ServiceInfoItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 2 : 1;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in items)
              SizedBox(
                width: columns == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 12) / 2,
                child: _ServiceInfoTile(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _ServiceInfoTile extends StatelessWidget {
  const _ServiceInfoTile({required this.item});

  final _ServiceInfoItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final accent = item.positive ? colors.success : colors.icon;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceOverlay.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.glassBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(item.icon, color: accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
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
