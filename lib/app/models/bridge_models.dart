import 'dart:convert';

class WorkspaceInfo {
  const WorkspaceInfo({required this.name, required this.path});

  final String name;
  final String path;

  factory WorkspaceInfo.fromJson(Map<String, dynamic> json) {
    return WorkspaceInfo(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
    );
  }
}

class PairingInfo {
  const PairingInfo({
    required this.baseUrl,
    required this.token,
    required this.pairingUri,
  });

  final String baseUrl;
  final String token;
  final String pairingUri;

  factory PairingInfo.fromJson(Map<String, dynamic> json) {
    final baseUrl = json['baseUrl'] as String? ?? '';
    final token = json['token'] as String? ?? '';
    return PairingInfo(
      baseUrl: baseUrl,
      token: token,
      pairingUri:
          json['pairingUri'] as String? ??
          Uri(
            scheme: 'recodex',
            host: 'pair',
            queryParameters: {'baseUrl': baseUrl, 'token': token},
          ).toString(),
    );
  }

  static PairingInfo? tryParse(String raw) {
    final trimmed = raw.trim();
    try {
      if (trimmed.startsWith('{')) {
        return PairingInfo.fromJson(
          jsonDecode(trimmed) as Map<String, dynamic>,
        );
      }
      final uri = Uri.parse(trimmed);
      if (uri.scheme == 'recodex' && uri.host == 'pair') {
        final baseUrl = uri.queryParameters['baseUrl'] ?? '';
        final token = uri.queryParameters['token'] ?? '';
        if (baseUrl.isEmpty || token.isEmpty) return null;
        return PairingInfo(baseUrl: baseUrl, token: token, pairingUri: trimmed);
      }
      if ((uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.path.endsWith('/pairing')) {
        final origin = '${uri.scheme}://${uri.authority}';
        return PairingInfo(baseUrl: origin, token: '', pairingUri: trimmed);
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.name,
    required this.lastSeen,
  });

  final String id;
  final String name;
  final String lastSeen;

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Device',
      lastSeen: json['lastSeen'] as String? ?? '',
    );
  }
}

class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.workspace,
    required this.prompt,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String workspace;
  final String prompt;
  final String status;
  final String createdAt;
  final String updatedAt;

  factory SessionRecord.fromJson(Map<String, dynamic> json) {
    return SessionRecord(
      id: json['id'] as String? ?? '',
      workspace: json['workspace'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      status: json['status'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }

  DateTime get updatedAtDate =>
      DateTime.tryParse(updatedAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
}

class SessionEvent {
  const SessionEvent({required this.kind, required this.text, this.time});

  final String kind;
  final String text;
  final DateTime? time;

  factory SessionEvent.fromJson(Map<String, dynamic> json) {
    return SessionEvent(
      kind: json['kind'] as String? ?? 'event',
      text: json['text'] as String? ?? json['raw'] as String? ?? '',
      time: DateTime.tryParse(json['time'] as String? ?? ''),
    );
  }
}

class GitSnapshot {
  const GitSnapshot({
    required this.branch,
    required this.status,
    required this.stat,
    required this.numstat,
    required this.diff,
    required this.log,
  });

  final String branch;
  final String status;
  final String stat;
  final String numstat;
  final String diff;
  final String log;

  factory GitSnapshot.fromJson(Map<String, dynamic> json) {
    return GitSnapshot(
      branch: json['branch'] as String? ?? '',
      status: json['status'] as String? ?? '',
      stat: json['stat'] as String? ?? '',
      numstat: json['numstat'] as String? ?? '',
      diff: json['diff'] as String? ?? '',
      log: json['log'] as String? ?? '',
    );
  }
}

class ComposerContext {
  const ComposerContext({
    required this.transport,
    required this.model,
    required this.models,
    required this.reasoningEffort,
    required this.reasoningEfforts,
    required this.approvalPolicy,
    required this.requireConfirmGitWrite,
    required this.branch,
    required this.bridgeVersion,
    required this.codexBinary,
    required this.codexVersion,
    required this.apiKeyConfigured,
  });

  final String transport;
  final String model;
  final List<String> models;
  final String reasoningEffort;
  final List<String> reasoningEfforts;
  final String approvalPolicy;
  final bool requireConfirmGitWrite;
  final String branch;
  final String bridgeVersion;
  final String codexBinary;
  final String codexVersion;
  final bool apiKeyConfigured;

  ComposerContext copyWith({
    String? transport,
    String? model,
    List<String>? models,
    String? reasoningEffort,
    List<String>? reasoningEfforts,
    String? approvalPolicy,
    bool? requireConfirmGitWrite,
    String? branch,
    String? bridgeVersion,
    String? codexBinary,
    String? codexVersion,
    bool? apiKeyConfigured,
  }) {
    return ComposerContext(
      transport: transport ?? this.transport,
      model: model ?? this.model,
      models: models ?? this.models,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      reasoningEfforts: reasoningEfforts ?? this.reasoningEfforts,
      approvalPolicy: approvalPolicy ?? this.approvalPolicy,
      requireConfirmGitWrite:
          requireConfirmGitWrite ?? this.requireConfirmGitWrite,
      branch: branch ?? this.branch,
      bridgeVersion: bridgeVersion ?? this.bridgeVersion,
      codexBinary: codexBinary ?? this.codexBinary,
      codexVersion: codexVersion ?? this.codexVersion,
      apiKeyConfigured: apiKeyConfigured ?? this.apiKeyConfigured,
    );
  }

  factory ComposerContext.fromJson(Map<String, dynamic> json) {
    return ComposerContext(
      transport: json['transport'] as String? ?? 'Local',
      model: json['model'] as String? ?? 'gpt-5.5',
      models: ((json['models'] as List?) ?? const ['gpt-5.5'])
          .whereType<String>()
          .toList(),
      reasoningEffort: json['reasoningEffort'] as String? ?? 'medium',
      reasoningEfforts:
          ((json['reasoningEfforts'] as List?) ??
                  const ['low', 'medium', 'high', 'xhigh'])
              .whereType<String>()
              .toList(),
      approvalPolicy: json['approvalPolicy'] as String? ?? 'on-request',
      requireConfirmGitWrite: json['requireConfirmGitWrite'] as bool? ?? true,
      branch: json['branch'] as String? ?? '',
      bridgeVersion:
          json['bridgeVersion'] as String? ?? json['version'] as String? ?? '',
      codexBinary: json['codexBinary'] as String? ?? 'codex',
      codexVersion: json['codexVersion'] as String? ?? '',
      apiKeyConfigured: json['apiKeyConfigured'] as bool? ?? false,
    );
  }

  static const fallback = ComposerContext(
    transport: 'Local',
    model: 'gpt-5.5',
    models: ['gpt-5.5', 'gpt-5.4', 'gpt-5.4-mini', 'gpt-5.3-codex', 'gpt-5.2'],
    reasoningEffort: 'medium',
    reasoningEfforts: ['low', 'medium', 'high', 'xhigh'],
    approvalPolicy: 'on-request',
    requireConfirmGitWrite: true,
    branch: '',
    bridgeVersion: '',
    codexBinary: 'codex',
    codexVersion: '',
    apiKeyConfigured: false,
  );
}
