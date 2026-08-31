import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../components/liquid_background.dart';
import '../../components/liquid_glass.dart';
import '../../components/liquid_page_app_bar.dart';
import '../../theme/recodex_theme.dart';

class OpenSourceLicensesPage extends StatefulWidget {
  const OpenSourceLicensesPage({super.key});

  @override
  State<OpenSourceLicensesPage> createState() => _OpenSourceLicensesPageState();
}

class _OpenSourceLicensesPageState extends State<OpenSourceLicensesPage> {
  late final Future<List<_LicenseData>> _licenses = _loadLicenses();

  Future<List<_LicenseData>> _loadLicenses() async {
    final entries = await LicenseRegistry.licenses.toList();
    final licensesByPackage = <String, List<_LicenseData>>{};
    for (final entry in entries) {
      final packages = entry.packages.toSet().toList()..sort();
      if (packages.isEmpty) continue;

      final paragraphs = entry.paragraphs
          .map((paragraph) => paragraph.text.trimRight())
          .where((paragraph) => paragraph.isNotEmpty)
          .toList();
      final text = paragraphs.join('\n\n');
      if (text.isEmpty) continue;

      for (final package in packages) {
        licensesByPackage
            .putIfAbsent(package, () => [])
            .add(
              _LicenseData(
                packages: [package],
                license: _licenseLabel(text),
                text: text,
              ),
            );
      }
    }
    final licenses = licensesByPackage.entries.map((entry) {
      final labels = entry.value.map((license) => license.license).toSet();
      return _LicenseData(
        packages: [entry.key],
        license: labels.length == 1 ? labels.first : '${labels.length} 项许可',
        text: entry.value.map((license) => license.text).join('\n\n---\n\n'),
      );
    }).toList();
    licenses.sort((first, second) {
      return first.displayName.compareTo(second.displayName);
    });
    return licenses;
  }

