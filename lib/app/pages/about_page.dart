import 'package:flutter/material.dart';

import '../components/liquid_background.dart';
import '../components/liquid_glass.dart';
import '../components/liquid_page_app_bar.dart';
import '../theme/recodex_theme.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const LiquidPageAppBar(title: '关于'),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(30, 90, 30, 34),
          children: [
            const _HeroBrand(),
            const SizedBox(height: 70),
            LiquidGlass(
              radius: 30,
              opacity: 0.7,
              padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 34),
              child: Text(
                '一个自用的 Remodex 类工具，旨在通过手机安全地远程操作电脑上的 Codex 工作流。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  height: 1.55,
                  color: context.recodexColors.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 74),
            const _AboutRow(
              icon: Icons.public,
              title: '官方网站',
              value: 'remodex.io',
            ),
            const SizedBox(height: 28),
            const _AboutRow(
              icon: Icons.group_outlined,
              title: '开发者',
              value: 'Remodex Team',
            ),
            const SizedBox(height: 28),
            const _AboutRow(
              icon: Icons.description_outlined,
              title: '开源协议',
              value: 'MIT License',
            ),
            const SizedBox(height: 112),
            Text(
              '© 2024 Remodex. All rights reserved.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.recodexColors.textMuted,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroBrand extends StatelessWidget {
  const _HeroBrand();

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Column(
      children: [
        Container(
          width: 190,
          height: 190,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(44),
            color: colors.surfaceOverlay,
            border: Border.all(color: colors.glassBorder),
            boxShadow: [
              BoxShadow(
                color: colors.glassShadow.withValues(alpha: 0.18),
                offset: const Offset(0, 20),
                blurRadius: 42,
              ),
            ],
          ),
          padding: const EdgeInsets.all(18),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(34),
            child: Image.asset(
              'assets/brand/recodex_icon_1024.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 54),
        Text(
          'Remodex\nCompanion',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 26),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          decoration: BoxDecoration(
            color: colors.surfaceOverlay,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colors.glassBorder),
          ),
          child: Text(
            '版本 v1.0.4',
            style: TextStyle(
              color: colors.icon,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return LiquidGlass(
      radius: 28,
      opacity: 0.7,
      padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 22),
      child: Row(
        children: [
          Icon(icon, size: 30, color: colors.icon),
          const SizedBox(width: 22),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: colors.text,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
