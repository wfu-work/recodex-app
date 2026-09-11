import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../components/recodex_dropdown.dart';
import '../../routes/app_pages.dart';
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
          body: SettingsPageContent(
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
                    SettingsDropdownRow<String>(
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
                    SettingsDropdownRow<String>(
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
                    SettingsDropdownRow<String>(
                      icon: RecodexIcons.reasoning,
                      title: '默认推理强度',
                      emptyLabel: '连接主机后可用',
                      subtitle: '控制 Codex 思考深度和响应速度的平衡',
                      value: preferences.defaultReasoningEffort.value,
                      options: _reasoningOptions(bridge, preferences),
                      onChanged: (value) {
                        preferences.setDefaultReasoningEffort(value);
                        bridge.applyTaskPreferences(preferences);
                      },
                    ),
                    const SettingsDivider(),
                    SettingsDropdownRow<String>(
                      icon: RecodexIcons.shield,
                      title: '默认权限模式',
                      subtitle: '控制任务执行时的确认策略',
                      value: preferences.defaultPermissionMode.value,
                      options: const [
                        RecodexDropdownOption(value: '默认权限', label: '请求批准'),
                        RecodexDropdownOption(value: '自动审查', label: '帮我批准'),
                        RecodexDropdownOption(value: '完全访问权限', label: '完全访问权限'),
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
                  title: '任务安全',
                  subtitle: '控制高风险操作的确认行为',
                ),
                const SizedBox(height: 10),
                SettingsGroup(
                  children: [
                    SettingsToggleRow(
                      icon: RecodexIcons.security,
                      title: '高风险操作前确认',
                      subtitle: '执行敏感操作前始终要求再次确认',
                      value: preferences.confirmSensitiveActions.value,
                      onChanged: preferences.setConfirmSensitiveActions,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const SettingsSectionTitle(
                  title: '对话显示',
                  subtitle: '调整思考过程、时间线和回答区域布局',
                ),
                const SizedBox(height: 10),
                SettingsGroup(
                  children: [
                    SettingsRow(
                      icon: RecodexIcons.message,
                      title: '对话显示设置',
                      subtitle: '思考、索引、自动滚动、工具详情和回答宽度',
                      trailing: Icon(
                        RecodexIcons.chevronRight,
                        color: context.recodexColors.textMuted,
                      ),
                      onTap: () => Get.toNamed(Routes.conversationDisplay),
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

  List<RecodexDropdownOption<String>> _reasoningOptions(
    BridgeController bridge,
    SettingsPreferencesController preferences,
  ) {
    final context = bridge.composerContext.value;
    final configuredModel = preferences.defaultModel.value;
    final model = configuredModel == '自动选择' || configuredModel.trim().isEmpty
        ? context.model
        : configuredModel;
    final efforts =
        context.modelReasoningEfforts[model] ??
        (model == context.model ? context.reasoningEfforts : const <String>[]);
    return [
      for (final effort in efforts)
        RecodexDropdownOption<String>(
          value: effort,
          label: _reasoningLabel(effort),
        ),
    ];
  }

  String _reasoningLabel(String value) {
    return switch (value) {
      'minimal' => '最低 · 更快响应',
      'low' => '低 · 更快响应',
      'medium' => '中 · 推荐',
      'high' => '高 · 更深入分析',
      'xhigh' => '极高 · 复杂任务',
      'max' => '最高 · 最深入分析',
      'ultra' => '极致 · 自动委派',
      _ => value,
    };
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

class _TaskHero extends StatelessWidget {
  const _TaskHero({required this.bridge});

  final BridgeController bridge;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final workspace = bridge.selectedWorkspace.value?.name;
    return SettingsCard(
      radius: 20,
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
                    fontWeight: FontWeight.w600,
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
