import 'package:flutter/material.dart';

import '../components/liquid_background.dart';
import '../components/liquid_glass.dart';
import '../components/liquid_page_app_bar.dart';

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
          children: const [
            _HeroBrand(),
            SizedBox(height: 70),
            LiquidGlass(
              radius: 30,
              opacity: 0.7,
              padding: EdgeInsets.symmetric(horizontal: 38, vertical: 34),
              child: Text(
                '一个自用的 Remodex 类工具，旨在通过手机安全地远程操作电脑上的 Codex 工作流。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  height: 1.55,
                  color: Color(0xff303132),
                ),
              ),
            ),
            SizedBox(height: 74),
            _AboutRow(icon: Icons.public, title: '官方网站', value: 'remodex.io'),
            SizedBox(height: 28),
            _AboutRow(
              icon: Icons.group_outlined,
              title: '开发者',
              value: 'Remodex Team',
            ),
            SizedBox(height: 28),
            _AboutRow(
              icon: Icons.description_outlined,
              title: '开源协议',
              value: 'MIT License',
            ),
            SizedBox(height: 112),
            Text(
              '© 2024 Remodex. All rights reserved.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xff747878), fontSize: 15),
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
    return Column(
      children: [
        Container(
          width: 190,
          height: 190,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.84),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.9),
                blurRadius: 42,
                spreadRadius: 18,
              ),
            ],
          ),
          child: const Icon(Icons.terminal, color: Color(0xff005fc7), size: 78),
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
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            '版本 v1.0.4',
            style: TextStyle(
              color: Color(0xff005fc7),
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
    return LiquidGlass(
      radius: 28,
      opacity: 0.7,
      padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 22),
      child: Row(
        children: [
          Icon(icon, size: 30, color: const Color(0xff4f5356)),
          const SizedBox(width: 22),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
