import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_glass.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../components/recodex_dropdown.dart';
import '../../theme/recodex_theme.dart';
import '../main/bridge_controller.dart';
import 'settings_preferences_controller.dart';
import 'settings_widgets.dart';

class TaskSettingsPage extends StatelessWidget {
  const TaskSettingsPage({super.key});

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
          appBar: const LiquidPageAppBar(title: '任务与工作区'),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 34),
                children: [
                  _TaskHero(bridge: bridge),
                  const SizedBox(height: 24),
                  const SettingsSectionTitle(
                    title: '默认任务参数',
                    subtitle: '新建任务时自动使用这些选项，仍可在输入框中临时调整',
                  ),
                  const SizedBox(height: 10),
                  SettingsGroup(
                    children: [
                      _SelectorRow(
                        icon: RecodexIcons.folderOpen,
                        title: '默认工作区',
                        subtitle: '新建任务时优先使用的项目目录',
                        value: preferences.defaultWorkspacePath.value,
                        options: _workspaceOptions(bridge, preferences),
                        onChanged: (value) {
                          preferences.setDefaultWorkspacePath(value);
                          if (value.isEmpty) return;
                          for (final workspace in bridge.workspaces) {
                            if (workspace.path == value) {
                              bridge.selectWorkspace(workspace);
                              break;
                            }
                          }
                        },
                      ),
                      const SettingsDivider(),
                      _SelectorRow(
                        icon: RecodexIcons.fast,
                        title: '默认模型',
                        subtitle: '选择新会话优先使用的模型',
                        value: preferences.defaultModel.value,
                        options: _modelOptions(bridge, preferences),
                        onChanged: (value) {
                          preferences.setDefaultModel(value);
                          bridge.applyTaskPreferences(preferences);
                        },
                      ),
                      const SettingsDivider(),
                      _SelectorRow(
                        icon: RecodexIcons.reasoning,
                        title: '默认推理强度',
                        subtitle: '控制 Codex 思考深度和响应速度的平衡',
                        value: preferences.defaultReasoningEffort.value,
                        options: const [
                          RecodexDropdownOption(
                            value: 'low',
                            label: '低 · 更快响应',
                          ),
                          RecodexDropdownOption(
                            value: 'medium',
                            label: '中 · 推荐',
                          ),
                          RecodexDropdownOption(
                            value: 'high',
                            label: '高 · 更深入分析',
                          ),
                          RecodexDropdownOption(
                            value: 'xhigh',
                            label: '极高 · 复杂任务',
                          ),
                        ],
                        onChanged: (value) {
                          preferences.setDefaultReasoningEffort(value);
                          bridge.setReasoningEffort(value);
                        },
                      ),
                      const SettingsDivider(),
                      _SelectorRow(
                        icon: RecodexIcons.shield,
                        title: '默认权限模式',
                        subtitle: '控制任务执行时的确认策略',
                        value: preferences.defaultPermissionMode.value,
                        options: const [
                          RecodexDropdownOption(value: '默认权限', label: '默认权限'),
                          RecodexDropdownOption(value: '自动审查', label: '自动审查'),
                          RecodexDropdownOption(
                            value: '完全访问权限',
                            label: '完全访问权限',
                          ),
                        ],
                        onChanged: (value) {
                          preferences.setDefaultPermissionMode(value);
                          bridge.setPermissionMode(value);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const SettingsSectionTitle(
                    title: '任务显示与安全',
                    subtitle: '调整时间线展示和高风险操作的确认行为',
                  ),
                  const SizedBox(height: 10),
                  SettingsGroup(
                    children: [
                      SettingsToggleRow(
                        icon: RecodexIcons.reasoning,
                        title: '显示推理过程',
                        subtitle: '在任务时间线中显示可用的推理摘要',
                        value: preferences.showReasoning.value,
                        onChanged: preferences.setShowReasoning,
                      ),
                      const SettingsDivider(),
                      SettingsToggleRow(
                        icon: RecodexIcons.security,
                        title: '高风险操作前确认',
                        subtitle: '执行敏感操作前始终要求再次确认',
                        value: preferences.confirmSensitiveActions.value,
                        onChanged: preferences.setConfirmSensitiveActions,
                      ),
                      const SettingsDivider(),
                      SettingsToggleRow(
                        icon: RecodexIcons.tune,
                        title: '紧凑时间线',
                        subtitle: '减少任务卡片间距，显示更多内容',
                        value: preferences.compactTimeline.value,
                        onChanged: preferences.setCompactTimeline,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _reset(context, preferences, bridge),
                      icon: const Icon(RecodexIcons.undo, size: 18),
                      label: const Text('恢复任务默认设置'),
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

  List<RecodexDropdownOption<String>> _modelOptions(
    BridgeController bridge,
    SettingsPreferencesController preferences,
  ) {
    final values = <String>{'自动选择', ...bridge.composerContext.value.models};
    return [
      for (final value in values)
        RecodexDropdownOption<String>(
          value: value,
          label: value == '自动选择'
              ? value
              : bridge.composerContext.value.modelLabel(value),
        ),
    ];
  }

  List<RecodexDropdownOption<String>> _workspaceOptions(
    BridgeController bridge,
    SettingsPreferencesController preferences,
  ) {
    final options = <RecodexDropdownOption<String>>[
      const RecodexDropdownOption(value: '', label: '跟随当前配对'),
    ];
    for (final workspace in bridge.workspaces) {
      if (workspace.path.trim().isEmpty) continue;
      options.add(
        RecodexDropdownOption(
          value: workspace.path,
          label: workspace.name.trim().isEmpty
              ? workspace.path
              : workspace.name,
        ),
      );
    }
    final selected = preferences.defaultWorkspacePath.value;
    if (selected.isNotEmpty &&
        !options.any((option) => option.value == selected)) {
      options.add(RecodexDropdownOption(value: selected, label: selected));
    }
    return options;
  }

  Future<void> _reset(
    BuildContext context,
    SettingsPreferencesController preferences,
    BridgeController bridge,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复默认设置？'),
        content: const Text('任务模型、推理强度、权限和显示选项都会恢复默认值。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await preferences.resetTaskPreferences();
    bridge.applyTaskPreferences(preferences);
  }
}

class _SelectorRow extends StatelessWidget {
  const _SelectorRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final List<RecodexDropdownOption<String>> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = options.any((option) => option.value == value)
        ? value
        : options.first.value;
    return SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: SizedBox(
        width: 158,
        child: RecodexDropdown<String>(
          value: selected,
          options: options,
          maxWidth: 158,
          compact: true,
          tooltip: '选择$title',
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _TaskHero extends StatelessWidget {
  const _TaskHero({required this.bridge});

  final BridgeController bridge;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final workspace = bridge.selectedWorkspace.value?.name;
    return LiquidGlass(
      radius: 28,
      opacity: 0.72,
      padding: const EdgeInsets.fromLTRB(20, 20, 18, 20),
      child: Row(
        children: [
          Icon(RecodexIcons.terminal, color: colors.icon, size: 30),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '任务与工作区',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  workspace == null ? '当前尚未选择工作区' : '当前工作区：$workspace',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
