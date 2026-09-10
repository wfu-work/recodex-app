/// Cursor for the plugin's event journal, independent of transport receipts.
/// A restarted plugin has a new namespace even if its sequence has caught up.
class EventRecovery {
  String? streamId;
  int sequence = 0;
  bool _hasBaseline = false;
  final _retired = <String>{};

  bool isRetired(String? id) => id != null && _retired.contains(id);

  bool adopt(String? id) {
    if (id == null || id == streamId || isRetired(id)) return false;
    if (streamId != null) _retired.add(streamId!);
    if (_retired.length > 32) _retired.remove(_retired.first);
    streamId = id;
    sequence = 0;
    _hasBaseline = false;
    return true;
  }

  bool accept(int next) {
    if (next <= sequence || next != sequence + 1) return false;
    sequence = next;
    return true;
  }

  void snapshot(int baseline) {
    _hasBaseline = true;
    // Live events can overtake the snapshot request. Never rewind that cursor.
    if (baseline > sequence) sequence = baseline;
  }

  Map<String, dynamic> get request => {
    if (_hasBaseline || sequence > 0) 'lastSequence': sequence,
    if (streamId != null) 'eventStreamId': streamId,
  };

  void reset() {
    streamId = null;
    sequence = 0;
    _hasBaseline = false;
    _retired.clear();
  }
}
