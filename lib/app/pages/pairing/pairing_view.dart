import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../components/recodex_dropdown.dart';
import '../../components/recodex_notice.dart';
import '../../models/bridge_models.dart';
import '../../services/relay_protocol.dart';
import '../../theme/recodex_theme.dart';
import '../main/bridge_controller.dart';
import '../settings/settings_widgets.dart';

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
    final profiles = controller.pairings.toList(growable: false);
    final activeId = controller.activePairingId.value;
    return _PairingPageContent(
      key: const ValueKey('pairing-list'),
      children: [
        _PairingIntro(
          title: '你的配对',
          subtitle: profiles.isEmpty
              ? '连接主机，在手机上继续 Codex 任务。'
              : '已保存 ${profiles.length} 个配对，点按卡片管理连接。',
        ),
        const SizedBox(height: 20),
        if (profiles.isEmpty)
          _EmptyPairingCard(onCreate: _newPairing)
        else ...[
          for (final profile in profiles) ...[
            _PairingListTile(
              profile: profile,
              active: profile.id == activeId,
              connected: profile.id == activeId && controller.connected.value,
              busy: profile.id == activeId && controller.busy.value,
              onSelect: () => controller.switchPairing(profile.id),
              onEdit: () => _openEditor(profile),
              onDelete: () => _confirmDelete(profile),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          _PairingActionButton(
            label: '新建配对',
            icon: RecodexIcons.add,
            onPressed: _newPairing,
          ),
        ],
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
    final currentProfile =
        _editingProfile != null &&
        _editingProfile!.id == controller.activePairingId.value;
    final showRemote = currentProfile && connected;
    final unavailable = _testing || _saving || busy || _preparingKey;
    return _PairingPageContent(
      key: ValueKey('pairing-editor:$_activeDraftId'),
      children: [
        _PairingIntro(
          title: _editingProfile?.displayName ?? '连接你的 Codex 主机',
          subtitle: '填写 Relay 连接信息与凭证，保存后即可连接。',
        ),
        const SizedBox(height: 20),
        _PairingCard(
          icon: RecodexIcons.router,
          title: '连接信息',
          children: [
            _TextSettingRow(
              title: '配对名称',
              subtitle: '给这台主机一个容易识别的名称',
              controller: _nameController,
              keyboardType: TextInputType.text,
              onSubmitted: (_) => _savePairing(),
            ),
            const SizedBox(height: 16),
            _TextSettingRow(
              title: 'Relay 连接地址',
              subtitle: '例如 wss://relay.example.com/v1/connect',
              controller: _baseUrlController,
              onSubmitted: (_) => _savePairing(),
            ),
            const SizedBox(height: 16),
            _TextSettingRow(
              title: '空间 ID',
              subtitle: '与连接令牌中的空间一致',
              controller: _spaceIdController,
              onSubmitted: (_) => _savePairing(),
            ),
            const SizedBox(height: 16),
            _TextSettingRow(
              title: '目标主机接入端 ID',
              subtitle: '桌面插件登记的主机 ID',
              controller: _targetDeviceController,
              onSubmitted: (_) => _savePairing(),
            ),
            const SizedBox(height: 16),
            _TextSettingRow(
              title: '本机接入端 ID',
              subtitle: '与为本机签发的连接令牌一致',
              controller: _endpointIdController,
              onSubmitted: (_) => _savePairing(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _PairingCard(
          icon: RecodexIcons.key,
          title: '连接认证',
          children: [
            _PublicKeySettingRow(
              controller: _publicKeyController,
              onCopy: _copyPublicKey,
              preparing: _preparingKey,
            ),
            const SizedBox(height: 16),
            _TokenSettingRow(
              controller: _tokenController,
              showToken: _showToken,
              onToggleToken: () => setState(() => _showToken = !_showToken),
            ),
            const SizedBox(height: 16),
            _TextSettingRow(
              title: '接入端授权凭证',
              subtitle: 'Endpoint Grant · 用于自动续期连接令牌',
              controller: _grantController,
              keyboardType: TextInputType.text,
              onSubmitted: (_) => _savePairing(),
            ),
            const SizedBox(height: 12),
            const _PairingHint(text: '建议同时保存授权凭证，令牌到期后可自动续期。私钥仅保存在本机。'),
          ],
        ),
        const SizedBox(height: 16),
        _PairingActions(
          testing: _testing,
          saving: _saving,
          busy: busy,
          preparingKey: _preparingKey,
          onTest: unavailable ? null : _testConnection,
          onSave: unavailable ? null : _savePairing,
        ),
        const SizedBox(height: 12),
        _ConnectionStatusRow(
          connected: showRemote,
          label: currentProfile ? connectionLabel : 'idle',
          error: lastError,
        ),
        if (showRemote) ...[
          const SizedBox(height: 24),
          _PairingCard(
            icon: RecodexIcons.terminal,
            title: '远程 Codex',
            children: [
              _ServiceInfoList(
                items: [
                  _ServiceInfoItem(
                    label: '网关版本',
                    value: serviceContext.bridgeVersion.isEmpty
                        ? '未知'
                        : serviceContext.bridgeVersion,
                  ),
                  _ServiceInfoItem(
                    label: 'Codex 版本',
                    value: serviceContext.codexVersion.isEmpty
                        ? '未检测到'
                        : serviceContext.codexVersion,
                  ),
                  _ServiceInfoItem(
                    label: 'API 密钥',
                    value: serviceContext.apiKeyConfigured ? '已配置' : '未配置',
                    positive: serviceContext.apiKeyConfigured,
                  ),
                  _ServiceInfoItem(
                    label: '默认模型',
                    value: serviceContext.model.isEmpty
                        ? '未提供'
                        : serviceContext.modelLabel(serviceContext.model),
                  ),
                  _ServiceInfoItem(
                    label: '今日用量',
                    value: _formatTokenCount(serviceContext.usage.todayTokens),
                  ),
                  _ServiceInfoItem(
                    label: '本月用量',
                    value: _formatTokenCount(serviceContext.usage.monthTokens),
                  ),
                  _ServiceInfoItem(
                    label: '估算费用',
                    value: serviceContext.usage.rateConfigured
                        ? _formatCost(serviceContext.usage.monthCost)
                        : '未配置费率',
                  ),
                  _ServiceInfoItem(
                    label: '最近更新',
                    value: _formatUsageTime(serviceContext.usage.lastUpdated),
                  ),
                  _ServiceInfoItem(
                    label: '用量读取',
                    value: serviceContext.usage.canReadUsage ? '可读取' : '不可读取',
                    positive: serviceContext.usage.canReadUsage,
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
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
    RecodexNotice.show(
      context,
      'Ed25519 公钥已复制',
      tone: RecodexNoticeTone.success,
      duration: const Duration(seconds: 2),
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
    final grant = _grantController.text.trim();
    if (token.isEmpty && grant.isEmpty) {
      controller.lastError.value = '请填写连接令牌或接入端授权凭证。';
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
        inputEndpointGrant: grant,
        inputTokenExpiresAt:
            _editingProfile != null &&
                token == _editingProfile!.pairingToken.trim()
            ? _editingProfile!.tokenExpiresAt
            : 0,
        inputGrantExpiresAt:
            _editingProfile != null &&
                grant == _editingProfile!.endpointGrant.trim()
            ? _editingProfile!.grantExpiresAt
            : 0,
      );
      if (!mounted) return;
      if (error == null) {
        RecodexNotice.show(
          context,
          '连接测试成功，Relay 连接正常。',
          tone: RecodexNoticeTone.success,
          duration: const Duration(seconds: 2),
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
    // The public key is editable for importing/correcting a value, but it
    // must still correspond to the private seed held by this pairing. Relay
    // verifies that relationship during the signed handshake.
    try {
      final keyPair = await RelayProtocol.keyPairFromSeed(
        RelayProtocol.decodeBase64Url(_draftDeviceKey),
      );
      final derivedPublicKey = await RelayProtocol.publicKey(keyPair);
      if (_publicKeyController.text.trim() != derivedPublicKey) {
        controller.lastError.value = '公钥与本机私钥不匹配，请填写对应的公钥。';
        return;
      }
    } catch (_) {
      controller.lastError.value = '公钥格式无效，请检查后重试。';
      return;
    }
    final name = _nameController.text.trim();
    final target = _targetDeviceController.text.trim();
    if (name.isEmpty && target.isEmpty) {
      controller.lastError.value = '请填写配对名称或目标主机接入端 ID。';
      return;
    }
    final editing = _editingProfile;
    final latest = editing == null ? null : controller.pairingById(editing.id);
    // A background renewal updates the saved profile while this editor can
    // remain open for minutes. Use that newest profile as the base and only
    // keep a credential value from the form when the user actually changed
    // that field; otherwise saving an unrelated label would restore the
    // already-rotated token (and its old expiry).
    final base = latest ?? editing ?? controller.createDraftPairing();
    var nextToken = _tokenController.text.trim();
    var nextGrant = _grantController.text.trim();
    if (editing != null && latest != null) {
      if (nextToken == editing.pairingToken.trim() &&
          latest.pairingToken != editing.pairingToken) {
        nextToken = latest.pairingToken;
      }
      if (nextGrant == editing.endpointGrant.trim() &&
          latest.endpointGrant != editing.endpointGrant) {
        nextGrant = latest.endpointGrant;
      }
    }
    final profile = base.copyWith(
      name: name.isEmpty ? target : name,
      baseUrl: _baseUrlController.text,
      spaceId: _spaceIdController.text,
      targetDeviceId: target,
      deviceId: _endpointIdController.text,
      deviceKey: _draftDeviceKey,
      endpointPublicKey: _publicKeyController.text.trim(),
      pairingToken: nextToken,
      endpointGrant: nextGrant,
      tokenExpiresAt: nextToken == base.pairingToken.trim()
          ? base.tokenExpiresAt
          : 0,
      grantExpiresAt: nextGrant == base.endpointGrant.trim()
          ? base.grantExpiresAt
          : 0,
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

class _PairingPageContent extends StatelessWidget {
  const _PairingPageContent({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final horizontal = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 24.0;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        horizontal,
        16,
        horizontal,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

class _PairingIntro extends StatelessWidget {
  const _PairingIntro({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colors.text,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 14,
              height: 1.45,
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
    final colors = context.recodexColors;
    return SettingsCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(RecodexIcons.devices, size: 28, color: colors.textMuted),
          const SizedBox(height: 16),
          Text(
            '还没有配对',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '添加主机的 Relay 连接信息，即可发送任务、查看回答与文件修改。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          _PairingActionButton(
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
    final statusColor = connected
        ? colors.success
        : busy
        ? colors.warning
        : colors.textMuted;
    return SettingsCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
      // Opening details never switches the active connection. That action
      // stays explicit in the menu alongside edit and delete.
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(RecodexIcons.devices, color: colors.icon, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _PairingStatus(text: status, color: statusColor),
                        if (active)
                          Text(
                            '默认配对',
                            style: TextStyle(
                              color: colors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox.square(
                dimension: 44,
                child: RecodexPopupMenuButton<String>(
                  tooltip: '更多操作',
                  icon: Icon(
                    RecodexIcons.more,
                    color: colors.textMuted,
                    size: 20,
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        onEdit();
                      case 'select':
                        onSelect();
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Text('编辑配对')),
                    PopupMenuItem(
                      value: 'select',
                      enabled: !active,
                      child: Text(active ? '当前默认配对' : '设为默认配对'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        '删除配对',
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PairingDetail(label: '空间', value: profile.spaceId),
          const SizedBox(height: 4),
          _PairingDetail(label: '主机', value: profile.targetDeviceId),
        ],
      ),
    );
  }
}

class _PairingDetail extends StatelessWidget {
  const _PairingDetail({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: colors.textMuted, fontSize: 13, height: 1.4),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value.isEmpty ? '未填写' : value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _PairingStatus extends StatelessWidget {
  const _PairingStatus({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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
    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.textMuted, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}

class _PairingActionButton extends StatelessWidget {
  const _PairingActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.secondary = false,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool secondary;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      textStyle: WidgetStatePropertyAll(
        Theme.of(context).textTheme.labelLarge?.copyWith(
          fontSize: 14,
          height: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final leading = loading
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.textMuted,
            ),
          )
        : Icon(icon, size: 18);
    if (secondary) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        style: style.merge(
          OutlinedButton.styleFrom(
            foregroundColor: colors.text,
            side: BorderSide(color: colors.glassBorder),
          ),
        ),
        icon: leading,
        label: Text(label),
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      style: style,
      icon: leading,
      label: Text(label),
    );
  }
}

class _PairingActions extends StatelessWidget {
  const _PairingActions({
    required this.testing,
    required this.saving,
    required this.busy,
    required this.preparingKey,
    required this.onTest,
    required this.onSave,
  });
  final bool testing;
  final bool saving;
  final bool busy;
  final bool preparingKey;
  final VoidCallback? onTest;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final test = _PairingActionButton(
      label: testing ? '测试中' : '测试连接',
      icon: RecodexIcons.network,
      secondary: true,
      loading: testing,
      onPressed: onTest,
    );
    final save = _PairingActionButton(
      label: saving
          ? '保存中'
          : busy
          ? '连接中'
          : preparingKey
          ? '生成密钥中'
          : '保存并连接',
      icon: RecodexIcons.link,
      loading: saving || busy || preparingKey,
      onPressed: onSave,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth / textScale < 300) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [test, const SizedBox(height: 10), save],
          );
        }
        return Row(
          children: [
            Expanded(child: test),
            const SizedBox(width: 12),
            Expanded(child: save),
          ],
        );
      },
    );
  }
}

Color _pairingInputFillColor(BuildContext context) =>
    context.recodexColors.surfaceOverlay.withValues(alpha: 0.5);

OutlineInputBorder _pairingInputBorder(
  BuildContext context, {
  bool focused = false,
}) {
  final colors = context.recodexColors;
  final theme = Theme.of(context);
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(
      color: focused ? theme.colorScheme.primary : colors.glassBorder,
      width: focused ? 1.2 : 1,
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
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: _pairingInputBorder(context),
    enabledBorder: _pairingInputBorder(context),
    focusedBorder: _pairingInputBorder(context, focused: true),
    hintStyle: TextStyle(
      color: context.recodexColors.textMuted,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
    isDense: true,
    suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
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
          fontWeight: FontWeight.w400,
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
          fontWeight: FontWeight.w400,
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
        subtitle: '可手动修改；必须与本机私钥匹配，用于在 relay-web 签发连接令牌',
      ),
      field: TextField(
        controller: controller,
        textAlign: TextAlign.left,
        maxLines: 2,
        minLines: 1,
        style: TextStyle(
          color: context.recodexColors.icon,
          fontSize: 13,
          fontWeight: FontWeight.w400,
          height: 1.4,
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
        if (constraints.maxWidth /
                (MediaQuery.textScalerOf(context).scale(14) / 14) <
            520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [label, const SizedBox(height: 8), field],
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
  const _PairingHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: context.recodexColors.textMuted,
      fontSize: 13,
      height: 1.5,
    ),
  );
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
    final pending =
        label == 'connecting' || label == 'auth' || label == 'reconnecting';
    final color = connected
        ? colors.success
        : pending
        ? colors.warning
        : label == 'failed'
        ? colors.error
        : colors.textMuted;
    final text = connected
        ? '已连接'
        : switch (label) {
            'connecting' => '正在连接',
            'auth' => '正在认证',
            'reconnecting' => '正在重连',
            'failed' => '连接失败',
            _ => '未连接',
          };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '连接状态',
                  style: TextStyle(color: colors.textMuted, fontSize: 13),
                ),
              ),
              _PairingStatus(text: text, color: color),
            ],
          ),
          if (error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(color: colors.error, fontSize: 13, height: 1.45),
            ),
          ],
        ],
      ),
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
          style: TextStyle(
            color: colors.text,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(color: colors.textMuted, fontSize: 13, height: 1.4),
        ),
      ],
    );
  }
}

class _ServiceInfoItem {
  const _ServiceInfoItem({
    required this.label,
    required this.value,
    this.positive = false,
  });
  final String label;
  final String value;
  final bool positive;
}

class _ServiceInfoList extends StatelessWidget {
  const _ServiceInfoList({required this.items});
  final List<_ServiceInfoItem> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              color: colors.glassBorder.withValues(alpha: 0.6),
            ),
          _ServiceInfoRow(item: items[i]),
        ],
      ],
    );
  }
}

class _ServiceInfoRow extends StatelessWidget {
  const _ServiceInfoRow({required this.item});
  final _ServiceInfoItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final label = Text(
            item.label,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 13,
              height: 1.5,
            ),
          );
          final compact =
              constraints.maxWidth /
                  (MediaQuery.textScalerOf(context).scale(14) / 14) <
              240;
          final value = SelectableText(
            item.value,
            textAlign: compact ? TextAlign.left : TextAlign.right,
            style: TextStyle(
              color: item.positive ? colors.success : colors.text,
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [label, const SizedBox(height: 4), value],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 86, child: label),
              const SizedBox(width: 16),
              Expanded(child: value),
            ],
          );
        },
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
