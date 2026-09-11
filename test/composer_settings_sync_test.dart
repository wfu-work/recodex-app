import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:recodex/app/pages/main/bridge_controller.dart';
import 'package:recodex/app/pages/settings/settings_preferences_controller.dart';

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
    'composer synchronizes desktop edits, phone edits, selection, stale replies and new tasks',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'recodex-composer-',
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
      final preferences = Get.put(SettingsPreferencesController());
      await preferences.ready;
      final bridge = Get.put(BridgeController());
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      WebSocket? socket;
      var messageId = 0;
      var sequence = 0;
      var revision = 1;
      var epoch = 'first';
      var holdWrites = false;
      var rejectWrites = false;
      String? persistedPrompt;
      final held = <Map<String, dynamic>>[];
      final commands = <Map<String, dynamic>>[];
      final settings = <String, Map<String, dynamic>>{
        'a': {
          'model': 'astra',
          'effort': 'high',
          'approvalPolicy': 'never',
          'approvalsReviewer': 'user',
          'activePermissionProfile': {'id': ':danger-full-access'},
          'revision': revision,
        },
        'b': {
          'model': 'sol',
          'effort': 'low',
          'approvalPolicy': 'on-request',
          'approvalsReviewer': 'user',
          'activePermissionProfile': {'id': ':read-only'},
          'revision': revision,
        },
      };
      Map<String, dynamic> thread(String id) => {
        'id': id,
        'cwd': '/tmp/project',
        'name': id,
        'status': {'type': 'idle'},
        'turns': id == 'new' && persistedPrompt != null
            ? [
                {
                  'id': 'turn-new',
                  'status': 'inProgress',
                  'items': [
                    {
                      'id': 'user-new',
                      'type': 'userMessage',
                      'content': [
                        {'type': 'text', 'text': persistedPrompt},
                      ],
                    },
                  ],
                },
              ]
            : [],
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
        }),
      );
      void respond(Map<String, dynamic> request, Object? result) => send({
        'type': 'codex.command.result',
        'requestId': request['requestId'],
        'success': true,
        'result': result,
      });
      void broadcast(String id, Map<String, dynamic> value) => send({
        'type': 'codex.event',
        'eventStreamId': epoch,
        'sequence': ++sequence,
        'threadId': id,
        'event': {
          'type': 'thread.settings.updated',
          'data': {'threadId': id, 'threadSettings': value},
        },
      });
      void applyWrite(Map<String, dynamic> request) {
        final command = request['command'] as Map;
        final id = request['threadId'] as String;
        if (rejectWrites) {
          send({
            'type': 'codex.command.result',
            'requestId': request['requestId'],
            'success': false,
            'error': {'code': 'COMMAND_NOT_ALLOWED', 'message': '权限未启用'},
          });
          return;
        }
        final next = {...settings[id]!, 'revision': ++revision};
        for (final key in ['model', 'effort']) {
          if (command.containsKey(key)) next[key] = command[key];
        }
        if (command['permissionMode'] != null) {
          final mode = command['permissionMode'];
          next['activePermissionProfile'] = {
            'id': mode == '完全访问权限'
                ? ':danger-full-access'
                : mode == '只读权限'
                ? ':read-only'
                : ':workspace',
          };
          next['approvalPolicy'] = mode == '完全访问权限' ? 'never' : 'on-request';
          next['approvalsReviewer'] = mode == '自动审查' ? 'auto_review' : 'user';
        }
        settings[id] = next;
        broadcast(id, next);
        respond(request, {'threadId': id, 'threadSettings': next});
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
          final id = request['threadId'] as String?;
          switch (command['type']) {
            case 'sync.request':
              if (command['eventStreamId'] == epoch &&
                  command.containsKey('lastSequence')) {
                respond(request, {
                  'mode': 'events',
                  'eventStreamId': epoch,
                  'latestSequence': sequence,
                  'events': [],
                });
                break;
              }
              respond(request, {
                'mode': 'snapshot',
                'eventStreamId': epoch,
                'latestSequence': sequence,
                'threads': {'data': settings.keys.map(thread).toList()},
                'projects': {'data': []},
              });
            case 'thread.list':
              respond(request, {'data': settings.keys.map(thread).toList()});
            case 'thread.read' || 'thread.status':
              respond(request, {
                'thread': thread(id!),
                'threadSettings': settings[id],
                'pendingInteractions': [],
              });
            case 'host.get_status':
              respond(request, {
                'eventStreamId': epoch,
                'appServer': {'state': 'ready'},
              });
            case 'model.list':
              respond(request, {
                'data': [
                  {
                    'model': 'astra',
                    'displayName': 'GPT-6-Astra',
                    'isDefault': true,
                    'supportedReasoningEfforts': [
                      'low',
                      'medium',
                      'high',
                      'ultra',
                    ],
                    'defaultReasoningEffort': 'medium',
                  },
                  {
                    'model': 'sol',
                    'displayName': 'GPT-5.6-Sol',
                    'supportedReasoningEfforts': ['low', 'high'],
                    'defaultReasoningEffort': 'low',
                  },
                ],
              });
            case 'thread.settings.update':
              if (holdWrites) {
                held.add(request);
              } else {
                applyWrite(request);
              }
            case 'thread.create':
              settings['new'] = {...settings['b']!, 'revision': ++revision};
              respond(request, {
                'thread': thread('new'),
                'threadSettings': settings['new'],
              });
            case 'turn.start':
              respond(request, {
                'turn': {'id': 'turn', 'status': 'inProgress'},
              });
            default:
              respond(request, {'data': []});
          }
        });
      });
      int count(String type) =>
          commands.where((c) => c['command']['type'] == type).length;
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
              bridge.connected.value &&
              bridge.sessions.length == 2 &&
              bridge.composerContext.value.models.length == 2,
        );
        bridge.selectSession(bridge.sessions.firstWhere((s) => s.id == 'a'));
        await until(() => bridge.permissionMode.value == '完全访问权限');
        expect(bridge.composerContext.value.reasoningEffort, 'high');
        expect(count('thread.settings.update'), 0);

        settings['a'] = {
          ...settings['a']!,
          'effort': 'ultra',
          'approvalsReviewer': 'auto_review',
          'approvalPolicy': 'on-request',
          'activePermissionProfile': {'id': ':workspace'},
          'revision': ++revision,
        };
        broadcast('a', settings['a']!);
        await until(() => bridge.permissionMode.value == '自动审查');
        expect(bridge.composerContext.value.reasoningEffort, 'ultra');
        bridge.applyTaskPreferences(preferences);
        final modelReads = count('model.list');
        bridge.refreshContext();
        await until(
          () =>
              count('model.list') > modelReads &&
              bridge.composerContext.value.models.length == 2,
        );
        expect(bridge.composerContext.value.reasoningEffort, 'ultra');
        expect(
          count('thread.settings.update'),
          0,
          reason: 'remote updates and local defaults must not echo writes',
        );

        holdWrites = true;
        bridge.setReasoningEffort('high');
        bridge.setReasoningEffort('low');
        await until(() => held.length == 2);
        applyWrite(held.removeAt(0));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          bridge.composerContext.value.reasoningEffort,
          'low',
          reason: 'old response must not replace a newer local choice',
        );
        bridge.startSession('after settings');
        expect(count('turn.start'), 0);
        applyWrite(held.removeAt(0));
        await until(() => count('turn.start') == 1);
        expect(
          commands
              .lastWhere((c) => c['command']['type'] == 'turn.start')['command']
              .containsKey('model'),
          false,
        );
        holdWrites = false;
        bridge.setComposerModel('sol');
        await until(() => settings['a']!['model'] == 'sol');
        bridge.setPermissionMode('只读权限');
        await until(
          () => settings['a']!['activePermissionProfile']['id'] == ':read-only',
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        rejectWrites = true;
        bridge.setPermissionMode('完全访问权限');
        await until(
          () => bridge.lastError.value.contains('COMMAND_NOT_ALLOWED'),
        );
        expect(bridge.permissionMode.value, '只读权限');
        rejectWrites = false;

        holdWrites = true;
        bridge.setReasoningEffort('high');
        await until(() => held.isNotEmpty);
        bridge.selectSession(bridge.sessions.firstWhere((s) => s.id == 'b'));
        await until(
          () =>
              !bridge.timelineLoading.value &&
              bridge.composerContext.value.model == 'sol',
        );
        applyWrite(held.removeAt(0));
        holdWrites = false;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          bridge.composerContext.value.reasoningEffort,
          'low',
          reason: 'a previous task acknowledgement must not change this task',
        );
        settings['a'] = {
          ...settings['a']!,
          'model': 'astra',
          'effort': 'ultra',
          'revision': ++revision,
        };
        broadcast('a', settings['a']!);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          bridge.composerContext.value.model,
          'sol',
          reason: 'background task must not alter selected composer',
        );
        bridge.selectSession(bridge.sessions.firstWhere((s) => s.id == 'a'));
        await until(
          () => bridge.composerContext.value.reasoningEffort == 'ultra',
        );
        broadcast('a', {...settings['a']!, 'effort': 'low', 'revision': 1});
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(bridge.composerContext.value.reasoningEffort, 'ultra');

        // A restart resets the revision namespace and rehydrates authoritative values.
        epoch = 'second';
        sequence = 0;
        revision = 1;
        settings['a'] = {
          ...settings['a']!,
          'effort': 'medium',
          'revision': revision,
        };
        send({
          'type': 'host.snapshot',
          'status': {
            'eventStreamId': epoch,
            'appServer': {'state': 'ready'},
          },
        });
        await until(
          () => bridge.composerContext.value.reasoningEffort == 'medium',
        );
        settings['a'] = {
          ...settings['a']!,
          'activePermissionProfile': {'id': 'company'},
          'revision': ++revision,
        };
        broadcast('a', settings['a']!);
        await until(() => bridge.permissionMode.value == '自定义权限（company）');

        bridge.startNewConversation();
        bridge.setComposerModel('astra');
        bridge.setReasoningEffort('high');
        bridge.setPermissionMode('自动审查');
        holdWrites = true;
        persistedPrompt = 'new task';
        bridge.startSession('new task');
        await until(() => held.isNotEmpty);
        expect(count('turn.start'), 1);
        final initial = held.removeAt(0);
        expect(initial['threadId'], 'new');
        expect(initial['command']['effort'], 'high');
        expect(initial['command']['permissionMode'], '自动审查');
        applyWrite(initial);
        await until(() => count('turn.start') == 2);
        await until(
          () =>
              bridge.events
                  .where(
                    (event) => event.kind == 'user' && event.text == 'new task',
                  )
                  .length ==
              1,
        );
        expect(bridge.composerContext.value.reasoningEffort, 'high');
        expect(bridge.permissionMode.value, '自动审查');

        bridge.setReasoningEffort('low');
        await until(() => held.isNotEmpty);
        bridge.startSession('cancel before settings acknowledgement');
        bridge.interrupt();
        applyWrite(held.removeAt(0));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          count('turn.start'),
          2,
          reason: 'stop must cancel a queued send',
        );

        bridge.setPermissionMode('完全访问权限');
        await until(() => held.isNotEmpty);
        bridge.startSession('rejected settings must block this message');
        rejectWrites = true;
        applyWrite(held.removeAt(0));
        await until(() => bridge.lastError.value.contains('消息未发送'));
        expect(count('turn.start'), 2);
        expect(bridge.permissionMode.value, '自动审查');
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
