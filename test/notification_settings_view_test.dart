import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:recodex/app/pages/settings/notification_settings_view.dart';
import 'package:recodex/app/pages/settings/theme_controller.dart';
import 'package:recodex/app/routes/app_pages.dart';
import 'package:recodex/app/services/task_notification_controller.dart';
import 'package:recodex/app/theme/recodex_theme.dart';

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put(ThemeController(), permanent: true);
    Get.put(TaskNotificationController(), permanent: true);
  });

  tearDown(Get.reset);

  testWidgets('opens notification settings as a route', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        theme: RecodexTheme.light,
        darkTheme: RecodexTheme.dark,
        getPages: AppPages.routes,
        initialRoute: Routes.notifications,
      ),
    );
    await tester.pump();

    expect(find.byType(NotificationSettingsPage), findsOneWidget);
    expect(find.text('消息通知'), findsNWidgets(2));
    expect(find.text('通知类型', skipOffstage: false), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('权限与测试'),
      420,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('投递方式', skipOffstage: false), findsOneWidget);
    expect(find.text('权限与测试', skipOffstage: false), findsOneWidget);
    expect(find.text('任务完成', skipOffstage: false), findsOneWidget);
    expect(find.text('中继服务断开', skipOffstage: false), findsOneWidget);
    expect(find.text('锁屏显示', skipOffstage: false), findsOneWidget);
  });

  testWidgets('updates an event preference from its switch', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        theme: RecodexTheme.light,
        darkTheme: RecodexTheme.dark,
        getPages: AppPages.routes,
        initialRoute: Routes.notifications,
      ),
    );
    await tester.pump();

    final controller = Get.find<TaskNotificationController>();
    expect(controller.completedEnabled.value, isTrue);

    // The first switch belongs to the page-level enable control. The next
    // switch is the task-completed event preference.
    await tester.tap(find.byType(Switch).at(1));
    await tester.pump();

    expect(controller.completedEnabled.value, isFalse);
  });
}
