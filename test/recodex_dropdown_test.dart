import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/components/recodex_dropdown.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

void main() {
  testWidgets('RecodexDropdown exposes and selects every option', (
    tester,
  ) async {
    var selected = 'medium';

    await tester.pumpWidget(
      MaterialApp(
        theme: RecodexTheme.light,
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Center(
              child: RecodexDropdown<String>(
                value: selected,
                leadingIcon: Icons.blur_circular,
                options: const [
                  RecodexDropdownOption(value: 'low', label: '低'),
                  RecodexDropdownOption(value: 'medium', label: '中'),
                  RecodexDropdownOption(value: 'high', label: '高'),
                ],
                onChanged: (value) => setState(() => selected = value),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('中'), findsOneWidget);
    await tester.tap(find.byType(RecodexDropdown<String>));
    await tester.pumpAndSettle();

    expect(find.text('低'), findsOneWidget);
    expect(find.text('高'), findsOneWidget);
    expect(find.byIcon(RecodexIcons.check), findsOneWidget);

    await tester.tap(find.text('高'));
    await tester.pumpAndSettle();
    expect(find.text('高'), findsOneWidget);
  });

  testWidgets('supports a borderless trigger for the composer controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RecodexTheme.light,
        home: Scaffold(
          body: Center(
            child: RecodexDropdown<String>(
              value: 'medium',
              options: const [
                RecodexDropdownOption(value: 'medium', label: '中'),
              ],
              showBorder: false,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    final trigger = find.ancestor(
      of: find.text('中'),
      matching: find.byType(DecoratedBox),
    );
    final decoration = tester.widget<DecoratedBox>(trigger.first).decoration;
    expect((decoration as BoxDecoration).border, isNull);
  });

  testWidgets('trigger follows the selected label inside a wider parent', (
    tester,
  ) async {
    var selected = 'short';
    await tester.pumpWidget(
      MaterialApp(
        theme: RecodexTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: StatefulBuilder(
                builder: (context, setState) => RecodexDropdown<String>(
                  value: selected,
                  compact: true,
                  maxWidth: 180,
                  options: const [
                    RecodexDropdownOption(value: 'short', label: '舒适'),
                    RecodexDropdownOption(value: 'long', label: '特大 · 32'),
                  ],
                  onChanged: (next) => setState(() => selected = next),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final trigger = find.byType(RecodexPopupMenuButton<String>);
    final shortWidth = tester.getSize(trigger).width;
    expect(shortWidth, lessThan(100));

    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.tap(find.text('特大 · 32'));
    await tester.pumpAndSettle();
    expect(selected, 'long');
    expect(tester.getSize(trigger).width, greaterThan(shortWidth));
    expect(tester.getSize(trigger).width, lessThan(180));

    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.tap(find.text('舒适'));
    await tester.pumpAndSettle();
    expect(tester.getSize(trigger).width, shortWidth);
  });

  testWidgets('long labels and large text fit a constrained trigger', (
    tester,
  ) async {
    const label = '工作区 / projects / a-very-long-project-name';
    await tester.pumpWidget(
      MaterialApp(
        theme: RecodexTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                child: RecodexDropdown<String>(
                  value: 'long',
                  leadingIcon: RecodexIcons.folderOpen,
                  compact: true,
                  options: const [
                    RecodexDropdownOption(value: 'long', label: label),
                  ],
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final trigger = find.byType(RecodexPopupMenuButton<String>);
    final triggerRect = tester.getRect(trigger);
    expect(triggerRect.width, 120);
    expect(
      tester.getRect(find.byIcon(RecodexIcons.chevronDown)).right,
      lessThan(triggerRect.right),
    );

    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(PopupMenuItem<String>)).width,
      greaterThan(triggerRect.width),
    );
    expect(find.text(label), findsNWidgets(2));
  });

  testWidgets('RecodexPopupMenuButton uses the global rounded menu theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RecodexTheme.dark,
        home: Scaffold(
          body: Center(
            child: RecodexPopupMenuButton<String>(
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'new', child: Text('新建配对')),
                PopupMenuItem(value: 'manage', child: Text('管理配对')),
              ],
              child: const Text('配对菜单'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('配对菜单'));
    await tester.pumpAndSettle();

    expect(find.text('新建配对'), findsOneWidget);
    final theme = Theme.of(tester.element(find.text('新建配对')));
    final shape = theme.popupMenuTheme.shape as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(18));
    expect(
      theme.popupMenuTheme.menuPadding,
      const EdgeInsets.symmetric(vertical: 7),
    );
  });
}
