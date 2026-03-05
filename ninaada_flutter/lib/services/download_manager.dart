import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ninaada_music/data/models.dart';

// ================================================================
//  DOWNLOAD MANAGER — Phase 9: Offline Download System
// ================================================================
//
//  Architecture:
//  ┌────────────────────────────────────────────────────────────┐
//  │  DownloadManager (Singleton Service)                       │
//  │                                                            │
//  │  Hive 'downloads' box — persistent state per song          │
//  │    key: songId                                             │
//  │    val: DownloadRecord (JSON)                               │
//  │         → status, localFilePath, localArtPath, progress    │
//  │                                                            │
//  │  Queue-based sequential downloader:                         │
//  │    _pendingQueue → FIFO                                    │
//  │    _processQueue() → picks next queued, downloads          │
//  │    Max parallel: 2 concurrent downloads                    │
//  │                                                            │
//  │  File layout:                                              │
//  │    {appDocDir}/ninaada_downloads/{songId}.mp3               │
//  │    {appDocDir}/ninaada_downloads/art/{songId}.jpg           │
//  └────────────────────────────────────────────────────────────┘
// ================================================================

// ══════════════════════════════════════════════════
//  DOWNLOAD STATUS ENUM
// ══════════════════════════════════════════════════

enum DownloadStatus { queued, downloading, completed, failed }

// ══════════════════════════════════════════════════
//  DOWNLOAD RECORD — persisted to Hive per song
// ══════════════════════════════════════════════════

class DownloadRecord {
  final String songId;
  final String songName;
  final DownloadStatus status;
  final double progress; // 0.0 – 1.0
  final String? localFilePath; // absolute path to MP3
  final String? localArtPath; // absolute path to album art JPG
  final String? error;
  final DateTime? queuedAt;
  final DateTime? completedAt;

  const DownloadRecord({
    required this.songId,
    required this.songName,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.localFilePath,
    this.localArtPath,
    this.error,
    this.queuedAt,
    this.completedAt,
  });

