import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final runSession = args.contains('--session');
  final baseUrl = args.firstWhere(
    (arg) => !arg.startsWith('--'),
    orElse: () => 'http://127.0.0.1:8765',
  );
  final pairing = await _getJson(Uri.parse('$baseUrl/pairing'));
  final token = pairing['token'] as String? ?? '';
  if (token.isEmpty) {
    throw StateError('Pairing token is empty.');
  }

  final wsUrl = baseUrl.replaceFirst(RegExp('^http'), 'ws');
  final socket = await WebSocket.connect('$wsUrl/ws');
  var seq = 0;
  final messages = StreamIterator<String>(
    socket.map((raw) => raw as String).timeout(const Duration(seconds: 8)),
  );

  Future<Map<String, dynamic>> next({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final hasMessage = await messages.moveNext().timeout(timeout);
    if (!hasMessage) {
      throw StateError('WebSocket closed before the next message.');
    }
    return jsonDecode(messages.current) as Map<String, dynamic>;
  }

  void send(String type, Map<String, dynamic> payload) {
    seq += 1;
    socket.add(
      jsonEncode({'type': type, 'id': 'smoke_$seq', 'payload': payload}),
    );
  }

  final hello = await next();
  _expect(hello['type'] == 'bridge.hello', 'expected bridge.hello');

  send('auth.hello', {
    'deviceId': 'smoke_dart',
    'deviceName': 'Dart Smoke',
    'token': token,
  });
  final auth = await next();
  _expect(auth['type'] == 'auth.ok', 'expected auth.ok, got ${auth['type']}');

  send('workspace.list', {});
  final workspacesResult = await next();
  _expect(
    workspacesResult['type'] == 'workspace.list.result',
    'expected workspace.list.result',
  );
  final workspacePayload = workspacesResult['payload'] as Map<String, dynamic>;
  final workspaces = (workspacePayload['workspaces'] as List?) ?? const [];

  send('device.list', {});
  final devicesResult = await next();
  _expect(
    devicesResult['type'] == 'device.list.result',
    'expected device.list.result',
  );

  var sessionChecked = false;
  if (workspaces.isNotEmpty) {
    final workspace = (workspaces.first as Map).cast<String, dynamic>();
    send('git.status', {'workspace': workspace['name']});
    final gitResult = await next();
    _expect(
      gitResult['type'] == 'git.status.result',
      'expected git.status.result',
    );

    if (runSession) {
      send('session.start', {
        'workspace': workspace['name'],
        'prompt': 'Reply with exactly: recodex-smoke-ok',
      });
      var done = false;
      while (!done) {
        final message = await next(timeout: const Duration(seconds: 120));
        switch (message['type']) {
          case 'session.created':
          case 'session.event':
            break;
          case 'session.done':
            done = true;
          case 'session.error':
            throw StateError('session failed: ${message['payload']}');
          default:
            break;
        }
      }
      sessionChecked = true;
    }
  }

  await socket.close();
  await messages.cancel();
  stdout.writeln(
    jsonEncode({
      'ok': true,
      'workspaces': workspaces.length,
      'authed': true,
      'gitChecked': workspaces.isNotEmpty,
      'sessionChecked': sessionChecked,
    }),
  );
}

Future<Map<String, dynamic>> _getJson(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(body, uri: uri);
    }
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
