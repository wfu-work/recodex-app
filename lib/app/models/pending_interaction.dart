class PendingInteraction {
  PendingInteraction.fromJson(Map<String, dynamic> json)
    : id = json['approvalId'] as String? ?? '',
      kind = json['kind'] as String? ?? 'desktop',
      method = json['method'] as String? ?? '',
      canRespond = json['canRespond'] == true,
      responding = json['responding'] == true,
      params = json['params'] is Map
          ? Map<String, dynamic>.from(json['params'] as Map)
          : <String, dynamic>{};

  final String id;
  final String kind;
  final String method;
  final bool canRespond;
  final bool responding;
  final Map<String, dynamic> params;
  String get threadId => params['threadId'] as String? ?? '';
  String? get turnId => params['turnId'] as String?;
  List<Map<String, dynamic>> get questions => [
    for (final item in params['questions'] is List ? params['questions'] : [])
      if (item is Map) Map<String, dynamic>.from(item),
  ];
  List<String> get decisions => params['availableDecisions'] is List
      ? (params['availableDecisions'] as List).whereType<String>().toList()
      : const ['accept', 'acceptForSession', 'decline', 'cancel'];
}
