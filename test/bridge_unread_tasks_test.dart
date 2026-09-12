import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/pages/main/bridge_controller.dart';

void main() {
  test('counts only unread successful completions', () {
    final bridge = BridgeController();
    bridge.sessions.addAll([
      const SessionRecord(
        id: 'done',
        workspace: '/workspace',
        prompt: '完成',
        status: 'completed',
        createdAt: '',
        updatedAt: '',
      ),
      const SessionRecord(
        id: 'failed',
        workspace: '/workspace',
        prompt: '失败',
        status: 'failed',
        createdAt: '',
        updatedAt: '',
      ),
      const SessionRecord(
        id: 'running',
        workspace: '/workspace',
        prompt: '执行中',
        status: 'running',
        createdAt: '',
        updatedAt: '',
      ),
    ]);
    bridge.unreadCompletedTaskIds.addAll({'done', 'failed', 'missing'});

    expect(bridge.unreadCompletedTaskCount, 1);
  });
}
