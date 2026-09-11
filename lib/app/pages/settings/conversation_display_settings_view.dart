import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../components/recodex_dropdown.dart';
import '../../theme/recodex_theme.dart';
import 'settings_preferences_controller.dart';
import 'settings_widgets.dart';

/// Display-only preferences for the transcript and answer column.
class ConversationDisplaySettingsPage extends StatelessWidget {
  const ConversationDisplaySettingsPage({super.key});

  static const _widthOptions = <RecodexDropdownOption<double>>[
    RecodexDropdownOption(value: 560, label: '窄 · 560 px'),
    RecodexDropdownOption(value: 720, label: '标准 · 720 px'),
    RecodexDropdownOption(value: 840, label: '宽 · 840 px'),
    RecodexDropdownOption(value: 960, label: '桌面 · 960 px'),
    RecodexDropdownOption(value: 1200, label: '超宽 · 1200 px'),
  ];

  static const _paddingOptions = <RecodexDropdownOption<double>>[
    RecodexDropdownOption(value: 8, label: '紧凑 · 8 px'),
    RecodexDropdownOption(value: 16, label: '标准 · 16 px'),
    RecodexDropdownOption(value: 24, label: '宽松 · 24 px'),
    RecodexDropdownOption(value: 32, label: '更宽 · 32 px'),
    RecodexDropdownOption(value: 40, label: '最大 · 40 px'),
  ];

  @override
  Widget build(BuildContext context) {
    final preferences = Get.isRegistered<SettingsPreferencesController>()
        ? Get.find<SettingsPreferencesController>()
        : Get.put(SettingsPreferencesController(), permanent: true);
    return Obx(
      () => LiquidBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: const LiquidPageAppBar(title: '对话显示'),
          body: SettingsPageContent(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 34),
              children: [
                const SettingsSectionTitle(
                  title: '思考与时间线',
                  subtitle: '控制回答区域中思考过程、时间线密度和导航辅助的显示方式。',
                ),
                const SizedBox(height: 10),
                SettingsGroup(
                  children: [
                    SettingsToggleRow(
                      icon: RecodexIcons.reasoning,
                      title: '显示/隐藏思考过程',
                      subtitle: '隐藏后仍会保留任务状态，只是不显示思考摘要',
                      value: preferences.showReasoning.value,
                      onChanged: preferences.setShowReasoning,
                    ),
                    const SettingsDivider(),
                    SettingsToggleRow(
                      icon: RecodexIcons.chevronDown,
                      title: '思考内容默认折叠',
                      subtitle: '回答完成后自动收起思考内容，可点击耗时栏重新展开',
                      value: preferences.collapseReasoningByDefault.value,
                      onChanged: preferences.setCollapseReasoningByDefault,
                    ),
                    const SettingsDivider(),
                    SettingsToggleRow(
                      icon: RecodexIcons.tune,
                      title: '紧凑时间线',
                      subtitle: '减少任务卡片之间的间距，适合较长的对话',
                      value: preferences.compactTimeline.value,
                      onChanged: preferences.setCompactTimeline,
                    ),
                    const SettingsDivider(),
                    SettingsToggleRow(
                      icon: RecodexIcons.accountTree,
                      title: '显示对话索引',
                      subtitle: '在回答区域侧边显示可点击的对话定位短线',
                      value: preferences.showConversationIndex.value,
                      onChanged: preferences.setShowConversationIndex,
                    ),
                    const SettingsDivider(),
                    SettingsToggleRow(
                      icon: RecodexIcons.arrowUp,
                      title: '自动滚动到最新回答',
                      subtitle: '任务产生新内容时保持视图跟随最新回答',
                      value: preferences.autoScrollToLatest.value,
                      onChanged: preferences.setAutoScrollToLatest,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const SettingsSectionTitle(
                  title: '回答详情',
                  subtitle: '选择是否显示工具调用详情和回答的统计信息。',
                ),
                const SizedBox(height: 10),
                SettingsGroup(
                  children: [
                    SettingsToggleRow(
                      icon: RecodexIcons.terminal,
                      title: '显示工具调用详情',
                      subtitle: '显示工具类型、命令摘要和文件处理状态',
                      value: preferences.showToolCallDetails.value,
                      onChanged: preferences.setShowToolCallDetails,
                    ),
                    const SettingsDivider(),
                    SettingsToggleRow(
                      icon: RecodexIcons.calendar,
                      title: '显示回答统计信息',
                      subtitle: '显示消耗总量、输入、输出、缓存、耗时和完成时间',
                      value: preferences.showUsageMetrics.value,
                      onChanged: preferences.setShowUsageMetrics,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const SettingsSectionTitle(
                  title: '回答区域布局',
                  subtitle: '调整正文最大宽度以及回答区域两侧的留白。',
                ),
                const SizedBox(height: 10),
                SettingsGroup(
                  children: [
                    SettingsDropdownRow<double>(
                      icon: RecodexIcons.scale,
                      title: '正文最大宽度',
                      subtitle: '限制回答正文在桌面窗口中的最大显示宽度',
                      value: preferences.answerMaxWidth.value,
                      options: _widthOptions,
                      onChanged: preferences.setAnswerMaxWidth,
                    ),
                    const SettingsDivider(),
                    SettingsDropdownRow<double>(
                      icon: RecodexIcons.menu,
                      title: '回答区域左右边距',
                      subtitle: '设置回答正文与窗口边缘之间的水平留白',
                      value: preferences.answerHorizontalPadding.value,
                      options: _paddingOptions,
                      onChanged: preferences.setAnswerHorizontalPadding,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
