import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:recodex/app/pages/main/bridge_controller.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/services/composer_images.dart';

Future<void> until(bool Function() check) async {
  final caller = StackTrace.current;
  for (var i = 0; i < 500; i++) {
    if (check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  Error.throwWithStackTrace(StateError('condition timed out'), caller);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'image sends preserve task identity, configure new tasks, and never retry uncertain turns',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'recodex-image-relay-',
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
      await GetStorage('recodex').erase();
      Get.testMode = true;
      final bridge = Get.put(BridgeController());
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      WebSocket? socket;
      var messageId = 0;
      var newThread = 0;
      var revision = 0;
      var dropTurnReply = false;
      final commands = <Map<String, dynamic>>[];
      final uploads = <String, List<int>>{};
      final persisted = <String, Map<String, dynamic>>{};
      Map<String, dynamic> thread(String id) => {
        'id': id,
        'cwd': '/tmp/project',
        'name': id,
        'status': {'type': 'idle'},
        'turns': persisted[id] == null ? [] : [persisted[id]],
      };
      final settings = {
        'model': 'model',
        'effort': 'medium',
        'approvalPolicy': 'on-request',
        'approvalsReviewer': 'user',
        'activePermissionProfile': {'id': ':workspace'},
        'revision': 1,
      };
      void reply(Map request, Object result) {
        if (socket?.readyState != WebSocket.open) return;
        socket!.add(
          jsonEncode({
            'version': 1,
            'type': 'stream.message',
            'messageId': 'm${messageId++}',
            'protocol': 'codex.v1',
            'from': 'host',
            'to': 'phone',
            'payload': {
              'type': 'codex.command.result',
              'requestId': request['requestId'],
              'success': true,
              'result': result,
            },
          }),
        );
      }

      final listening = server.listen((request) async {
        socket = await WebSocketTransformer.upgrade(request);
        socket!.listen((raw) {
          final frame = jsonDecode(raw as String) as Map;
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
                'maxFrameSize': 180000,
              }),
            );
            return;
          }
          if (frame['type'] != 'stream.message') return;
          final message = Map<String, dynamic>.from(frame['payload']);
          commands.add(message);
          final command = message['command'] as Map;
          final id = message['threadId'] as String?;
          final uploadId = command['uploadId'] as String?;
          switch (command['type']) {
            case 'host.get_status':
              reply(message, {
                'eventStreamId': 'images',
                'appServer': {'state': 'ready'},
                'capabilities': {
                  'imageAttachments': {'version': 1},
                },
              });
            case 'sync.request':
              if (command['eventStreamId'] == 'images' &&
                  command.containsKey('lastSequence')) {
                reply(message, {
                  'mode': 'events',
                  'eventStreamId': 'images',
                  'latestSequence': 0,
                  'events': [],
                });
              } else {
                reply(message, {
                  'mode': 'snapshot',
                  'eventStreamId': 'images',
                  'latestSequence': 0,
                  'threads': {
                    'data': [thread('a'), thread('b')],
                  },
                  'projects': {'data': []},
                });
              }
            case 'thread.list':
              reply(message, {
                'data': [thread('a'), thread('b')],
              });
            case 'thread.read' || 'thread.status':
              reply(message, {
                'thread': thread(id!),
                'threadSettings': settings,
                'snapshotRevision': ++revision,
              });
            case 'thread.settings.update':
              reply(message, {'threadId': id, 'threadSettings': settings});
            case 'thread.create':
              reply(message, {
                'thread': thread('new-${++newThread}'),
                'threadSettings': settings,
              });
            case 'image.upload.begin':
              uploads.putIfAbsent(uploadId!, () => []);
              reply(message, {
                'uploadId': uploadId,
                'offset': uploads[uploadId]!.length,
              });
            case 'image.upload.append':
              expect((raw).length, lessThan(180000));
              expect(command['offset'], uploads[uploadId]!.length);
              uploads[uploadId]!.addAll(base64Decode(command['data']));
              reply(message, {'offset': uploads[uploadId]!.length});
            case 'image.upload.finish':
              reply(message, {'attachmentId': uploadId});
            case 'turn.start':
              final turnId = 'turn-${commands.length}';
              persisted[id!] = {
                'id': turnId,
                'status': 'completed',
                'items': [
                  {
                    'type': 'userMessage',
                    'id': 'user-$turnId',
                    'content': [
                      {'type': 'text', 'text': command['text']},
                      {
                        'type': 'image',
                        'thumbnailDataUrl': 'data:image/png;base64,cmVtb3Rl',
                        'resourceUrl': 'https://example.com/image.png',
                      },
                    ],
                  },
                ],
              };
              if (!dropTurnReply) {
                reply(message, {
                  'turn': {'id': turnId},
                });
              }
            default:
              reply(message, {'data': []});
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
        await until(
          () =>
              bridge.sessions.length >= 2 &&
              bridge.imageAttachmentsAvailable.value,
        );
        bridge.selectSession(bridge.sessions.firstWhere((s) => s.id == 'a'));
        await until(() => !bridge.timelineLoading.value);
        final bytes = Uint8List.fromList(
          List.generate(230000, (index) => index % 256),
        );
        final image = ComposerImage(
          name: 'test.png',
          bytes: bytes,
          thumbnail: Uint8List.fromList([1, 2, 3]),
        );
        final context = bridge.imageMessageContext;
        final uploadedId = await bridge.uploadImage(image, context, (_) {});
        expect(uploads[uploadedId], orderedEquals(bytes));
        expect(
          await bridge.sendImageMessage('看看图片', [image], [uploadedId], context),
          ImageSendOutcome.accepted,
        );
        await until(
          () => bridge.events.any((e) => e.itemId?.startsWith('user-') == true),
        );
        final user = bridge.events.where((e) => e.kind == 'user').toList();
        expect(user, hasLength(1));
        expect(
          user.single.attachments,
          hasLength(1),
          reason: 'local preview is replaced by persisted metadata',
        );
        final command = commands.lastWhere(
          (m) => m['command']['type'] == 'turn.start',
        );
        expect(command['threadId'], 'a');
        expect(command['command']['attachmentIds'], [uploadedId]);
        expect(command['command'].containsKey('model'), isFalse);
        bridge.selectSession(bridge.sessions.firstWhere((s) => s.id == 'b'));
        await expectLater(
          () => bridge.uploadImage(image, context, (_) {}),
          throwsA(isA<ImageCommandException>()),
        );
        bridge.startNewConversation();
        final newContext = bridge.imageMessageContext;
        final newId = await bridge.uploadImage(image, newContext, (_) {});
        expect(
          await bridge.sendImageMessage('', [image], [newId], newContext),
          ImageSendOutcome.accepted,
        );
        expect(bridge.selectedSessionId.value, 'new-1');
        final relevant = commands
            .where(
              (m) =>
                  m['command']['type'] == 'thread.create' ||
                  m['threadId'] == 'new-1',
            )
            .map((m) => m['command']['type'])
            .toList();
        expect(relevant.take(3), [
          'thread.create',
          'thread.settings.update',
          'turn.start',
        ]);
        await until(() => !bridge.timelineStatus.value.isActive);
        final unknownContext = bridge.imageMessageContext;
        final unknownId = await bridge.uploadImage(
          image,
          unknownContext,
          (_) {},
        );
        dropTurnReply = true;
        final before = commands
            .where((m) => m['command']['type'] == 'turn.start')
            .length;
        final sending = bridge.sendImageMessage(
          '回执丢失',
          [image],
          [unknownId],
          unknownContext,
        );
        await until(
          () =>
              commands
                  .where((m) => m['command']['type'] == 'turn.start')
                  .length >
              before,
        );
        await bridge.disconnect(silent: true);
        expect(await sending, ImageSendOutcome.unknown);
        expect(bridge.timelineStatus.value, TimelineTaskStatus.unknown);
        expect(
          commands.where((m) => m['command']['type'] == 'turn.start').length,
          before + 1,
        );
      } finally {
        await bridge.disconnect(silent: true);
        await socket?.close();
        await listening.cancel();
        await server.close(force: true);
        Get.reset();
      }
    },
  );
}
