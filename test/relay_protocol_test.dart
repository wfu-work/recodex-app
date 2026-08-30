import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recodex/app/services/relay_protocol.dart';

void main() {
  test('builds a Relay v1 hello with a verifiable endpoint proof', () async {
    final keyPair = await RelayProtocol.newKeyPair();
    final hello = await RelayProtocol.connectHello(
      keyPair: keyPair,
      spaceId: 'space-1',
      endpointId: 'app-1',
      endpointType: 'app',
      endpointName: 'Test phone',
      token: 'connect-token',
    );

    expect(hello['version'], RelayProtocol.version);
    expect(hello['type'], 'connect.hello');
    expect(hello['capabilities'], RelayProtocol.capabilities);
    final proof = Map<String, dynamic>.from(hello['endpointProof'] as Map);
    final canonical = [
      'relay-connect-v1',
      hello['version'],
      hello['requestId'],
      hello['spaceId'],
      hello['endpointId'],
      hello['endpointType'],
      hello['token'],
      proof['issuedAt'],
      proof['nonce'],
    ].join('\n');
    final publicKey = await keyPair.extractPublicKey();
    final verified = await Ed25519().verify(
      utf8.encode(canonical),
      signature: Signature(
        RelayProtocol.decodeBase64Url(proof['signature'] as String),
        publicKey: publicKey,
      ),
    );
    expect(verified, isTrue);
  });

  test('wraps and unwraps the plugin command contract', () {
    final frame = RelayProtocol.command(
      requestId: 'request-1',
      spaceId: 'space-1',
      deviceId: 'app-1',
      targetDeviceId: 'host-1',
      sequence: 7,
      command: {'type': 'host.get_status'},
    );

    expect(frame['type'], 'stream.message');
    expect(frame['streamId'], RelayProtocol.streamId);
    expect(frame['protocol'], RelayProtocol.product);
    expect(frame['to'], 'host-1');
    final payload = RelayProtocol.unwrapProductMessage({
      ...frame,
      'from': 'app-1',
    });
    expect(payload?['type'], 'codex.command');
    expect(payload?['deviceId'], 'app-1');
    expect(payload?['targetDeviceId'], 'host-1');
    expect((payload?['command'] as Map)['type'], 'host.get_status');
  });

  test('requires a complete welcome and valid transport frames', () {
    final welcome = RelayProtocol.validateWelcome({
      'version': 1,
      'type': 'connect.welcome',
      'requestId': 'hello-1',
      'connectionId': 'connection-1',
      'sessionId': 'session-1',
      'spaceId': 'space-1',
      'endpointId': 'app-1',
      'maxFrameSize': 1024,
    });
    expect(welcome['sessionId'], 'session-1');
    expect(
      () => RelayProtocol.validateWelcome({
        'version': 1,
        'type': 'connect.welcome',
        'connectionId': 'connection-1',
      }),
      throwsFormatException,
    );
    expect(
      () =>
          RelayProtocol.validateFrame({'version': 1, 'type': 'stream.message'}),
      throwsFormatException,
    );
  });
}
