/// Normalizes Codex FileChange items and unified diff snapshots into the
/// path-to-patch map used by the conversation and review views.
class TurnFileChanges {
  /// Resolve full paths first. Relative/absolute aliases must have matching
  /// path segments and a unique candidate; a shared basename is not enough.
  static String? resolvePath(Iterable<String> paths, String selectedPath) {
    String normalize(String value) => value.replaceAll('\\', '/').trim();
    bool absolute(String value) => value.startsWith('/') ||
        RegExp(r'^[a-zA-Z]:/').hasMatch(value);
    final selected = normalize(selectedPath);
    if (selected.isEmpty) return null;
    final candidates = paths.toSet();
    for (final candidate in candidates) {
      if (normalize(candidate) == selected) return candidate;
    }
    final matches = candidates.where((path) {
      final candidate = normalize(path);
      if (absolute(candidate) == absolute(selected)) return false;
      return absolute(selected)
          ? selected.endsWith('/$candidate')
          : candidate.endsWith('/$selected');
    }).toList();
    return matches.length == 1 ? matches.single : null;
  }

  static Map<String, String> fromItem(Map<String, dynamic> item) {
    final result = <String, String>{};
    void add(String path, Object? value) {
      final normalized = path.trim();
      if (normalized.isEmpty) return;
      final map = value is Map
          ? Map<String, dynamic>.from(value)
          : const <String, dynamic>{};
      final diff =
          (map['unified_diff'] ?? map['unifiedDiff'] ?? map['diff'] ?? '')
              .toString();
      result[normalized] = diff;
    }

    void visit(Object? raw) {
      if (raw is! Map) return;
      final map = Map<String, dynamic>.from(raw);
      final changes = map['changes'] ?? map['files'] ?? map['diffs'];
      if (changes is Map) {
        for (final entry in changes.entries) {
          add(entry.key.toString(), entry.value);
        }
      } else if (changes is List) {
        for (final entry in changes) {
          if (entry is Map) {
            final path =
                entry['path'] ??
                entry['file'] ??
                entry['filename'] ??
                entry['filePath'];
            if (path != null) add(path.toString(), entry);
          }
        }
      }
      final path =
          map['path'] ?? map['file'] ?? map['filename'] ?? map['filePath'];
      if (path != null &&
          (map.containsKey('unified_diff') ||
              map.containsKey('unifiedDiff') ||
              map.containsKey('diff'))) {
        add(path.toString(), map);
      }
      visit(map['item']);
      visit(map['data']);
    }

    visit(item);
    return result;
  }

  static Map<String, String> fromUnifiedDiff(String diff) {
    final result = <String, String>{};
    final chunks = diff.split(RegExp(r'(?=^diff --git )', multiLine: true));
    for (final chunk in chunks) {
      final header = RegExp(
        r'^diff --git a/(.*?) b/(.*?)$',
        multiLine: true,
      ).firstMatch(chunk);
      final path = header?.group(2);
      if (path != null && path.isNotEmpty) result[path] = chunk.trim();
    }
    return result;
  }

  static String numstat(Map<String, String> diffs) {
    return diffs.entries
        .map((entry) {
          var added = 0;
          var removed = 0;
          for (final line in entry.value.split('\n')) {
            if (line.startsWith('+++') || line.startsWith('---')) continue;
            if (line.startsWith('+')) added++;
            if (line.startsWith('-')) removed++;
          }
          return '$added\t$removed\t${entry.key}';
        })
        .join('\n');
  }

  static Map<String, dynamic> toJson(Map<String, String> diffs) => diffs;

  static Map<String, String> fromJson(Object? value) {
    if (value is! Map) return const {};
    return value.map(
      (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
    );
  }
}