  DownloadRecord copyWith({
    DownloadStatus? status,
    double? progress,
    String? localFilePath,
    String? localArtPath,
    String? error,
    DateTime? completedAt,
  }) {
    return DownloadRecord(
      songId: songId,
      songName: songName,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      localFilePath: localFilePath ?? this.localFilePath,
      localArtPath: localArtPath ?? this.localArtPath,
      error: error,
      queuedAt: queuedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'songId': songId,
        'songName': songName,
        'status': status.index,
        'progress': progress,
        'localFilePath': localFilePath,
        'localArtPath': localArtPath,
        'error': error,
        'queuedAt': queuedAt?.millisecondsSinceEpoch,
        'completedAt': completedAt?.millisecondsSinceEpoch,
      };

  factory DownloadRecord.fromJson(Map<String, dynamic> json) {
    return DownloadRecord(
      songId: json['songId'] as String? ?? '',
      songName: json['songName'] as String? ?? '',
      status: DownloadStatus.values[(json['status'] as int?) ?? 0],
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      localFilePath: json['localFilePath'] as String?,
      localArtPath: json['localArtPath'] as String?,
      error: json['error'] as String?,
      queuedAt: json['queuedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['queuedAt'] as int)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['completedAt'] as int)
          : null,
    );
  }
}

// ══════════════════════════════════════════════════
//  DOWNLOAD MANAGER — Singleton Service
// ══════════════════════════════════════════════════

class DownloadManager {
  static final DownloadManager _instance = DownloadManager._();
  factory DownloadManager() => _instance;
  DownloadManager._();

  static const String _boxName = 'downloads';
  static const int _maxParallel = 2;

  Box? _box;
  String? _downloadDir;
  String? _artDir;
  final Dio _dio = Dio();

  /// In-memory cache of all records for fast lookups.
  final Map<String, DownloadRecord> _records = {};

  /// Active download cancel tokens.
  final Map<String, CancelToken> _cancelTokens = {};

  /// Number of currently active downloads.
  int _activeCount = 0;

  /// Pending download queue (songId → Song).
  final Map<String, Song> _pendingQueue = {};

  /// Broadcast stream of state changes for UI reactivity.
  final _stateController =
      StreamController<Map<String, DownloadRecord>>.broadcast();

  /// Fires a songId when a download completes successfully.
  /// PlayerNotifier listens to this for deterministic hot-swap.
  final _completedController = StreamController<String>.broadcast();

  /// Stream of completed download songIds (one-way event bridge).
  Stream<String> get downloadCompletedStream =>
      _completedController.stream;

  /// Stream of all download records (fires on every state change).
  Stream<Map<String, DownloadRecord>> get stateStream =>
      _stateController.stream;

  /// Current snapshot of all records.
  Map<String, DownloadRecord> get records => Map.unmodifiable(_records);

  /// Maximum download storage in bytes (2 GB).
  static const int _maxStorageBytes = 2 * 1024 * 1024 * 1024;

  // ── Legacy compatibility getters (used by existing UI) ──
  /// Stream alias matching old DownloadTask API.
  Stream<Map<String, DownloadRecord>> get tasksStream => stateStream;

  /// Snapshot alias matching old DownloadTask API.
  Map<String, DownloadRecord> get tasks => records;

  // ══════════════════════════════════════════════════
  //  INITIALIZATION
  // ══════════════════════════════════════════════════

  /// Initialize the download manager. Call once during app startup.
  Future<void> init() async {
    try {
      _box = await Hive.openBox(_boxName);

      // Resolve persistent download directory
      final appDir = await getApplicationDocumentsDirectory();
      _downloadDir = '${appDir.path}/ninaada_downloads';
      _artDir = '${appDir.path}/ninaada_downloads/art';

      // Create directories if they don't exist
      await Directory(_downloadDir!).create(recursive: true);
      await Directory(_artDir!).create(recursive: true);

      // Load all persisted records into memory
      for (final key in _box!.keys) {
        try {
          final raw = _box!.get(key);
          if (raw != null) {
            final record = DownloadRecord.fromJson(
              jsonDecode(raw as String) as Map<String, dynamic>,
            );
            // Validate completed downloads — if file missing, mark failed
            if (record.status == DownloadStatus.completed &&
                record.localFilePath != null) {
              if (!await File(record.localFilePath!).exists()) {
                final fixed = record.copyWith(
                  status: DownloadStatus.failed,
                  error: 'File missing after restart',
                );
                _records[key as String] = fixed;
                await _persistRecord(fixed);
                continue;
              }
            }
            // Reset "downloading" → "failed" (process died mid-download)
            if (record.status == DownloadStatus.downloading) {
              final reset = record.copyWith(
                  status: DownloadStatus.failed,
                  progress: 0.0,
                  error: 'Interrupted by app restart');
              _records[key as String] = reset;
              await _persistRecord(reset);
              continue;
            }
            _records[key as String] = record;
          }
        } catch (e) {
          debugPrint(
              '=== DOWNLOAD MGR: failed to load record $key: $e ===');
        }
      }

      // ── Clean up orphaned .tmp files from crashed downloads ──
      try {
        final dlDir = Directory(_downloadDir!);
        await for (final entity in dlDir.list()) {
          if (entity is File && entity.path.endsWith('.tmp')) {
            await entity.delete();
            debugPrint('=== DOWNLOAD MGR: cleaned orphan tmp: ${entity.path} ===');
          }
        }
      } catch (_) {}

      _emit();
      debugPrint(
        '=== DOWNLOAD MGR: initialized (${_records.length} records, '
        'dir=$_downloadDir) ===',
      );
    } catch (e) {
      debugPrint('=== DOWNLOAD MGR: init FAILED: $e ===');
    }
  }

  // ══════════════════════════════════════════════════
  //  PUBLIC API — ENQUEUE
  // ══════════════════════════════════════════════════

  /// Enqueue a single song for download.
  /// No-op if already completed or currently downloading.
  /// Refuses if storage threshold (2 GB) is exceeded.
  Future<void> download(Song song) async {
    if (song.mediaUrl.isEmpty) return;

    final existing = _records[song.id];
    if (existing != null &&
        (existing.status == DownloadStatus.completed ||
            existing.status == DownloadStatus.downloading)) {
      return;
    }

    // ── Storage guardrail: refuse if over 2 GB ──
    final used = await getStorageUsed();
    if (used >= _maxStorageBytes) {
      debugPrint('=== DOWNLOAD MGR: storage limit reached (${(used / 1024 / 1024).toStringAsFixed(0)} MB) ===');
      return;
    }

    final record = DownloadRecord(
      songId: song.id,
      songName: song.name,
      status: DownloadStatus.queued,
      queuedAt: DateTime.now(),
    );

    _records[song.id] = record;
    await _persistRecord(record);
    _pendingQueue[song.id] = song;
    _emit();

    // Kick the queue processor
    _processQueue();
  }

  /// Enqueue multiple songs for download (album / playlist).
  Future<void> downloadAll(List<Song> songs) async {
    for (final song in songs) {
      if (song.mediaUrl.isEmpty) continue;
      final existing = _records[song.id];
      if (existing != null &&
          (existing.status == DownloadStatus.completed ||
              existing.status == DownloadStatus.downloading)) {
        continue;
      }

      final record = DownloadRecord(
        songId: song.id,
        songName: song.name,
        status: DownloadStatus.queued,
        queuedAt: DateTime.now(),
      );
      _records[song.id] = record;
      await _persistRecord(record);
      _pendingQueue[song.id] = song;
    }
    _emit();
    _processQueue();
  }

  /// Retry a failed download.
  Future<void> retry(Song song) async {
    _records.remove(song.id);
    await _box?.delete(song.id);
    await download(song);
  }

  /// Cancel an in-progress or queued download.
  void cancel(String songId) {
    _cancelTokens[songId]?.cancel('User cancelled');
    _cancelTokens.remove(songId);
    _pendingQueue.remove(songId);
    _records.remove(songId);
    _box?.delete(songId);
    _emit();
  }

  /// Delete a completed download (remove files + record).
  Future<void> deleteDownload(String songId) async {
    final record = _records[songId];
    if (record != null) {
      // Delete audio file
      if (record.localFilePath != null) {
        try {
          final f = File(record.localFilePath!);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      // Delete art file
      if (record.localArtPath != null) {
        try {
          final f = File(record.localArtPath!);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
    _records.remove(songId);
    await _box?.delete(songId);
    _emit();
  }

  // ══════════════════════════════════════════════════
  //  LOOKUP
  // ══════════════════════════════════════════════════

  /// Get the download record for a song (null if never queued).
  DownloadRecord? getRecord(String songId) => _records[songId];

  /// Check if a song's download is complete.
  bool isDownloaded(String songId) =>
      _records[songId]?.status == DownloadStatus.completed;

  /// Get the local file path for a completed download, or null.
  String? getLocalPath(String songId) {
    final r = _records[songId];
    return r?.status == DownloadStatus.completed ? r?.localFilePath : null;
  }

  /// Get the local art path for a completed download, or null.
  String? getLocalArtPath(String songId) {
    final r = _records[songId];
    return r?.status == DownloadStatus.completed ? r?.localArtPath : null;
  }

  /// Count of completed downloads.
  int get completedCount => _records.values
      .where((r) => r.status == DownloadStatus.completed)
      .length;

  /// Total download storage in bytes (approximate).
  Future<int> getStorageUsed() async {
    int total = 0;
    for (final record in _records.values) {
      if (record.status == DownloadStatus.completed &&
          record.localFilePath != null) {
        try {
          final f = File(record.localFilePath!);
          if (await f.exists()) total += await f.length();
        } catch (_) {}
      }
    }
    return total;
  }

  // ══════════════════════════════════════════════════
  //  QUEUE PROCESSOR — max 2 parallel downloads
  // ══════════════════════════════════════════════════

  void _processQueue() {
    while (_activeCount < _maxParallel && _pendingQueue.isNotEmpty) {
      final songId = _pendingQueue.keys.first;
      final song = _pendingQueue.remove(songId)!;
      _activeCount++;
      _executeDownload(song);
    }
  }

  Future<void> _executeDownload(Song song) async {
    final cancelToken = CancelToken();
    _cancelTokens[song.id] = cancelToken;

    try {
      // ── STEP 1: Mark as downloading ──
      _records[song.id] = (_records[song.id] ?? DownloadRecord(
        songId: song.id,
        songName: song.name,
        queuedAt: DateTime.now(),
      )).copyWith(status: DownloadStatus.downloading, progress: 0.0);
      await _persistRecord(_records[song.id]!);
      _emit();

      if (_downloadDir == null) {
        throw Exception('Download directory not initialized');
      }

      final audioPath = '$_downloadDir/${song.id}.mp3';
      final tmpPath = '$_downloadDir/${song.id}.tmp';

      // ── STEP 2: Download MP3 audio to .tmp (crash-safe) ──
      debugPrint(
        '=== DOWNLOAD MGR: downloading "${song.name}" (${song.id}) ===',
      );

      await _dio.download(
        song.mediaUrl,
        tmpPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            // Audio download = 0% → 85% of total progress
            final p = (received / total * 0.85).clamp(0.0, 0.85);
            _records[song.id] = _records[song.id]!.copyWith(progress: p);
            _emit();
          }
        },
      );

      // ── Atomic rename: .tmp → .mp3 (crash-safe commit) ──
      await File(tmpPath).rename(audioPath);

      // ── STEP 3: Download album art ──
      String? artPath;
      if (song.image.isNotEmpty) {
        try {
          artPath = '$_artDir/${song.id}.jpg';
          await _dio.download(
            song.image,
            artPath,
            cancelToken: cancelToken,
          );
          _records[song.id] =
              _records[song.id]!.copyWith(progress: 0.95);
          _emit();
        } catch (e) {
          debugPrint(
            '=== DOWNLOAD MGR: art download failed for ${song.id}: $e ===',
          );
          artPath = null; // Art download is non-fatal
        }
      }

      // ── STEP 4: Update library with local path ──
      await _updateLibraryWithLocalPath(song, audioPath, artPath);

      // ── STEP 5: Mark as completed ──
      _records[song.id] = _records[song.id]!.copyWith(
        status: DownloadStatus.completed,
        progress: 1.0,
        localFilePath: audioPath,
        localArtPath: artPath,
        completedAt: DateTime.now(),
      );
      await _persistRecord(_records[song.id]!);
      _emit();

      debugPrint(
        '=== DOWNLOAD MGR: completed "${song.name}" '
        '(file=${File(audioPath).existsSync()}, art=${artPath != null}) ===',
      );

      // ── Emit completion event for hot-swap bridge ──
      if (!_completedController.isClosed) {
        _completedController.add(song.id);
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        debugPrint('=== DOWNLOAD MGR: cancelled ${song.id} ===');
        // Record already removed by cancel()
      } else {
        debugPrint(
            '=== DOWNLOAD MGR: network error ${song.id}: $e ===');
        _records[song.id] = (_records[song.id] ?? DownloadRecord(
          songId: song.id,
          songName: song.name,
        )).copyWith(
          status: DownloadStatus.failed,
          error: e.message ?? 'Network error',
        );
        await _persistRecord(_records[song.id]!);
        _emit();
      }
    } catch (e) {
      debugPrint('=== DOWNLOAD MGR: failed ${song.id}: $e ===');
      _records[song.id] = (_records[song.id] ?? DownloadRecord(
        songId: song.id,
        songName: song.name,
      )).copyWith(
        status: DownloadStatus.failed,
        error: e.toString(),
      );
      await _persistRecord(_records[song.id]!);
      _emit();
    } finally {
      _cancelTokens.remove(song.id);
      _activeCount--;
      // Process next item in queue
      _processQueue();
    }
  }

  // ══════════════════════════════════════════════════
  //  LIBRARY SYNC — populate downloadedSongs with local paths
  // ══════════════════════════════════════════════════

  Future<void> _updateLibraryWithLocalPath(
    Song song,
    String audioPath,
    String? artPath,
  ) async {
    try {
      final box = Hive.box('library');
      final existing = box.get('downloadedSongs');
      final List<Song> downloads = existing != null
          ? (jsonDecode(existing) as List)
              .map((e) => Song.fromJson(e as Map<String, dynamic>))
              .toList()
          : [];

      // Remove any existing entry for this song
      downloads.removeWhere((s) => s.id == song.id);

      // Add with localUri populated for _toAudioSource() routing
      downloads.add(song.copyWith(
        localUri: audioPath,
        downloadedAt: DateTime.now().toIso8601String(),
        image: artPath ?? song.image,
      ));

      await box.put(
        'downloadedSongs',
        jsonEncode(downloads.map((s) => s.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('=== DOWNLOAD MGR: library sync failed: $e ===');
    }
  }

  // ══════════════════════════════════════════════════
  //  PERSISTENCE
  // ══════════════════════════════════════════════════

  Future<void> _persistRecord(DownloadRecord record) async {
    try {
      await _box?.put(record.songId, jsonEncode(record.toJson()));
    } catch (e) {
      debugPrint('=== DOWNLOAD MGR: persist failed: $e ===');
    }
  }

  void _emit() {
    if (!_stateController.isClosed) {
      _stateController.add(Map.unmodifiable(_records));
    }
  }

  /// Release resources.
  void dispose() {
    _stateController.close();
    _completedController.close();
    _dio.close();
  }
}

// ══════════════════════════════════════════════════
//  DOWNLOAD STATE — Riverpod integration
// ══════════════════════════════════════════════════

class DownloadState {
  final Map<String, DownloadRecord> records;

  const DownloadState({this.records = const {}});

  DownloadState copyWith({Map<String, DownloadRecord>? records}) =>
      DownloadState(records: records ?? this.records);

  /// Number of currently active + queued downloads.
  int get pendingCount => records.values
      .where((r) =>
          r.status == DownloadStatus.queued ||
          r.status == DownloadStatus.downloading)
      .length;

  /// Number of completed downloads.
  int get completedCount =>
      records.values
          .where((r) => r.status == DownloadStatus.completed)
          .length;

  /// Number of failed downloads.
  int get failedCount =>
      records.values
          .where((r) => r.status == DownloadStatus.failed)
          .length;
}

class DownloadNotifier extends StateNotifier<DownloadState> {
  StreamSubscription? _sub;

  DownloadNotifier() : super(const DownloadState()) {
    _init();
  }

  void _init() {
    // Seed with current state
    state = DownloadState(records: DownloadManager().records);

    // Listen for changes from the singleton service
    _sub = DownloadManager().stateStream.listen((records) {
      if (mounted) {
        state = DownloadState(records: records);
      }
    });
  }

  /// Enqueue a single song for download.
  Future<void> download(Song song) => DownloadManager().download(song);

  /// Enqueue multiple songs (album / playlist).
  Future<void> downloadAll(List<Song> songs) =>
      DownloadManager().downloadAll(songs);

  /// Retry a failed download.
  Future<void> retry(Song song) => DownloadManager().retry(song);

  /// Cancel a download.
  void cancel(String songId) => DownloadManager().cancel(songId);

  /// Delete a completed download and remove file.
  Future<void> deleteDownload(String songId) =>
      DownloadManager().deleteDownload(songId);

  /// Check if a song is fully downloaded.
  bool isDownloaded(String songId) => DownloadManager().isDownloaded(songId);

  /// Get download record for a song.
  DownloadRecord? getRecord(String songId) =>
      DownloadManager().getRecord(songId);

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Riverpod provider for download state.
final downloadProvider =
    StateNotifierProvider<DownloadNotifier, DownloadState>(
  (ref) => DownloadNotifier(),
);
