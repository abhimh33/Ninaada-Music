import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ninaada_music/data/models.dart';

/// Persists frequently-accessed media items in fast local storage.
/// Maintains a capped collection (max [_maxItems]) with ordered overwrite.
class SpeedDialService {
  static final SpeedDialService _instance = SpeedDialService._();
  factory SpeedDialService() => _instance;
  SpeedDialService._();

  static const int _maxItems = 12;
  static const String _boxKey = 'speedDialItems';

  Box? _box;

  Box get _settings {
    _box ??= Hive.box('settings');
    return _box!;
  }

  /// Load all pinned items, ordered by most recently pinned first.
  List<Song> loadAll() {
    try {
      final raw = _settings.get(_boxKey);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List;
      return list.map((e) => Song.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Pin [song] to speed dial. If already pinned, moves to front.
  /// If collection is at capacity, evicts the oldest (last) item.
  Future<void> pin(Song song) async {
    final items = loadAll();
    items.removeWhere((s) => s.id == song.id);
    items.insert(0, song);
    if (items.length > _maxItems) {
      items.removeLast();
    }
    await _settings.put(_boxKey, jsonEncode(items.map((s) => s.toJson()).toList()));
  }

  /// Unpin [songId] from speed dial.
  Future<void> unpin(String songId) async {
    final items = loadAll();
    items.removeWhere((s) => s.id == songId);
    await _settings.put(_boxKey, jsonEncode(items.map((s) => s.toJson()).toList()));
  }

  /// Check if a song is pinned.
  bool isPinned(String songId) => loadAll().any((s) => s.id == songId);
}
