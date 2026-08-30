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
  const SessionEvent({
    required this.kind,
    required this.text,
    this.time,
    this.usage,
    this.attachments = const [],
  });

  final String kind;
  final String text;
  final DateTime? time;
  final TokenUsage? usage;
  final List<EventAttachment> attachments;

  factory SessionEvent.fromJson(Map<String, dynamic> json) {
    return SessionEvent(
      kind: json['kind'] as String? ?? 'event',
      text: json['text'] as String? ?? json['raw'] as String? ?? '',
      time: DateTime.tryParse(json['time'] as String? ?? ''),
      usage: json['usage'] is Map
          ? TokenUsage.fromJson((json['usage'] as Map).cast<String, dynamic>())
          : null,
      attachments: ((json['attachments'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => EventAttachment.fromJson(item.cast<String, dynamic>()))
          .toList(),
    );
  }
}

class EventAttachment {
  const EventAttachment({
    required this.type,
    required this.mime,
    required this.dataUrl,
  });

  final String type;
  final String mime;
  final String dataUrl;

  factory EventAttachment.fromJson(Map<String, dynamic> json) {
    return EventAttachment(
      type: json['type'] as String? ?? '',
      mime: json['mime'] as String? ?? '',
      dataUrl: json['dataUrl'] as String? ?? json['data_url'] as String? ?? '',
    );
  }
}

class TokenUsage {
  const TokenUsage({
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
  });

  final int inputTokens;
  final int outputTokens;
  final int totalTokens;

  factory TokenUsage.fromJson(Map<String, dynamic> json) {
    return TokenUsage(
      inputTokens: _jsonInt(json['inputTokens'] ?? json['input_tokens']),
      outputTokens: _jsonInt(json['outputTokens'] ?? json['output_tokens']),
      totalTokens: _jsonInt(json['totalTokens'] ?? json['total_tokens']),
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
    required this.usage,
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
  final UsageOverview usage;

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
    UsageOverview? usage,
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
      usage: usage ?? this.usage,
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
      usage: json['usage'] is Map
          ? UsageOverview.fromJson(
              (json['usage'] as Map).cast<String, dynamic>(),
            )
          : UsageOverview.empty,
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
    usage: UsageOverview.empty,
  );
}

class UsageOverview {
  const UsageOverview({
    required this.todayTokens,
    required this.monthTokens,
    required this.todayCost,
    required this.monthCost,
    required this.lastUpdated,
    required this.canReadUsage,
    required this.rateConfigured,
  });

  final int todayTokens;
  final int monthTokens;
  final double todayCost;
  final double monthCost;
  final DateTime? lastUpdated;
  final bool canReadUsage;
  final bool rateConfigured;

  factory UsageOverview.fromJson(Map<String, dynamic> json) {
    return UsageOverview(
      todayTokens: _jsonInt(json['todayTokens']),
      monthTokens: _jsonInt(json['monthTokens']),
      todayCost: _jsonDouble(json['todayCost']),
      monthCost: _jsonDouble(json['monthCost']),
      lastUpdated: DateTime.tryParse(json['lastUpdated'] as String? ?? ''),
      canReadUsage: json['canReadUsage'] as bool? ?? false,
      rateConfigured: json['rateConfigured'] as bool? ?? false,
    );
  }

  static const empty = UsageOverview(
    todayTokens: 0,
    monthTokens: 0,
    todayCost: 0,
    monthCost: 0,
    lastUpdated: null,
    canReadUsage: false,
    rateConfigured: false,
  );
}

int _jsonInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _jsonDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
