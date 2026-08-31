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

  test('SessionRecord exposes a useful sidebar title and running state', () {
    const record = SessionRecord(
      id: 'thread-1',
      workspace: '/work/recodex',
      prompt: '修复侧边栏任务读取',
      status: 'active',
      createdAt: '1700000000',
      updatedAt: '1700000100',
    );

    expect(record.displayTitle, '修复侧边栏任务读取');
    expect(record.isRunning, isTrue);
    expect(record.updatedAtDate.year, 2023);
  });

  test('ComposerContext keeps remote model ids and display names separate', () {
    final context = ComposerContext.fromJson({
      'model': 'gpt-remote',
      'models': [
        {
          'model': 'gpt-remote',
          'id': 'catalog-entry',
          'displayName': 'GPT Remote',
          'hidden': false,
        },
        {'model': 'gpt-hidden', 'displayName': 'Hidden model', 'hidden': true},
        'legacy-model',
      ],
    });

    expect(context.models, ['gpt-remote', 'legacy-model']);
    expect(context.modelLabel('gpt-remote'), 'GPT Remote');
    expect(context.modelLabel('legacy-model'), 'legacy-model');
    expect(context.model, 'gpt-remote');
  });

  test('ComposerContext fallback has no fabricated remote models', () {
    expect(ComposerContext.fallback.models, isEmpty);
    expect(ComposerContext.fallback.model, isEmpty);
  });
}
