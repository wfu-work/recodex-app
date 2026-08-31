import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_glass.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../components/recodex_dropdown.dart';
import '../../models/bridge_models.dart';
import '../../theme/recodex_theme.dart';
import '../main/bridge_controller.dart';

class PairingPageArgs {
  const PairingPageArgs({this.createNew = false, this.pairingId});

  final bool createNew;
  final String? pairingId;
}

class PairingPage extends StatefulWidget {
  const PairingPage({super.key});

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final BridgeController controller = Get.find();
  late final TextEditingController _nameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _spaceIdController;
  late final TextEditingController _targetDeviceController;
  late final TextEditingController _endpointIdController;
  late final TextEditingController _publicKeyController;
  late final TextEditingController _tokenController;
  late final TextEditingController _grantController;
  bool _showToken = false;
  bool _saving = false;
  bool _testing = false;
  bool _preparingKey = false;
  String _draftDeviceKey = '';
  String _activeDraftId = '';
  Future<void>? _keyPreparation;
  _PairingPageMode _mode = _PairingPageMode.list;
  PairingProfile? _editingProfile;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _baseUrlController = TextEditingController();
    _spaceIdController = TextEditingController();
    _targetDeviceController = TextEditingController();
    _endpointIdController = TextEditingController();
    _publicKeyController = TextEditingController();
    _tokenController = TextEditingController();
    _grantController = TextEditingController();
    final args = Get.arguments;
    if (args is PairingPageArgs && (args.createNew || args.pairingId != null)) {
      _openEditor(
        args.createNew ? null : controller.pairingById(args.pairingId!),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _spaceIdController.dispose();
    _targetDeviceController.dispose();
    _endpointIdController.dispose();
    _publicKeyController.dispose();
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
      final title = _mode == _PairingPageMode.list
          ? '配对'
          : (_editingProfile == null ? '新建配对' : '编辑配对');
      return LiquidBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: LiquidPageAppBar(
            title: title,
            onBack: _mode == _PairingPageMode.editor
                ? _showList
                : () => Navigator.of(context).pop(),
          ),
          body: _mode == _PairingPageMode.list
              ? _buildPairingList(context)
              : _buildEditor(
                  context,
                  connected: connected,
                  connectionLabel: connectionLabel,
                  lastError: lastError,
                  busy: busy,
                  serviceContext: serviceContext,
                ),
        ),
      );
    });
  }

  Widget _buildPairingList(BuildContext context) {
    final horizontalPadding = MediaQuery.sizeOf(context).width >= 720
        ? 48.0
        : 24.0;
    final profiles = controller.pairings.toList(growable: false);
    final activeId = controller.activePairingId.value;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        22,
        horizontalPadding,
        32,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PairingListHero(
                  count: profiles.length,
                  connected: controller.connected.value,
                ),
                const SizedBox(height: 20),
                if (profiles.isEmpty)
                  _EmptyPairingCard(onCreate: _newPairing)
                else ...[
                  for (final profile in profiles) ...[
                    _PairingListTile(
                      profile: profile,
                      active: profile.id == activeId,
                      connected:
                          profile.id == activeId && controller.connected.value,
                      busy: profile.id == activeId && controller.busy.value,
                      onSelect: () => controller.switchPairing(profile.id),
                      onEdit: () => _openEditor(profile),
                      onDelete: () => _confirmDelete(profile),
                    ),
                    const SizedBox(height: 14),
                  ],
                  const SizedBox(height: 6),
                  BluePillButton(
                    label: '新建配对',
                    icon: RecodexIcons.add,
                    onPressed: _newPairing,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditor(
    BuildContext context, {
    required bool connected,
    required String connectionLabel,
    required String lastError,
    required bool busy,
    required ComposerContext serviceContext,
  }) {
    final horizontalPadding = MediaQuery.sizeOf(context).width >= 720
        ? 48.0
        : 24.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            22,
            horizontalPadding,
            32,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  children: [
                    _PairingHero(connected: connected),
                    const SizedBox(height: 22),
                    _PairingCard(
                      icon: RecodexIcons.tag,
                      title: '配对信息',
                      children: [
                        _TextSettingRow(
                          title: '配对名称',
                          subtitle: '用于在侧边栏和列表中识别这台主机',
                          controller: _nameController,
                          keyboardType: TextInputType.text,
                          onSubmitted: (_) => _savePairing(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    _PairingCard(
                      icon: RecodexIcons.router,
                      title: 'Relay 连接',
                      children: [
                        _TextSettingRow(
                          title: 'Relay 连接地址',
                          subtitle: 'Relay 协议 v1 /v1/connect',
                          controller: _baseUrlController,
                          onSubmitted: (_) => _savePairing(),
                        ),
                        const SizedBox(height: 20),
                        _TextSettingRow(
                          title: '空间 ID',
                          subtitle: '与连接令牌中的空间 ID 一致',
                          controller: _spaceIdController,
                          onSubmitted: (_) => _savePairing(),
                        ),
                        const SizedBox(height: 20),
                        _TextSettingRow(
                          title: '目标主机接入端 ID',
                          subtitle: '桌面插件登记的主机接入端 ID',
                          controller: _targetDeviceController,
                          onSubmitted: (_) => _savePairing(),
                        ),
                        const SizedBox(height: 20),
                        _TextSettingRow(
                          title: '本机接入端 ID',
                          subtitle: '需与连接令牌中的接入端 ID 完全一致',
                          controller: _endpointIdController,
                          onSubmitted: (_) => _savePairing(),
                        ),
                        const SizedBox(height: 20),
                        _ConnectionStatusRow(
                          connected: connected,
                          label: connectionLabel,
                          error: lastError,
                        ),
                        const SizedBox(height: 30),
                        const _PairingHint(
                          text:
                              'Relay 连接地址示例：wss://relay.example.com/v1/connect；公网 Relay 必须使用 WSS。',
                          error: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    _PairingCard(
                      icon: RecodexIcons.key,
                      title: '连接认证',
                      children: [
                        _PublicKeySettingRow(
                          controller: _publicKeyController,
                          onCopy: _copyPublicKey,
                          preparing: _preparingKey,
                        ),
                        const SizedBox(height: 18),
                        _TokenSettingRow(
                          controller: _tokenController,
                          showToken: _showToken,
                          onToggleToken: () =>
                              setState(() => _showToken = !_showToken),
                        ),
                        const SizedBox(height: 18),
                        _TextSettingRow(
                          title: '接入端授权凭证',
                          subtitle: '可选，用于连接令牌到期后自动续期',
                          controller: _grantController,
                          keyboardType: TextInputType.text,
                          onSubmitted: (_) => _savePairing(),
                        ),
                        const SizedBox(height: 18),
                        _PairingHint(
                          text: '私钥只保存在本机；Relay 仅登记上方的 Ed25519 公钥和连接令牌哈希。',
                          error: false,
                        ),
                        const SizedBox(height: 22),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              OutlinedButton.icon(
                                onPressed:
                                    _testing || _saving || busy || _preparingKey
                                    ? null
                                    : _testConnection,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  side: BorderSide(
                                    color: Theme.of(context).colorScheme.primary
                                        .withValues(alpha: 0.55),
                                  ),
                                  minimumSize: const Size(0, 58),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  shape: const StadiumBorder(),
                                ),
                                icon: _testing
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(RecodexIcons.network),
                                label: Text(_testing ? '测试中' : '测试连接'),
                              ),
                              BluePillButton(
                                label: _saving
                                    ? '保存中'
                                    : busy
                                    ? '连接中'
                                    : _preparingKey
                                    ? '生成密钥中'
                                    : '保存并连接',
                                icon: _saving || busy
                                    ? RecodexIcons.sync
                                    : RecodexIcons.qrCode,
                                onPressed: _saving || busy || _preparingKey
                                    ? null
                                    : _savePairing,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (connected) ...[
                      const SizedBox(height: 22),
                      _PairingCard(
                        icon: RecodexIcons.terminal,
                        title: '远程 Codex',
                        children: [
                          _ServiceInfoGrid(
                            items: [
                              _ServiceInfoItem(
                                label: '网关版本',
                                value: serviceContext.bridgeVersion.isEmpty
                                    ? '未知'
                                    : serviceContext.bridgeVersion,
                                icon: RecodexIcons.network,
                              ),
                              _ServiceInfoItem(
                                label: 'Codex 版本',
                                value: serviceContext.codexVersion.isEmpty
                                    ? '未检测到'
                                    : serviceContext.codexVersion,
                                icon: RecodexIcons.terminal,
                              ),
                              _ServiceInfoItem(
                                label: 'API 密钥',
                                value: serviceContext.apiKeyConfigured
                                    ? '已配置'
                                    : '未配置',
                                icon: serviceContext.apiKeyConfigured
                                    ? RecodexIcons.key
                                    : RecodexIcons.keyOff,
                                positive: serviceContext.apiKeyConfigured,
                              ),
                              _ServiceInfoItem(
                                label: '默认模型',
                                value: serviceContext.model,
                                icon: RecodexIcons.cpu,
                              ),
                              _ServiceInfoItem(
                                label: '今日用量',
                                value: _formatTokenCount(
                                  serviceContext.usage.todayTokens,
                                ),
                                icon: RecodexIcons.calendar,
                              ),
                              _ServiceInfoItem(
                                label: '本月用量',
                                value: _formatTokenCount(
                                  serviceContext.usage.monthTokens,
                                ),
                                icon: RecodexIcons.calendar,
                              ),
                              _ServiceInfoItem(
                                label: '估算费用',
                                value: serviceContext.usage.rateConfigured
                                    ? _formatCost(
                                        serviceContext.usage.monthCost,
                                      )
                                    : '未配置费率',
                                icon: RecodexIcons.payments,
                              ),
                              _ServiceInfoItem(
                                label: '最近更新',
                                value: _formatUsageTime(
                                  serviceContext.usage.lastUpdated,
                                ),
                                icon: RecodexIcons.sync,
                              ),
                              _ServiceInfoItem(
                                label: '用量读取',
                                value: serviceContext.usage.canReadUsage
                                    ? '可读取'
                                    : '不可读取',
                                icon: serviceContext.usage.canReadUsage
                                    ? RecodexIcons.checkCircle
                                    : RecodexIcons.error,
                                positive: serviceContext.usage.canReadUsage,
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
    );
  }

  void _openEditor(PairingProfile? profile) {
    final next = profile ?? controller.createDraftPairing();
    _editingProfile = profile;
    _mode = _PairingPageMode.editor;
    _activeDraftId = next.id;
    _draftDeviceKey = next.deviceKey;
    _preparingKey = true;
    _nameController.text = next.name;
    _baseUrlController.text = next.baseUrl;
    _spaceIdController.text = next.spaceId;
    _targetDeviceController.text = next.targetDeviceId;
    _endpointIdController.text = next.deviceId;
    _publicKeyController.text = next.endpointPublicKey;
    _tokenController.text = next.pairingToken;
    _grantController.text = next.endpointGrant;
    _showToken = false;
    if (mounted) setState(() {});
    _keyPreparation = _prepareEndpointKey(next);
  }

  Future<void> _prepareEndpointKey(PairingProfile profile) async {
    try {
      final material = await controller.prepareEndpointKey(
        deviceKey: profile.deviceKey,
      );
      if (!mounted ||
          _mode != _PairingPageMode.editor ||
          _activeDraftId != profile.id) {
        return;
      }
      _draftDeviceKey = material.deviceKey;
      _publicKeyController.text = material.publicKey;
    } catch (error) {
      if (mounted &&
          _mode == _PairingPageMode.editor &&
          _activeDraftId == profile.id) {
        controller.lastError.value = '生成接入端公钥失败：$error';
      }
    } finally {
      if (mounted &&
          _mode == _PairingPageMode.editor &&
          _activeDraftId == profile.id) {
        setState(() => _preparingKey = false);
      }
    }
  }

  Future<void> _copyPublicKey() async {
    final value = _publicKeyController.text.trim();
    if (value.isEmpty || _preparingKey) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ed25519 公钥已复制'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _testConnection() async {
    if (_testing || _saving || _preparingKey) return;
    final keyPreparation = _keyPreparation;
    if (keyPreparation != null) await keyPreparation;
    if (!mounted || _draftDeviceKey.isEmpty) {
      controller.lastError.value = '接入端公钥尚未生成，请稍后再试。';
      return;
    }
    final spaceId = _spaceIdController.text.trim();
    final targetDeviceId = _targetDeviceController.text.trim();
    final endpointId = _endpointIdController.text.trim();
    final token = _tokenController.text.trim();
    if (spaceId.isEmpty || targetDeviceId.isEmpty || endpointId.isEmpty) {
      controller.lastError.value = '请先填写空间 ID、目标主机接入端 ID 和本机接入端 ID。';
      return;
    }
    if (token.isEmpty) {
      controller.lastError.value = '请先填写连接令牌；接入端授权凭证用于后续自动续期。';
      return;
    }
    setState(() => _testing = true);
    controller.lastError.value = '';
    try {
      final error = await controller.testConnection(
        inputBaseUrl: _baseUrlController.text,
        token: token,
        inputDeviceName: controller.deviceName.value,
        inputSpaceId: spaceId,
        inputTargetDeviceId: targetDeviceId,
        inputEndpointId: endpointId,
        inputEndpointType: controller.endpointType.value,
        inputDeviceKey: _draftDeviceKey,
      );
      if (!mounted) return;
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('连接测试成功，Relay 已接受当前配置。'),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        controller.lastError.value = error;
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _newPairing() => _openEditor(null);

  void _showList() {
    if (!mounted) return;
    setState(() {
      _mode = _PairingPageMode.list;
      _editingProfile = null;
    });
  }

  Future<void> _savePairing() async {
    if (_saving) return;
    final keyPreparation = _keyPreparation;
    if (keyPreparation != null) await keyPreparation;
    if (_draftDeviceKey.isEmpty || _publicKeyController.text.trim().isEmpty) {
      controller.lastError.value = '接入端公钥尚未生成，请稍后再试。';
      return;
    }
    final name = _nameController.text.trim();
    final target = _targetDeviceController.text.trim();
    if (name.isEmpty && target.isEmpty) {
      controller.lastError.value = '请填写配对名称或目标主机接入端 ID。';
      return;
    }
    final base = _editingProfile ?? controller.createDraftPairing();
    final profile = base.copyWith(
      name: name.isEmpty ? target : name,
      baseUrl: _baseUrlController.text,
      spaceId: _spaceIdController.text,
      targetDeviceId: target,
      deviceId: _endpointIdController.text,
      deviceKey: _draftDeviceKey,
      endpointPublicKey: _publicKeyController.text.trim(),
      pairingToken: _tokenController.text,
      endpointGrant: _grantController.text,
    );
    setState(() => _saving = true);
    try {
      await controller.upsertPairing(profile);
      if (mounted) _showList();
    } catch (error) {
      controller.lastError.value = error.toString();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete(PairingProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除“${profile.displayName}”？'),
        content: const Text('此配对保存的令牌和主机连接信息都会从本机移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.deletePairing(profile.id);
  }
}

enum _PairingPageMode { list, editor }

class _PairingListHero extends StatelessWidget {
  const _PairingListHero({required this.count, required this.connected});

  final int count;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return LiquidGlass(
      radius: 32,
      opacity: 0.72,
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.surfaceOverlay.withValues(alpha: 0.88),
            ),
            child: Icon(
              connected ? RecodexIcons.devices : RecodexIcons.devices,
              color: colors.icon,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '你的配对',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(
                  count == 0 ? '添加一台 Codex 主机开始使用' : '$count 个配对配置，可随时切换',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 12,
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

class _EmptyPairingCard extends StatelessWidget {
  const _EmptyPairingCard({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      radius: 28,
      opacity: 0.66,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      child: Column(
        children: [
          Icon(
            RecodexIcons.addLink,
            size: 42,
            color: context.recodexColors.icon,
          ),
          const SizedBox(height: 12),
          Text(
            '还没有配对',
            style: TextStyle(
              color: context.recodexColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '每台 Codex 主机都可以保存为独立配置。',
            style: TextStyle(color: context.recodexColors.textMuted),
          ),
          const SizedBox(height: 20),
          BluePillButton(
            label: '新建配对',
            icon: RecodexIcons.add,
            onPressed: onCreate,
          ),
        ],
      ),
    );
  }
}

class _PairingListTile extends StatelessWidget {
  const _PairingListTile({
    required this.profile,
    required this.active,
    required this.connected,
    required this.busy,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  final PairingProfile profile;
  final bool active;
  final bool connected;
  final bool busy;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final status = connected
        ? '在线'
        : busy
        ? '连接中'
        : profile.isComplete
        ? '离线'
        : '待配置';
    final statusColor = connected || busy ? colors.success : colors.textMuted;
    return LiquidGlass(
      radius: 24,
      opacity: active ? 0.82 : 0.64,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: active
                      ? colors.icon.withValues(alpha: 0.14)
                      : colors.surfaceOverlay,
                  child: Icon(
                    active ? RecodexIcons.link : RecodexIcons.router,
                    color: active ? colors.icon : colors.textMuted,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${profile.spaceId.isEmpty ? '未填写空间 ID' : profile.spaceId} · ${profile.targetDeviceId.isEmpty ? '未填写主机接入端 ID' : profile.targetDeviceId}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.textMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Icon(
                            RecodexIcons.circle,
                            size: 8,
                            color: statusColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            status,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '编辑配对',
                  onPressed: onEdit,
                  icon: Icon(RecodexIcons.edit, color: colors.textMuted),
                ),
                RecodexPopupMenuButton<String>(
                  padding: const EdgeInsets.all(8),
                  tooltip: '更多操作',
                  onSelected: (value) {
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'delete', child: Text('删除配对')),
                  ],
                  icon: Icon(RecodexIcons.more, color: colors.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PairingHero extends StatelessWidget {
  const _PairingHero({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return LiquidGlass(
      radius: 26,
      opacity: 0.72,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.surfaceOverlay.withValues(alpha: 0.88),
            ),
            child: Icon(
              connected ? RecodexIcons.link : RecodexIcons.linkOff,
              color: colors.icon,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected ? 'Relay 已连接' : '连接你的 Codex 主机',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '客户端使用 Ed25519 接入端证明连接 Relay，与桌面插件通过 codex.v1 通信。',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 12,
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
    final colors = context.recodexColors;
    return LiquidGlass(
      radius: 26,
      opacity: 0.72,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.icon, size: 22),
              const SizedBox(width: 10),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colors.icon,
                  fontSize: 17,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }
}

Color _pairingInputFillColor(BuildContext context) {
  final theme = Theme.of(context);
  final colors = context.recodexColors;
  final isDark = theme.brightness == Brightness.dark;
  return Color.alphaBlend(
    colors.icon.withValues(alpha: isDark ? 0.08 : 0.04),
    theme.colorScheme.surfaceContainerHighest,
  );
}

OutlineInputBorder _pairingInputBorder(
  BuildContext context, {
  bool focused = false,
}) {
  final colors = context.recodexColors;
  final theme = Theme.of(context);
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(
      color: focused
          ? theme.colorScheme.primary
          : colors.icon.withValues(alpha: 0.34),
      width: focused ? 1.6 : 1,
    ),
  );
}

InputDecoration _pairingInputDecoration(
  BuildContext context, {
  String? hintText,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    hintText: hintText,
    filled: true,
    fillColor: _pairingInputFillColor(context),
    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
    border: _pairingInputBorder(context),
    enabledBorder: _pairingInputBorder(context),
    focusedBorder: _pairingInputBorder(context, focused: true),
    hintStyle: TextStyle(
      color: context.recodexColors.textMuted,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    suffixIcon: suffixIcon,
  );
}

class _TextSettingRow extends StatelessWidget {
  const _TextSettingRow({
    required this.title,
    required this.subtitle,
    required this.controller,
    required this.onSubmitted,
    this.keyboardType = TextInputType.url,
  });

  final String title;
  final String subtitle;
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final TextInputType keyboardType;

  @override
  Widget build(BuildContext context) {
    return _ResponsiveSettingRow(
      label: _SettingLabel(title: title, subtitle: subtitle),
      field: TextField(
        controller: controller,
        textAlign: TextAlign.left,
        keyboardType: keyboardType,
        onSubmitted: onSubmitted,
        style: TextStyle(
          color: context.recodexColors.icon,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        decoration: _pairingInputDecoration(context),
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
        title: '连接令牌',
        subtitle: 'Relay 为本机客户端签发的短期连接凭证',
      ),
      field: TextField(
        controller: controller,
        obscureText: !showToken,
        textAlign: TextAlign.left,
        style: TextStyle(
          color: context.recodexColors.icon,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        decoration: _pairingInputDecoration(
          context,
          hintText: '输入连接令牌',
          suffixIcon: IconButton(
            tooltip: showToken ? '隐藏令牌' : '显示令牌',
            onPressed: onToggleToken,
            icon: Icon(
              showToken ? RecodexIcons.visibilityOff : RecodexIcons.visibility,
            ),
          ),
        ),
      ),
    );
  }
}

class _PublicKeySettingRow extends StatelessWidget {
  const _PublicKeySettingRow({
    required this.controller,
    required this.onCopy,
    required this.preparing,
  });

  final TextEditingController controller;
  final VoidCallback onCopy;
  final bool preparing;

  @override
  Widget build(BuildContext context) {
    return _ResponsiveSettingRow(
      label: const _SettingLabel(
        title: 'Ed25519 公钥',
        subtitle: '本机生成的接入端公钥，用于在 relay-web 签发连接令牌',
      ),
      field: TextField(
        controller: controller,
        readOnly: true,
        textAlign: TextAlign.left,
        maxLines: 2,
        minLines: 1,
        style: TextStyle(
          color: context.recodexColors.icon,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.15,
        ),
        decoration: _pairingInputDecoration(
          context,
          hintText: preparing ? '正在生成公钥…' : '公钥生成失败，请重试',
          suffixIcon: IconButton(
            tooltip: '复制公钥',
            onPressed: preparing || controller.text.trim().isEmpty
                ? null
                : onCopy,
            icon: const Icon(RecodexIcons.copy),
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    connected ? RecodexIcons.checkCircle : RecodexIcons.info,
                    size: 18,
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    text,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
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
              const _SettingLabel(title: '连接状态', subtitle: '网关实时状态'),
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
              child: _SettingLabel(title: '连接状态', subtitle: '网关实时状态'),
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
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.textMuted, fontSize: 12, height: 1.35),
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
