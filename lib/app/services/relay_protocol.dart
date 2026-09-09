import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Thin Dart implementation of the shared Relay Protocol v1 wire contract.
/// Product messages are intentionally kept opaque to Relay and live in the
/// `stream.message.payload` object.
class RelayProtocol {
  RelayProtocol._();

  static const version = 1;
  static const product = 'codex.v1';
  static const streamId = 'codex';
  static const defaultMaxFrameSize = 10 * 1024 * 1024;
  static const capabilities = ['streams', 'ack', 'opaque-payload', 'codex.v1'];
  static final _ed25519 = Ed25519();

  static String encodeBase64Url(List<int> bytes) {
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static List<int> decodeBase64Url(String value) {
    final padding = (4 - value.length % 4) % 4;
    return base64Url.decode('$value${'=' * padding}');
  }

  static String randomId(String prefix) {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return '${prefix}_${encodeBase64Url(bytes)}';
  }

  static String randomNonce() {
    final random = Random.secure();
    return encodeBase64Url(List<int>.generate(24, (_) => random.nextInt(256)));
  }

  static Future<SimpleKeyPair> newKeyPair() => _ed25519.newKeyPair();

  static Future<SimpleKeyPair> keyPairFromSeed(List<int> seed) {
    if (seed.length != 32) {
      throw ArgumentError.value(
        seed.length,
        'seed',
        'Ed25519 seed must be 32 bytes',
      );
    }
    return _ed25519.newKeyPairFromSeed(seed);
  }

  static Future<String> publicKey(SimpleKeyPair keyPair) async {
    final key = await keyPair.extractPublicKey();
    return encodeBase64Url(key.bytes);
  }

  static Future<String> signConnectHello({
    required SimpleKeyPair keyPair,
    required String requestId,
    required String spaceId,
    required String endpointId,
    required String endpointType,
    required String token,
    required int issuedAt,
    required String nonce,
  }) async {
    final canonical = [
      'relay-connect-v1',
      version,
      requestId,
      spaceId,
      endpointId,
      endpointType,
      token,
      issuedAt,
      nonce,
    ].join('\n');
    final signature = await _ed25519.sign(
      utf8.encode(canonical),
      keyPair: keyPair,
    );
    return encodeBase64Url(signature.bytes);
  }

  static Future<Map<String, dynamic>> connectHello({
    required SimpleKeyPair keyPair,
    required String spaceId,
    required String endpointId,
    required String endpointType,
    required String endpointName,
    required String token,
    Map<String, dynamic>? resume,
    bool test = false,
  }) async {
    final requestId = randomId('hello');
    final issuedAt = DateTime.now().millisecondsSinceEpoch;
    final nonce = randomNonce();
    final key = await keyPair.extractPublicKey();
    final signature = await signConnectHello(
      keyPair: keyPair,
      requestId: requestId,
      spaceId: spaceId,
      endpointId: endpointId,
      endpointType: endpointType,
      token: token,
      issuedAt: issuedAt,
      nonce: nonce,
    );
    final hello = <String, dynamic>{
      'version': version,
      'type': 'connect.hello',
      'requestId': requestId,
      'spaceId': spaceId,
      'endpointId': endpointId,
      'endpointType': endpointType,
      'endpointName': endpointName,
      'token': token,
      'endpointProof': {
        'algorithm': 'Ed25519',
        'publicKey': encodeBase64Url(key.bytes),
        'issuedAt': issuedAt,
        'nonce': nonce,
        'signature': signature,
      },
      'capabilities': capabilities,
    };
    if (resume != null) hello['resume'] = resume;
    if (test) hello['test'] = true;
    return hello;
  }

  static Map<String, dynamic> validateWelcome(Map<String, dynamic> frame) {
    if (frame['version'] != version || frame['type'] != 'connect.welcome') {
      throw FormatException('Relay welcome 不是 Protocol v1 消息');
    }
    for (final field in const [
      'connectionId',
      'sessionId',
      'spaceId',
      'endpointId',
    ]) {
      final value = frame[field];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Relay welcome 缺少 $field');
      }
    }
    final maxFrameSize = frame['maxFrameSize'];
    if (maxFrameSize is! num ||
        !maxFrameSize.isFinite ||
        maxFrameSize <= 0 ||
        maxFrameSize > 0x7fffffffffffffff) {
      throw FormatException('Relay welcome 缺少有效 maxFrameSize');
    }
    return frame;
  }

