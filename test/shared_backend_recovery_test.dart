import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/pages/main/bridge_controller.dart';

Future<void> until(bool Function() check) async {
  for (var i = 0; i < 600; i++) {
    if (check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('condition timed out');
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real websocket: replay deduplication, restart, interaction recovery and stop confirmation',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'recodex-flutter-recovery-',
      );
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => directory.path,
      );
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (_) async => null,
      );
      await BridgeController.initializeStorage();
      await GetStorage('recodex').write('recodex_pairings_v2', []);
      Get.testMode = true;
      final bridge = Get.put(BridgeController());
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      WebSocket? socket;
      var messageId = 0;
      var epoch = 'first';
      var sequence = 0;
      var active = true;
      var holdReads = false;
      final commands = <Map<String, dynamic>>[];
      final journal = <Map<String, dynamic>>[];
      final interactions = <Map<String, dynamic>>[];
      Map<String, dynamic>? heldRead;
      List<Map<String, dynamic>>? snapshotTurns;
      Map<String, dynamic> thread() => {
        'id': 'task',
        'cwd': '/tmp/project',
        'name': 'fixture',
        'status': {'type': active ? 'active' : 'idle'},
        'turns': snapshotTurns ?? [
          {
            'id': 'turn',
            'status': active ? 'inProgress' : 'interrupted',
            'items': [],
          },
        ],
      };
      void send(Map<String, dynamic> payload) => socket!.add(
        jsonEncode({
          'version': 1,
          'type': 'stream.message',
          'messageId': 'm${messageId++}',
          'protocol': 'codex.v1',
          'from': 'host',
          'to': 'phone',
          'payload': payload,
          if (payload['sequence'] != null) 'sequence': payload['sequence'],
        }),
      );
      void respond(Map<String, dynamic> request, Object? result) => send({
        'type': 'codex.command.result',
        'requestId': request['requestId'],
        'success': true,
        'result': result,
      });
      Map<String, dynamic> event(String type, Map<String, dynamic> data) {
        final frame = {
          'type': 'codex.event',
          'eventStreamId': epoch,
          'sequence': ++sequence,
          'threadId': 'task',
          'turnId': 'turn',
          'event': {'type': type, 'data': data},
        };
        journal.add(frame);
        return frame;
      }

      final listening = server.listen((request) async {
        socket = await WebSocketTransformer.upgrade(request);
        socket!.listen((raw) {
          final frame = jsonDecode(raw as String) as Map<String, dynamic>;
          if (frame['type'] == 'connect.hello') {
            socket!.add(
              jsonEncode({
                'version': 1,
                'type': 'connect.welcome',
                'requestId': frame['requestId'],
                'spaceId': 'space',
                'endpointId': 'phone',
                'connectionId': 'c',
                'sessionId': 's',
                'maxFrameSize': 1000000,
              }),
            );
            return;
          }
          if (frame['type'] != 'stream.message') return;
          final request = Map<String, dynamic>.from(frame['payload']);
          commands.add(request);
          final command = request['command'] as Map;
          switch (command['type']) {
            case 'sync.request':
              if (command['eventStreamId'] == epoch &&
                  command.containsKey('lastSequence')) {
                respond(request, {
                  'mode': 'events',
                  'eventStreamId': epoch,
                  'latestSequence': sequence,
                  'events': journal
                      .where(
                        (item) =>
                            (item['sequence'] as int) >
                            (command['lastSequence'] as int),
                      )
                      .toList(),
                });
              } else {
                respond(request, {
                  'mode': 'snapshot',
                  'eventStreamId': epoch,
                  'latestSequence': sequence,
                  'threads': {
                    'data': [thread()],
                  },
                  'projects': {'data': []},
                });
              }
            case 'thread.list':
              respond(request, {
                'data': [thread()],
              });
            case 'thread.read':
              if (holdReads) {
                heldRead = request;
                break;
              }
              respond(request, {
                'thread': thread(),
                'pendingInteractions': interactions,
              });
            case 'thread.status':
              respond(request, {
                'thread': thread(),
                'pendingInteractions': interactions,
              });
            case 'host.get_status':
              respond(request, {
                'eventStreamId': epoch,
                'appServer': {'state': 'ready'},
              });
            case 'turn.start':
              send({
                'type': 'codex.command.result',
                'requestId': request['requestId'],
                'success': false,
                'error': {
                  'code': command['text'] == '拒绝测试'
                      ? 'APP_SERVER_ERROR'
                      : 'COMMAND_OUTCOME_UNKNOWN',
                  'message': 'lost reply',
                },
              });
            case 'turn.interrupt':
              respond(request, {
                'status': 'requested',
                'threadId': 'task',
                'turnId': 'turn',
              });
            default:
              respond(request, {'data': []});
          }
        });
      });
      try {
        await bridge.connect(
          inputBaseUrl: 'ws://127.0.0.1:${server.port}',
          token: 'fixture',
          inputDeviceName: 'fixture',
          inputSpaceId: 'space',
          inputTargetDeviceId: 'host',
          inputEndpointId: 'phone',
        );
        await until(() => bridge.connected.value && bridge.sessions.isNotEmpty);
        bridge.selectSession(bridge.sessions.single);
        await until(
          () =>
              !bridge.timelineLoading.value &&
              bridge.timelineStatus.value.isActive,
        );
        holdReads = true;
        send(
          event('turn.started', {
            'turn': {'id': 'turn', 'status': 'inProgress'},
          }),
        );
        final first = event('message.assistant.delta', {
          'delta': 'ALPHA',
          'itemId': 'answer',
        });
        send(first);
        await until(
          () => bridge.events.any((item) => item.text.contains('ALPHA')),
        );
        event('message.assistant.delta', {
          'delta': 'BETA',
          'itemId': 'answer',
        }); // deliberately lost live frame
        send(
          event('message.assistant.delta', {
            'delta': 'GAMMA',
            'itemId': 'answer',
          }),
        );
        await until(
          () => bridge.events.any((item) => item.text.contains('GAMMA')),
        );
        send(first); // a new transport message id carrying a duplicate event
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final output = bridge.events
            .where((item) => item.kind == 'assistant')
            .map((item) => item.text)
            .join();
        expect(output, 'ALPHABETAGAMMA');
        send(event('message.assistant.delta', {
          'delta': 'ALPHA', 'itemId': 'answer',
        }));
        await until(() => bridge.events.any((item) =>
          item.text == 'ALPHABETAGAMMAALPHA'));
        expect(await bridge.steerCurrentTurn('补充测试'), true);
        final steer = commands.lastWhere(
          (c) => c['command']['type'] == 'turn.steer',
        );
        expect(steer['turnId'], 'turn');
        bridge.interrupt();
        await until(() => bridge.interactionNotice.value.contains('等待任务确认'));
        expect(
          bridge.timelineStatus.value.isActive,
          true,
          reason: 'receipt must not claim interrupted',
        );
        active = false;
        send(
          event('turn.completed', {
            'turn': {'id': 'turn', 'status': 'interrupted'},
          }),
        );
        await until(
          () => bridge.timelineStatus.value == TimelineTaskStatus.interrupted,
        );
        expect(bridge.interactionNotice.value, isEmpty);
        bridge.startSession('未知回执测试');
        await until(() => bridge.lastError.value.contains('命令结果尚未确认'));
        expect(
          bridge.timelineStatus.value.isActive,
          true,
          reason: 'an unknown result is not a failed turn',
        );
        bridge.startSession('拒绝测试');
        await until(() => bridge.lastError.value.contains('APP_SERVER_ERROR'));
        expect(
          bridge.timelineStatus.value,
          TimelineTaskStatus.unknown,
          reason: 'a rejected command must not fail an existing desktop task',
        );
        // A new connector can have a higher sequence already. It must still
        // force a snapshot and hydrate the selected task, discarding old reads.
        epoch = 'second';
        sequence = 100;
        journal.clear();
        holdReads = false;
        interactions.add({
          'approvalId': 'fresh',
          'kind': 'userInput',
          'canRespond': true,
          'params': {
            'threadId': 'task',
            'turnId': 'turn',
            'questions': [
              {'id': 'q', 'question': 'continue?'},
            ],
          },
        });
        send({
          'type': 'host.snapshot',
          'status': {
            'eventStreamId': epoch,
            'appServer': {'state': 'ready'},
          },
        });
        await until(() => bridge.pendingInteractions.containsKey('fresh'));
        if (heldRead != null) {
          respond(heldRead!, {'thread': thread(), 'pendingInteractions': []});
        }
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(bridge.pendingInteractions.containsKey('fresh'), true);
        final resolved = event('interaction.resolved', {});
        resolved['event'] = {
          'type': 'interaction.resolved',
          'approvalId': 'fresh',
          'params': {'threadId': 'task'},
        };
        interactions.clear();
        send(resolved);
        await until(() => bridge.pendingInteractions.isEmpty);
        expect(
          commands.where((c) => c['command']['type'] == 'turn.start').length,
          2,
        );
        expect(
          commands.where((c) => c['command']['type'] == 'sync.request').length,
          lessThan(12),
          reason: 'recovery must settle',
        );

        // History omits live-only turn diffs. Those patches and repeated
        // commentary must stay with their original turn after reconciliation.
        active = true;
        Map<String, dynamic> turn(String id, String status) => {
          'id': id, 'status': status, 'items': [
            {'id': 'user-$id', 'type': 'userMessage', 'content': [
              {'type': 'text', 'text': '问题 $id'},
            ]},
            {'id': 'message-$id', 'type': 'agentMessage',
             'phase': 'commentary', 'text': '正在检查'},
          ],
        };
        snapshotTurns = [turn('a', 'completed'), turn('b', 'inProgress')];
        bridge.events.assignAll(const [
          SessionEvent(kind: 'user', text: '问题 a', turnId: 'a', itemId: 'user-a'),
          SessionEvent(kind: 'assistant', text: '正在检查', turnId: 'a',
            itemId: 'message-a'),
          SessionEvent(kind: 'git_change', text: '', turnId: 'a',
            itemId: 'turn-diff:a', fileDiffs: {'old.dart': '@@ -0,0 +1 @@\n+old'}),
          SessionEvent(kind: 'done', text: '', turnId: 'a', itemId: 'turn-end:a'),
          SessionEvent(kind: 'user', text: '问题 b', turnId: 'b', itemId: 'user-b'),
          SessionEvent(kind: 'assistant', text: '正在检查', turnId: 'b',
            itemId: 'message-b'),
          SessionEvent(kind: 'assistant', text: '正在检查', turnId: 'b',
            itemId: 'another-message-b'),
        ]);
        bridge.selectSession(const SessionRecord(id: 'task', workspace: '/tmp/project',
          prompt: '', status: 'active', createdAt: '', updatedAt: ''));
        await until(() => !bridge.timelineLoading.value && bridge.events.any(
          (item) => item.itemId == 'message-b' && item.phase == 'commentary'));
        final split = bridge.events.indexWhere((item) => item.itemId == 'user-b');
        expect(split, greaterThan(0));
        expect(bridge.events.skip(split).where((item) => item.turnId == 'a'), isEmpty);
        expect(bridge.events.where((item) => item.kind == 'assistant').length, 3);
        expect(GitSnapshot.fromEvents(bridge.events.skip(split)).fileDiffs, isEmpty);
        expect(GitSnapshot.fromEvents(bridge.events.take(split)).fileDiffs.keys, ['old.dart']);

        // The same placement rule applies to a late live patch, before any
        // subsequent snapshot has a chance to repair the transcript.
        final late = event('diff.updated', {
          'diff': 'diff --git a/late.dart b/late.dart\n@@ -0,0 +1 @@\n+late\n',
        });
        late['turnId'] = 'a';
        send(late);
        await until(() => bridge.events.any((item) => item.fileDiffs.containsKey('late.dart')));
        final currentPrompt = bridge.events.indexWhere((item) => item.itemId == 'user-b');
        expect(bridge.events.skip(currentPrompt).where((item) => item.turnId == 'a'), isEmpty);

        await socket!.close();
        await until(() => bridge.events.any((item) =>
          item.kind == 'reconnecting' && item.text.contains('正在重新连接')));
        await until(() => bridge.connected.value && bridge.events.any((item) =>
          item.kind == 'reconnecting' && item.text == '连接已恢复'));
        expect(bridge.events.where((item) => item.kind == 'reconnecting' &&
          item.text.contains('正在重新连接')), isEmpty);
      } finally {
        await bridge.disconnect(silent: true);
        Get.reset();
        await socket?.close();
        await listening.cancel();
        await server.close(force: true);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await directory.delete(recursive: true);
      }
    },
  );
}
