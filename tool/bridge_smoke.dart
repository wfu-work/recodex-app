import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:recodex/app/services/relay_protocol.dart';

/// Protocol v1 smoke test. The Connect Token must have been issued for the
/// supplied app endpoint public key (the private seed is never logged).
Future<void> main(List<String> args) async {
  final relayUrl = _arg(args, 'relay');
  final spaceId = _arg(args, 'space');
  final token = _arg(args, 'token');
  final endpointId = _arg(args, 'endpoint');
  final targetDeviceId = _arg(args, 'target');
  final seedText = _arg(args, 'seed');
  if ([
    relayUrl,
    spaceId,
    token,
    endpointId,
    targetDeviceId,
    seedText,
  ].any((value) => value == null || value.isEmpty)) {
    throw ArgumentError(
      'usage: flutter pub run tool/bridge_smoke.dart '
      '--relay=wss://host/v1/connect --space=space --token=token '
      '--endpoint=app_id --target=host_id --seed=base64url-ed25519-seed',
    );
  }

  final relay = relayUrl!;
  final space = spaceId!;
  final connectToken = token!;
  final appEndpoint = endpointId!;
  final hostEndpoint = targetDeviceId!;
  final seed = seedText!;

  final keyPair = await RelayProtocol.keyPairFromSeed(
    RelayProtocol.decodeBase64Url(seed),
  );
  final socket = await WebSocket.connect(relay);
  final messages = StreamIterator<String>(
    socket.map((raw) => raw as String).timeout(const Duration(seconds: 8)),
  );
  Future<Map<String, dynamic>> next({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final hasMessage = await messages.moveNext().timeout(timeout);
    if (!hasMessage) throw StateError('Relay 在下一帧之前关闭连接');
    final decoded = jsonDecode(messages.current);
    if (decoded is! Map) throw StateError('Relay 返回了非对象帧');
    return Map<String, dynamic>.from(decoded);
  }

  socket.add(
    jsonEncode(
      await RelayProtocol.connectHello(
        keyPair: keyPair,
        spaceId: space,
        endpointId: appEndpoint,
        endpointType: 'app',
        endpointName: 'Dart Protocol Smoke',
        token: connectToken,
      ),
    ),
  );
  final welcome = await next();
  _expect(
    welcome['type'] == 'connect.welcome',
    'expected connect.welcome, got ${welcome['type']}',
  );

  final requestId = RelayProtocol.randomId('smoke');
  socket.add(
    jsonEncode(
      RelayProtocol.command(
        requestId: requestId,
        spaceId: space,
        deviceId: appEndpoint,
        targetDeviceId: hostEndpoint,
        sequence: 1,
        command: {'type': 'host.get_status'},
      ),
    ),
  );
  Map<String, dynamic>? result;
  while (result == null) {
    final frame = await next();
    final payload = RelayProtocol.unwrapProductMessage(frame);
    if (payload?['type'] == 'codex.command.result' &&
        payload?['requestId'] == requestId) {
      result = payload;
    }
  }
  _expect(
    result['success'] == true,
    'host.get_status failed: ${result['error']}',
  );
  await socket.close();
  await messages.cancel();
  stdout.writeln(
    jsonEncode({
      'ok': true,
      'protocolVersion': 1,
      'authed': true,
      'hostStatus': result['result'],
    }),
  );
}

String? _arg(List<String> args, String name) {
  final prefix = '--$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
