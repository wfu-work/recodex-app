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
  const SessionEvent({required this.kind, required this.text});

  final String kind;
  final String text;

  factory SessionEvent.fromJson(Map<String, dynamic> json) {
    return SessionEvent(
      kind: json['kind'] as String? ?? 'event',
      text: json['text'] as String? ?? json['raw'] as String? ?? '',
    );
  }
}

class GitSnapshot {
  const GitSnapshot({
    required this.branch,
    required this.status,
    required this.stat,
    required this.diff,
    required this.log,
  });

  final String branch;
  final String status;
  final String stat;
  final String diff;
  final String log;

  factory GitSnapshot.fromJson(Map<String, dynamic> json) {
    return GitSnapshot(
      branch: json['branch'] as String? ?? '',
      status: json['status'] as String? ?? '',
      stat: json['stat'] as String? ?? '',
      diff: json['diff'] as String? ?? '',
      log: json['log'] as String? ?? '',
    );
  }
}
