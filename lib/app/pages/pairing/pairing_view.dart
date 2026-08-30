import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_glass.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../theme/recodex_theme.dart';
import '../main/bridge_controller.dart';

class PairingPage extends StatefulWidget {
  const PairingPage({super.key});

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final BridgeController controller = Get.find();
  late final TextEditingController _baseUrlController;
  late final TextEditingController _spaceIdController;
  late final TextEditingController _targetDeviceController;
  late final TextEditingController _endpointIdController;
  late final TextEditingController _tokenController;
  late final TextEditingController _grantController;
  bool _showToken = false;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: controller.baseUrl.value);
    _spaceIdController = TextEditingController(text: controller.spaceId.value);
    _targetDeviceController = TextEditingController(
      text: controller.targetDeviceId.value,
    );
    _endpointIdController = TextEditingController(
      text: controller.deviceId.value,
    );
    _tokenController = TextEditingController(
      text: controller.pairingToken.value,
    );
    _grantController = TextEditingController(
      text: controller.endpointGrant.value,
    );
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _spaceIdController.dispose();
    _targetDeviceController.dispose();
    _endpointIdController.dispose();
    _tokenController.dispose();
    _grantController.dispose();
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
                  32,
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
                            title: 'Relay 连接',
                            children: [
                              _TextSettingRow(
                                title: 'Relay 地址',
                                subtitle: 'Relay Protocol v1 /v1/connect',
                                controller: _baseUrlController,
                                onSubmitted: (_) => _connect(),
                              ),
                              const SizedBox(height: 24),
                              _TextSettingRow(
                                title: 'Space ID',
                                subtitle: '与 Relay Connect Token 一致',
                                controller: _spaceIdController,
                                onSubmitted: (_) => _connect(),
                              ),
                              const SizedBox(height: 24),
                              _TextSettingRow(
                                title: '目标 Codex 主机 Endpoint',
                                subtitle: '插件配置中的 host deviceId',
                                controller: _targetDeviceController,
                                onSubmitted: (_) => _connect(),
                              ),
                              const SizedBox(height: 24),
                              _TextSettingRow(
                                title: '本机 App Endpoint',
                                subtitle: '需与 Relay Token 的 endpointId 完全一致',
                                controller: _endpointIdController,
                                onSubmitted: (_) => _connect(),
                              ),
                              const SizedBox(height: 24),
                              _ConnectionStatusRow(
                                connected: connected,
                                label: connectionLabel,
                                error: lastError,
                              ),
                              const SizedBox(height: 30),
                              _PairingHint(
                                text:
                                    'Relay 地址示例：wss://relay.example.com/v1/connect；公网 Relay 必须使用 WSS。',
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
                              const SizedBox(height: 18),
                              _TextSettingRow(
                                title: 'Endpoint Grant',
                                subtitle: '可选，用于 Token 到期后自动续期',
                                controller: _grantController,
                                onSubmitted: (_) => _connect(),
                              ),
                              const SizedBox(height: 18),
                              _PairingHint(
                                text:
                                    '本机 Endpoint ID：${controller.deviceId.value}\nEndpoint 公钥：${controller.endpointPublicKey.value.isEmpty ? '连接时生成' : controller.endpointPublicKey.value}',
                                error: false,
                              ),
                              const SizedBox(height: 22),
                              Align(
                                alignment: Alignment.centerRight,
                                child: BluePillButton(
                                  label: busy ? '连接中' : '连接 Relay',
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
                                    _ServiceInfoItem(
                                      label: '今日用量',
                                      value: _formatTokenCount(
                                        serviceContext.usage.todayTokens,
                                      ),
                                      icon: Icons.today_outlined,
                                    ),
                                    _ServiceInfoItem(
                                      label: '本月用量',
                                      value: _formatTokenCount(
                                        serviceContext.usage.monthTokens,
                                      ),
                                      icon: Icons.calendar_month_outlined,
                                    ),
                                    _ServiceInfoItem(
                                      label: '估算费用',
                                      value: serviceContext.usage.rateConfigured
                                          ? _formatCost(
                                              serviceContext.usage.monthCost,
                                            )
                                          : '未配置费率',
                                      icon: Icons.payments_outlined,
                                    ),
                                    _ServiceInfoItem(
                                      label: '最近更新',
                                      value: _formatUsageTime(
                                        serviceContext.usage.lastUpdated,
                                      ),
                                      icon: Icons.update,
                                    ),
                                    _ServiceInfoItem(
                                      label: '用量读取',
                                      value: serviceContext.usage.canReadUsage
                                          ? '可读取'
                                          : '不可读取',
                                      icon: serviceContext.usage.canReadUsage
                                          ? Icons.check_circle_outline
                                          : Icons.error_outline,
                                      positive:
                                          serviceContext.usage.canReadUsage,
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
      inputSpaceId: _spaceIdController.text,
      inputTargetDeviceId: _targetDeviceController.text,
      inputEndpointId: _endpointIdController.text,
      inputEndpointGrant: _grantController.text,
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
                  connected ? 'Relay 已连接' : '连接你的 Codex 主机',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'App 使用 Ed25519 Endpoint proof 接入 Relay，与桌面插件通过 codex.v1 通信。',
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
      label: const _SettingLabel(
        title: 'App Connect Token',
        subtitle: 'Relay 为本机 App Endpoint 签发的短期令牌',
      ),
      field: TextField(
        controller: controller,
        obscureText: !showToken,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          hintText: '输入 Connect Token',
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

String _formatTokenCount(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(2)}M tokens';
  }
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K tokens';
  return '$value tokens';
}

String _formatCost(double value) {
  return '\$${value.toStringAsFixed(4)}';
}

String _formatUsageTime(DateTime? value) {
  if (value == null) return '暂无记录';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
}
