import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:recodex/app/models/bridge_models.dart';
import 'package:recodex/app/pages/main/bridge_controller.dart';
import 'package:recodex/app/services/session_cache.dart';
import 'package:recodex/app/services/session_cache_backend.dart';

Future<void> _until(bool Function() check) async {
  for (var i = 0; i < 500; i++) {
    if (check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('condition timed out');
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('recodex-project-sync-');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
    await BridgeController.initializeStorage();
    Get.testMode = true;
  });
  tearDownAll(() async {
    await directory.delete(recursive: true);
  });

  for (final liveFirst in [false, true]) {
    test(
      'project pins refresh with ${liveFirst ? 'late' : 'startup'} cache hydration',
      () async {
        await GetStorage('recodex').write('recodex_pairings_v2', []);
        final cache = _DelayedCache();
        final bridge = Get.put(BridgeController(sessionCache: cache));
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        WebSocket? socket;
        var messageId = 0;
        var threads = <Map<String, dynamic>>[];
        Object catalog = {
          'data': [
            {
              'id': 'b',
              'name': 'Second',
              'position': 1,
              'roots': [
                {'path': '/b'},
              ],
              'isPinned': true,
              'pinnedPosition': 0,
            },
            {
              'id': 'a',
              'name': 'First',
              'position': 0,
              'roots': [
                {'path': '/a'},
              ],
              'isPinned': false,
            },
          ],
        };
        var holdCatalog = !liveFirst;
        final held = <Map<String, dynamic>>[];
        void respond(Map<String, dynamic> request, Object? result) {
          socket!.add(
            jsonEncode({
              'version': 1,
              'type': 'stream.message',
              'messageId': 'project-${messageId++}',
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

        final listener = server.listen((request) async {
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
                  'connectionId': 'connection',
                  'sessionId': 'session',
                  'maxFrameSize': 1000000,
                }),
              );
              return;
            }
            if (frame['type'] != 'stream.message') return;
            final request = Map<String, dynamic>.from(frame['payload']);
            switch (request['command']['type']) {
              case 'thread.list':
                respond(request, {'data': threads});
              case 'project.list':
                if (holdCatalog) {
                  held.add(request);
                } else {
                  respond(request, catalog);
                }
              case 'sync.request':
                respond(request, {
                  'mode': 'events',
                  'eventStreamId': 'fixture',
                  'latestSequence': 0,
                  'events': [],
                });
              case 'host.get_status':
                respond(request, {
                  'eventStreamId': 'fixture',
                  'appServer': {'state': 'ready'},
                });
              default:
                respond(request, {'data': []});
            }
          });
        });

        try {
          await bridge.upsertPairing(
            PairingProfile.fromJson({
              'id': 'fixture',
              'baseUrl': 'ws://127.0.0.1:${server.port}',
              'pairingToken': 'fixture',
              'deviceName': 'fixture',
              'spaceId': 'space',
              'targetDeviceId': 'host',
              'deviceId': 'phone',
            }),
          );
          await _until(() => bridge.connected.value && cache.loading);
          if (liveFirst) {
            await _until(
              () => bridge.workspaces.any((workspace) => workspace.id == 'b'),
            );
            // An authoritative empty list must not be resurrected by a late cache.
            catalog = {'data': []};
            await _until(() => !bridge.timelineRefreshing.value);
            bridge.refreshProjects();
            await _until(
              () =>
                  bridge.workspaces.every((workspace) => workspace.id.isEmpty),
            );
          }
          cache.snapshot.complete(
            const SessionCacheSnapshot(
              workspaces: [
                WorkspaceInfo(
                  id: 'a',
                  name: 'Cached',
                  path: '/a',
                  isPinned: true,
                  pinnedPosition: 2,
                ),
              ],
            ),
          );
          await _until(() => !bridge.cacheHydrating.value);
          if (liveFirst) {
            expect(
              bridge.workspaces.any((workspace) => workspace.id == 'a'),
              isFalse,
            );
            expect(
              bridge.workspaces.any((workspace) => workspace.isPinned),
              isFalse,
            );
          } else {
            expect(bridge.workspaces.single.id, 'a');
            expect(bridge.workspaces.single.isPinned, isTrue);
            expect(bridge.workspaces.single.pinnedPosition, 2);
            holdCatalog = false;
            for (final request in held) {
              respond(request, catalog);
            }
            await _until(() => bridge.workspaces.length == 2);
            expect(bridge.workspaces.map((workspace) => workspace.id), [
              'a',
              'b',
            ]);
            expect(bridge.workspaces.first.isPinned, isFalse);
            expect(bridge.workspaces.last.isPinned, isTrue);
            bridge.selectedWorkspace.value = bridge.workspaces.last;
            bridge.selectedSessionId.value = 'selected-task';
            threads = [
              {
                'id': 'selected-task',
                'cwd': '/b',
                'projectId': 'b',
                'name': 'Current task',
                'status': 'idle',
              },
            ];
            catalog = {
              'data': [
                {
                  'id': 'b',
                  'name': 'Second',
                  'position': 1,
                  'roots': [
                    {'path': '/b'},
                  ],
                  'isPinned': false,
                },
                {
                  'id': 'a',
                  'name': 'First',
                  'position': 0,
                  'roots': [
                    {'path': '/a'},
                  ],
                  'isPinned': true,
                  'pinnedPosition': 0,
                },
              ],
            };
            await _until(() => !bridge.timelineRefreshing.value);
            bridge.refreshProjects();
            await _until(() => bridge.workspaces.first.isPinned);
            expect(bridge.workspaces.last.isPinned, isFalse);
            expect(bridge.selectedWorkspace.value?.id, 'b');
            expect(bridge.selectedWorkspace.value?.isPinned, isFalse);
            expect(bridge.selectedSessionId.value, 'selected-task');
          }
        } finally {
          if (!cache.snapshot.isCompleted) {
            cache.snapshot.complete(const SessionCacheSnapshot());
          }
          await bridge.disconnect(silent: true);
          await Get.delete<BridgeController>(force: true);
          await socket?.close();
          await listener.cancel();
          await server.close(force: true);
          Get.reset();
        }
      },
    );
  }
}

class _DelayedCache extends SessionCache {
  _DelayedCache() : super(backend: MemorySessionCacheBackend());
  final snapshot = Completer<SessionCacheSnapshot>();
  bool loading = false;

  @override
  Future<SessionCacheSnapshot> load(
    SessionCacheScope scope, {
    String? timelineThreadId,
  }) {
    loading = true;
    return snapshot.future;
  }
}
