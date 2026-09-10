import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/pages/main/git_diff_view.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

const _path = '/Users/wfu/project/libs/monitor.go';
const _patch =
    'diff --git a/libs/monitor.go b/libs/monitor.go\n'
    '@@ -41,2 +43,3 @@\n-old\n+new\n+line\n context\n';

Widget _page({String patch = _patch, bool dark = false, double scale = 1}) {
  return MaterialApp(
    theme: dark ? RecodexTheme.dark : RecodexTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: GitDiffPage(
      args: GitDiffPageArgs(
        selectedPath: _path,
        snapshot: GitSnapshot(
          branch: 'nw',
          status: '',
          stat: '',
          numstat: '2\t1\t$_path',
          diff: patch,
          log: '',
          fileDiffs: {_path: patch},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows source line numbers with full-width change backgrounds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();
    expect(find.text('monitor.go'), findsOneWidget);
    expect(find.text('new'), findsOneWidget);
    expect(find.text('old'), findsOneWidget);
    expect(find.text('41'), findsOneWidget);
    expect(find.text('43'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('45'), findsOneWidget);
    expect(find.textContaining('+2'), findsOneWidget);
    final row = find
        .ancestor(of: find.text('new'), matching: find.byType(ColoredBox))
        .first;
    final viewport = find.byType(ListView);
    expect(tester.getSize(row).width, tester.getSize(viewport).width);
    expect(tester.getSize(row).width, greaterThan(1200));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'wraps long lines on narrow screens and copies the original patch',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final code = 'import "${'package/' * 30}"';
      final patch = '@@ -0,0 +1 @@\n+$code\n';
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(_page(patch: patch, dark: true, scale: 1.4));
      await tester.pumpAndSettle();
      final heightBefore = tester.getSize(find.text(code)).height;
      await tester.tap(find.byTooltip('自动换行'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.text(code)).height, greaterThan(heightBefore));
      expect(tester.getSize(find.byType(ListView)).width, lessThan(360));
      await tester.tap(find.byTooltip('复制补丁'));
      await tester.pump();
      expect(copied, patch);
      expect(find.byTooltip('已复制'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets('explains missing patches and disables patch actions', (
    tester,
  ) async {
    await tester.pumpWidget(_page(patch: ''));
    await tester.pumpAndSettle();
    expect(find.text('暂无可显示的修改内容'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '复制补丁',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