  @override
  Widget build(BuildContext context) {
    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const LiquidPageAppBar(title: '开源许可'),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 34),
              children: [
                const _LicenseHero(),
                const SizedBox(height: 24),
                const _LicenseSectionTitle(
                  title: '本应用',
                  subtitle: 'Recodex Companion 的源代码许可',
                ),
                const SizedBox(height: 10),
                LiquidGlass(
                  radius: 24,
                  opacity: 0.66,
                  padding: EdgeInsets.zero,
                  child: _LicenseRow(
                    icon: RecodexIcons.scale,
                    title: 'Recodex Companion',
                    subtitle: '© 2024 Remodex',
                    license: 'MIT License',
                    onTap: () => _openLicense(
                      const _LicenseData(
                        packages: ['Recodex Companion'],
                        license: 'MIT License',
                        text: _recodexLicenseText,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const _LicenseSectionTitle(
                  title: '第三方组件',
                  subtitle: '许可内容由 Flutter LicenseRegistry 自动收集',
                ),
                const SizedBox(height: 10),
                FutureBuilder<List<_LicenseData>>(
                  future: _licenses,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const _LicenseStatusCard(
                        icon: RecodexIcons.sync,
                        title: '正在读取许可',
                        subtitle: '正在整理应用依赖的开源许可信息',
                      );
                    }
                    if (snapshot.hasError) {
                      return const _LicenseStatusCard(
                        icon: RecodexIcons.warning,
                        title: '许可信息暂不可用',
                        subtitle: '稍后重新进入此页面即可再次尝试',
                      );
                    }
                    final licenses = snapshot.data ?? const <_LicenseData>[];
                    if (licenses.isEmpty) {
                      return const _LicenseStatusCard(
                        icon: RecodexIcons.fileText,
                        title: '暂无第三方许可',
                        subtitle: '当前构建未报告可展示的依赖许可',
                      );
                    }
                    return LiquidGlass(
                      radius: 24,
                      opacity: 0.66,
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < licenses.length;
                            index++
                          ) ...[
                            _LicenseRow(
                              icon: RecodexIcons.fileText,
                              title: licenses[index].displayName,
                              subtitle: licenses[index].packageSummary,
                              license: licenses[index].license,
                              onTap: () => _openLicense(licenses[index]),
                            ),
                            if (index != licenses.length - 1)
                              const _LicenseDivider(),
                          ],
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  '许可文本仅用于展示，具体使用和分发请以各开源项目随附的许可文件为准。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.recodexColors.textMuted,
                    fontSize: 11,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openLicense(_LicenseData license) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _LicenseDetailPage(license: license),
      ),
    );
  }
}

class _LicenseHero extends StatelessWidget {
  const _LicenseHero();

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return LiquidGlass(
      radius: 28,
      opacity: 0.72,
      padding: const EdgeInsets.fromLTRB(20, 20, 22, 20),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 58,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.icon.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: colors.icon.withValues(alpha: 0.20)),
              ),
              child: Icon(RecodexIcons.scale, color: colors.icon, size: 26),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '开源许可',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '感谢每一个让 Recodex 更可靠的开源项目。',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 13,
                    height: 1.4,
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

class _LicenseSectionTitle extends StatelessWidget {
  const _LicenseSectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: colors.textMuted.withValues(alpha: 0.72),
              fontSize: 11,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LicenseStatusCard extends StatelessWidget {
  const _LicenseStatusCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return LiquidGlass(
      radius: 24,
      opacity: 0.66,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      child: Row(
        children: [
          Icon(icon, color: colors.icon, size: 22),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 12,
                    height: 1.35,
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

class _LicenseRow extends StatelessWidget {
  const _LicenseRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.license,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String license;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 420;
            return Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.icon.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(icon, color: colors.icon, size: 19),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          compact ? '$license · $subtitle' : subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 10),
                    _LicenseTag(label: license),
                    const SizedBox(width: 8),
                  ],
                  Icon(
                    RecodexIcons.chevronRight,
                    color: colors.textMuted,
                    size: 19,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LicenseTag extends StatelessWidget {
  const _LicenseTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceOverlay.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.glassBorder.withValues(alpha: 0.72)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          label,
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _LicenseDivider extends StatelessWidget {
  const _LicenseDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 70,
      color: context.recodexColors.textMuted.withValues(alpha: 0.14),
    );
  }
}

class _LicenseDetailPage extends StatelessWidget {
  const _LicenseDetailPage({required this.license});

  final _LicenseData license;

  @override
  Widget build(BuildContext context) {
    final colors = context.recodexColors;
    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const LiquidPageAppBar(title: '许可详情'),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 34),
              children: [
                LiquidGlass(
                  radius: 26,
                  opacity: 0.72,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 17),
                  child: Row(
                    children: [
                      Icon(RecodexIcons.scale, color: colors.icon, size: 25),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              license.displayName,
                              style: TextStyle(
                                color: colors.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              license.license,
                              style: TextStyle(
                                color: colors.icon,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                LiquidGlass(
                  radius: 24,
                  opacity: 0.66,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                  child: SelectableText(
                    license.text,
                    style: TextStyle(
                      color: colors.text,
                      fontFamily: 'Menlo',
                      fontFamilyFallback: const ['SF Mono', 'monospace'],
                      fontSize: 12,
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LicenseData {
  const _LicenseData({
    required this.packages,
    required this.license,
    required this.text,
  });

  final List<String> packages;
  final String license;
  final String text;

  String get displayName {
    if (packages.length == 1) return packages.first;
    return '${packages.first} 等 ${packages.length} 个组件';
  }

  String get packageSummary {
    if (packages.length <= 1) return '查看完整许可文本';
    return packages.join('、');
  }
}

String _licenseLabel(String text) {
  final normalized = text.toLowerCase();
  if (normalized.contains('apache license')) return 'Apache License 2.0';
  if (normalized.contains('bsd 3-clause') ||
      normalized.contains('neither the name')) {
    return 'BSD 3-Clause';
  }
  if (normalized.contains('mit license') ||
      normalized.contains('permission is hereby granted')) {
    return 'MIT License';
  }
  if (normalized.contains('isc license')) return 'ISC License';
  return 'Open Source License';
}

const _recodexLicenseText = '''MIT License

Copyright (c) 2024 Remodex

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.''';