  static Map<String, dynamic> validateFrame(Map<String, dynamic> frame) {
    if (frame['version'] != version) {
      throw FormatException('Relay 帧版本不受支持');
    }
    const types = {
      'stream.open',
      'stream.message',
      'stream.ack',
      'stream.close',
      'ping',
      'pong',
      'connect.welcome',
      'relay.error',
    };
    final type = frame['type'];
    if (type is! String || !types.contains(type)) {
      throw FormatException('Relay 帧类型无效');
    }
    if (type == 'stream.message' && frame['payload'] is! Map) {
      throw FormatException('stream.message 缺少 JSON payload');
    }
    if (type == 'stream.ack' &&
        (frame['ack'] is! num || (frame['ack'] as num) <= 0)) {
      throw FormatException('stream.ack 缺少 ack');
    }
    return frame;
  }

  static Future<Map<String, dynamic>> connectTokenRefreshRequest({
    required SimpleKeyPair keyPair,
    required String endpointGrant,
  }) async {
    final requestId = randomId('refresh');
    final issuedAt = DateTime.now().millisecondsSinceEpoch;
    final nonce = randomNonce();
    final canonical = [
      'relay-connect-token-v1',
      requestId,
      issuedAt,
      nonce,
      endpointGrant,
    ].join('\n');
    final signature = await _ed25519.sign(
      utf8.encode(canonical),
      keyPair: keyPair,
    );
    return {
      'endpointGrant': endpointGrant,
      'proof': {
        'requestId': requestId,
        'issuedAt': issuedAt,
        'nonce': nonce,
        'signature': encodeBase64Url(signature.bytes),
      },
    };
  }

  static Map<String, dynamic> command({
    required String requestId,
    required String spaceId,
    required String deviceId,
    required String targetDeviceId,
    required int sequence,
    required Map<String, dynamic> command,
    String? threadId,
    String? turnId,
  }) {
    final payload = <String, dynamic>{
      // Product messages have their own protocol version in addition to the
      // transport envelope version. The relay plugin validates this field
      // after unwrapping `stream.message`.
      'version': version,
      'type': 'codex.command',
      'requestId': requestId,
      'spaceId': spaceId,
      'deviceId': deviceId,
      'targetDeviceId': targetDeviceId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'command': command,
      if (threadId != null && threadId.isNotEmpty) 'threadId': threadId,
      if (turnId != null && turnId.isNotEmpty) 'turnId': turnId,
    };
    return {
      'version': version,
      'type': 'stream.message',
      'messageId': randomId('msg'),
      'streamId': streamId,
      'sequence': sequence,
      'to': targetDeviceId,
      'protocol': product,
      'encrypted': false,
      'payload': payload,
    };
  }

  static Map<String, dynamic> ack({
    required String stream,
    required int sequence,
    required String targetDeviceId,
  }) {
    return {
      'version': version,
      'type': 'stream.ack',
      'streamId': stream,
      'ack': sequence,
      'to': targetDeviceId,
      'protocol': product,
    };
  }

  static Map<String, dynamic> ping() {
    return {'version': version, 'type': 'ping'};
  }

  static Map<String, dynamic>? unwrapProductMessage(
    Map<String, dynamic> frame,
  ) {
    if (frame['type'] != 'stream.message' ||
        frame['protocol'] != product ||
        frame['payload'] is! Map) {
      return null;
    }
    final payload = Map<String, dynamic>.from(frame['payload'] as Map);
    final from = frame['from'];
    final to = frame['to'];
    if (from is String && from.isNotEmpty) payload['deviceId'] = from;
    if (to is String && to.isNotEmpty) payload['targetDeviceId'] = to;
    return payload;
  }
}
