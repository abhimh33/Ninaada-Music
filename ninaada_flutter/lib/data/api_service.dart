import 'package:flutter/foundation.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/data/network_manager.dart';

// ================================================================
//  API SERVICE — thin facade over NetworkManager
// ================================================================
//
//  All caching, dedup, concurrency, and persistence are handled by
//  NetworkManager.  This class only maps endpoints → typed models.
// ================================================================

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  final NetworkManager _net = NetworkManager();

  static const Duration _homeTtl = Duration(hours: 1);
  static const Duration _detailTtl = Duration(hours: 24);

  ApiService._internal();

  /// Cancel a specific request by key.
  void cancelRequest(String key) => _net.cancelRequest(key);

  /// Cancel all in-flight requests.
  void cancelAll() => _net.cancelAll();

  /// Clear all caches (memory + disk).
  Future<void> clearCache() => _net.clearCache();

  // ==================== HOME / BROWSE ====================

  Future<List<BrowseItem>> fetchTrending({String language = 'hindi'}) async {
    try {
      final data = await _net.get('/browse/trending',
          params: {'language': language},
          cacheKey: 'trending_$language', cacheTtl: _homeTtl, staleOk: true);
      if (data == null) return [];
      final list = data['data'];
      if (list is List) return list.map((e) => BrowseItem.fromJson(e)).toList();
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<BrowseItem>> fetchFeatured({String language = 'hindi'}) async {
    try {
      final data = await _net.get('/browse/featured',
          params: {'language': language},
          cacheKey: 'featured_$language', cacheTtl: _homeTtl, staleOk: true);
      if (data == null) return [];
      final list = data['data'];
      if (list is List) return list.map((e) => BrowseItem.fromJson(e)).toList();
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<BrowseItem>> fetchNewReleases() async {
    try {
      final data = await _net.get('/browse/new-releases',
          cacheKey: 'newReleases', cacheTtl: _homeTtl, staleOk: true);
      if (data == null) return [];
      final list = data['data'];
      if (list is List) return list.map((e) => BrowseItem.fromJson(e)).toList();
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<Song>> fetchTopSongs({String language = 'hindi', int limit = 20}) async {
    try {
      final data = await _net.get('/browse/top-songs',
          params: {'language': language, 'limit': limit},
          cacheKey: 'topSongs_${language}_$limit',
          cacheTtl: _homeTtl,
          staleOk: true);
      if (data == null) return [];
      final list = data['data'];
      if (list is List) return list.map((e) => Song.fromJson(e)).toList();
      return [];
    } catch (_) {
      return [];
    }
  }

  // ==================== SEARCH ====================

  /// Cancel any in-flight search request.
  void cancelSearch() => _net.cancelRequest('search');

  Future<Map<String, dynamic>> search(String query) async {
    // Guard: block empty/whitespace queries at API layer
    final q = query.trim();
    if (q.isEmpty || q.length < 3) return _emptySearch;
    try {
      debugPrint('=== SEARCH: calling _net.get for q="$q" ===');
      final data = await _net.get('/search/',
          params: {'query': q},
          cancelKey: 'search',
          cacheTtl: const Duration(hours: 1));
      if (data == null) {
        debugPrint('=== SEARCH: _net.get returned NULL (cancelled?) ===');
        return _emptySearch;
      }
      debugPrint('=== SEARCH: got response, type=${data.runtimeType} ===');
      final d = data['data'];
      if (d != null) {
        final songs = (d['songs'] as List?)?.map((e) => Song.fromJson(e)).toList() ?? <Song>[];
        final albums = (d['albums'] as List?)?.map((e) => BrowseItem.fromJson(e)).toList() ?? <BrowseItem>[];
        final artists = (d['artists'] as List?)?.map((e) => ArtistBrief.fromJson(e)).toList() ?? <ArtistBrief>[];
        debugPrint('=== SEARCH: parsed ${songs.length} songs, ${albums.length} albums, ${artists.length} artists ===');
        return {
          'songs': songs,
          'albums': albums,
          'artists': artists,
        };
      }
      if (data is List) {
        debugPrint('=== SEARCH: data is List (${data.length} items) ===');
        return {'songs': data.map((e) => Song.fromJson(e)).toList(), 'albums': <BrowseItem>[], 'artists': <ArtistBrief>[]};
      }
      debugPrint('=== SEARCH: no data field found, keys=${data is Map ? (data as Map).keys.toList() : "not-map"} ===');
      return _emptySearch;
    } catch (e) {
      debugPrint('=== SEARCH: EXCEPTION: $e ===');
      return _emptySearch;
    }
  }

  Future<List<Song>> searchSongs(String query, {int limit = 30}) async {
    final q = query.trim();
    if (q.isEmpty || q.length < 3) return [];
    try {
      final data = await _net.get('/song/',
          params: {'query': q, 'limit': limit},
          cancelKey: 'songSearch',
          cacheTtl: const Duration(hours: 1));
      if (data == null) return [];
      if (data is List) return data.map((e) => Song.fromJson(e)).toList();
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<Song>> searchSongsByFilter(String query, String filter) async {
    try {
      String path;
      if (filter == 'albums') {
        path = '/search/albums';
      } else if (filter == 'artists') {
        path = '/search/artists';
      } else {
        path = '/search/';
      }
      final data = await _net.get(path,
          params: {'query': query},
          cancelKey: 'filterSearch');
      if (data == null) return [];
      return [];
    } catch (_) {
      return [];
    }
  }

  // ==================== SONG DETAILS ====================

  /// Fetch lyrics for a song by ID.
  /// Returns raw lyrics string (may contain HTML or LRC timestamps).
  /// Returns null if lyrics are unavailable.
  Future<String?> fetchLyrics(String songId) async {
    if (songId.trim().isEmpty) return null;
    try {
      final data = await _net.get('/lyrics/',
          params: {'query': songId},
          cacheKey: 'lyrics_$songId',
          cacheTtl: const Duration(hours: 24));
      if (data == null) return null;
      if (data is Map) {
        final lyrics = data['lyrics'];
        if (lyrics is String && lyrics.isNotEmpty) return lyrics;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Song>> fetchSimilarSongs(String songId) async {
    try {
      final data = await _net.get('/song/similar/',
          params: {'id': songId},
          cacheKey: 'similar_$songId',
          cacheTtl: _detailTtl);
      if (data == null) return [];
      if (data is List) return data.map((e) => Song.fromJson(e)).toList();
      return [];
    } catch (_) {
      return [];
    }
  }

  // ==================== ARTIST ====================

  Future<ArtistDetail?> fetchArtist(String artistId) async {
    try {
      final data = await _net.get('/artist/',
          params: {'id': artistId},
          cacheKey: 'artist_$artistId',
          cacheTtl: _detailTtl);
      if (data == null) return null;
      final d = data['data'];
      if (d != null) {
        return ArtistDetail.fromJson(d);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ==================== ALBUM / PLAYLIST ====================

  Future<BrowseItem?> fetchAlbum(String id) async {
    // Guard: block empty IDs — prevents 400 Bad Request
    if (id.trim().isEmpty) return null;
    try {
      final data = await _net.get('/album/',
          params: {'query': id},
          cacheKey: 'album_$id',
          cacheTtl: _detailTtl);
      if (data == null || data['detail'] != null) return null;
      return BrowseItem.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<BrowseItem?> fetchPlaylist(String id) async {
    // Guard: block empty IDs — prevents 400 Bad Request
    if (id.trim().isEmpty) return null;
    try {
      final data = await _net.get('/playlist/',
          params: {'query': id},
          cacheKey: 'playlist_$id',
          cacheTtl: _detailTtl);
      if (data == null || data['detail'] != null) return null;
      // Normalize playlist format
      final json = Map<String, dynamic>.from(data);
      if (json['listname'] != null) {
        json['name'] = json['listname'] ?? json['name'];
        json['subtitle'] = json['firstname'] ?? '';
      }
      // Normalize listid → id for playlists
      if ((json['id'] == null || json['id'].toString().isEmpty) && json['listid'] != null) {
        json['id'] = json['listid'].toString();
      }
      return BrowseItem.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Auto-detect album vs playlist and fetch.
  Future<BrowseItem?> fetchAlbumOrPlaylist(String id, {bool isPlaylist = false}) async {
    if (isPlaylist) {
      final pl = await fetchPlaylist(id);
      if (pl != null) return pl;
      return fetchAlbum(id);
    } else {
      final al = await fetchAlbum(id);
      if (al != null) return al;
      return fetchPlaylist(id);
    }
  }

  static const Map<String, dynamic> _emptySearch = {
    'songs': <Song>[],
    'albums': <BrowseItem>[],
    'artists': <ArtistBrief>[],
  };
}
