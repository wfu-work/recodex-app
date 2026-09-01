import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_glass.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../routes/app_pages.dart';
import '../../theme/recodex_theme.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const LiquidPageAppBar(title: '关于'),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
              children: [
                const _AboutBrandHeader(),
                const SizedBox(height: 26),
                const _AboutSectionLabel(label: '产品定位'),
                const SizedBox(height: 10),
                const _AboutPurposeCard(),
                const SizedBox(height: 22),
                const _AboutSectionLabel(label: '应用信息'),
                const SizedBox(height: 10),
                _AboutInfoGroup(
                  children: [
                    _AboutInfoRow(
                      icon: RecodexIcons.globe,
                      title: '官方网站',
                      value: 'remodex.io',
                    ),
                    _AboutInfoDivider(),
                    _AboutInfoRow(
                      icon: RecodexIcons.groups,
                      title: '开发者',
                      value: 'Remodex Team',
                    ),
                    _AboutInfoDivider(),
                    _AboutInfoRow(
                      icon: RecodexIcons.fileText,
                      title: '开源协议',
                      value: 'MIT License',
                    ),
                    _AboutInfoDivider(),
                    _AboutInfoRow(
                      icon: RecodexIcons.scale,
                      title: '开源许可',
                      value: '应用与第三方组件',
                      trailingIcon: RecodexIcons.chevronRight,
                      onTap: () => Get.toNamed(Routes.licenses),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const _AboutSectionLabel(label: '连接与安全'),
                const SizedBox(height: 10),
                const _AboutInfoGroup(
                  children: [
                    _AboutInfoRow(
                      icon: RecodexIcons.network,
                      title: '连接方式',
                      value: 'Relay Protocol v1',
                    ),
                    _AboutInfoDivider(),
                    _AboutInfoRow(
                      icon: RecodexIcons.verified,
                      title: '安全模型',
                      value: 'Ed25519 Endpoint proof',
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                const _AboutFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AboutBrandHeader extends StatelessWidget {
  const _AboutBrandHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return LiquidGlass(
      radius: 28,
      opacity: 0.72,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 104,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Image.asset(
                'assets/images/recodex_icon_1024.png',
                fit: BoxFit.cover,
                semanticLabel: 'Recodex Companion 图标',
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recodex',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 28,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Companion',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 17,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                const Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _AboutTag(label: 'v1.0.4', accent: true),
                    _AboutTag(label: '移动端控制台'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutTag extends StatelessWidget {
  const _AboutTag({required this.label, this.accent = false});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: (accent ? colors.icon : colors.surfaceOverlay).withValues(
          alpha: accent ? 0.12 : 0.74,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: (accent ? colors.icon : colors.glassBorder).withValues(
            alpha: accent ? 0.28 : 0.86,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            color: accent ? colors.icon : colors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _AboutSectionLabel extends StatelessWidget {
  const _AboutSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        label,
        style: TextStyle(
          color: context.recodexColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _AboutPurposeCard extends StatelessWidget {
  const _AboutPurposeCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return LiquidGlass(
      radius: 24,
      opacity: 0.66,
      padding: const EdgeInsets.fromLTRB(18, 16, 20, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(RecodexIcons.terminal, color: colors.icon, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              '通过 Relay 安全连接手机与 Codex 主机，快速选择工作区、发送任务并查看执行状态。',
              style: TextStyle(
                color: colors.text,
                fontSize: 14,
                height: 1.55,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutInfoGroup extends StatelessWidget {
  const _AboutInfoGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      radius: 24,
      opacity: 0.66,
      padding: EdgeInsets.zero,
      child: Column(children: children),
    );
  }
}

class _AboutInfoRow extends StatelessWidget {
  const _AboutInfoRow({
    required this.icon,
    required this.title,
    required this.value,
    this.trailingIcon,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final IconData? trailingIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 22, color: colors.icon),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: colors.text,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 10),
            Icon(trailingIcon, color: colors.textMuted, size: 19),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

class _AboutInfoDivider extends StatelessWidget {
  const _AboutInfoDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 70,
      color: context.recodexColors.textMuted.withValues(alpha: 0.14),
    );
  }
}

class _AboutFooter extends StatelessWidget {
  const _AboutFooter();

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Column(
      children: [
        Text(
          '© 2024 Remodex. All rights reserved.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Built for focused remote work.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textMuted.withValues(alpha: 0.72),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
