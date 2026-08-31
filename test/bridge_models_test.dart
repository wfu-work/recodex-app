import 'package:flutter_test/flutter_test.dart';

import 'package:recodex/app/models/bridge_models.dart';

void main() {
  test('PairingProfile round-trips all connection credentials', () {
    const profile = PairingProfile(
      id: 'pairing-one',
      name: '开发机',
      baseUrl: 'wss://relay.example.com/v1/connect',
      spaceId: 'space-1',
      deviceName: '手机',
      deviceId: 'flutter-1',
      targetDeviceId: 'host-1',
      endpointType: 'app',
      deviceKey: 'private-seed',
      endpointPublicKey: 'public-key',
      pairingToken: 'connect-token',
      endpointGrant: 'endpoint-grant',
      tokenExpiresAt: 123,
      grantExpiresAt: 456,
      selectedWorkspaceName: 'recodex',
      selectedWorkspacePath: '/work/recodex',
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-02T00:00:00Z',
    );

    final restored = PairingProfile.fromJson(profile.toJson());

    expect(restored.id, profile.id);
    expect(restored.displayName, profile.name);
    expect(restored.baseUrl, profile.baseUrl);
    expect(restored.deviceKey, profile.deviceKey);
    expect(restored.pairingToken, profile.pairingToken);
    expect(restored.endpointGrant, profile.endpointGrant);
    expect(restored.selectedWorkspacePath, profile.selectedWorkspacePath);
    expect(restored.tokenExpiresAt, profile.tokenExpiresAt);
    expect(restored.isComplete, isTrue);
  });

  test('PairingProfile reports incomplete credentials', () {
    const profile = PairingProfile(
      id: 'draft',
      name: '',
      baseUrl: 'ws://127.0.0.1:8788/v1/connect',
      spaceId: '',
      deviceName: 'Flutter phone',
      deviceId: 'flutter-draft',
      targetDeviceId: '',
      endpointType: 'app',
      deviceKey: '',
      endpointPublicKey: '',
      pairingToken: '',
      endpointGrant: '',
      tokenExpiresAt: 0,
      grantExpiresAt: 0,
    );

    expect(profile.isComplete, isFalse);
    expect(profile.displayName, '未命名配对');
  });
}
