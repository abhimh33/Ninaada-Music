import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/app_keys.dart';
import 'package:ninaada_music/core/helpers.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/data/api_service.dart';
import 'package:ninaada_music/providers/app_providers.dart';
import 'package:ninaada_music/providers/sleep_alarm_provider.dart';
import 'package:ninaada_music/widgets/sleep_timer_modal.dart';
import 'package:ninaada_music/widgets/alarm_setup_modal.dart';
import 'package:ninaada_music/services/download_manager.dart';
import 'package:ninaada_music/services/speed_dial_service.dart';
import 'package:ninaada_music/widgets/queue_bottom_sheet.dart';
import 'package:ninaada_music/screens/equalizer_screen.dart';
import 'package:share_plus/share_plus.dart';

// ================================================================
//  MEDIA ENTITY — unified wrapper for Song / BrowseItem / Playlist
// ================================================================

enum MediaEntityType { song, album, playlist, folder }

class MediaEntity {
  final MediaEntityType type;
  final Song? song;
  final BrowseItem? browseItem;
  final PlaylistModel? playlist;
  final List<Song>? songs; // for folder / playlist context

  const MediaEntity._({
    required this.type,
    this.song,
    this.browseItem,
    this.playlist,
    this.songs,
  });

  factory MediaEntity.fromSong(Song s) => MediaEntity._(type: MediaEntityType.song, song: s);
  factory MediaEntity.fromAlbum(BrowseItem b) => MediaEntity._(type: MediaEntityType.album, browseItem: b, songs: b.songs);
  factory MediaEntity.fromPlaylist(PlaylistModel p) => MediaEntity._(type: MediaEntityType.playlist, playlist: p, songs: p.songs);
  factory MediaEntity.fromFolder(String name, List<Song> songs) =>
      MediaEntity._(type: MediaEntityType.folder, songs: songs);

  String get id => song?.id ?? browseItem?.id ?? playlist?.id ?? '';
  String get name => song?.name ?? browseItem?.name ?? playlist?.name ?? '';
  String get image => song?.image ?? browseItem?.image ?? '';
  String get subtitle => song?.artist ?? browseItem?.subtitle ?? '${playlist?.songs.length ?? 0} songs';
}

// ================================================================
//  ACTION DEFINITIONS — strict order from spec
// ================================================================

enum MediaAction {
  playNext,
  saveToPlaylist,
  share,
  startMix,
  addToQueue,
  saveToLibrary,
  download,
  goToAlbum,
  viewSongCredits,
  pinToSpeedDial,
  dismissQueue,
  viewQueue,
  sleepTimer,
  alarm,
  equalizer,
}

class _ActionDef {
  final MediaAction action;
  final String label;
  final IconData icon;
  final bool Function(MediaEntity entity, WidgetRef ref)? showWhen;

  const _ActionDef({
    required this.action,
    required this.label,
    required this.icon,
    this.showWhen,
  });
}

/// Ordered action list — strict order per specification.
/// "Go to Artist", "Go to Album", and "Report" are explicitly excluded.
final List<_ActionDef> _actionDefs = [
  _ActionDef(
    action: MediaAction.playNext,
    label: 'Play Next',
    icon: Icons.playlist_play_rounded,
    showWhen: (e, _) => e.song != null,
  ),
  _ActionDef(
    action: MediaAction.saveToPlaylist,
    label: 'Save to Playlist',
    icon: Icons.playlist_add_rounded,
    showWhen: (e, _) => e.song != null,
  ),
  const _ActionDef(
    action: MediaAction.share,
    label: 'Share',
    icon: Icons.share_outlined,
  ),
  _ActionDef(
    action: MediaAction.startMix,
    label: 'Start Mix',
    icon: Icons.auto_awesome_rounded,
    showWhen: (e, _) => e.song != null,
  ),
  _ActionDef(
    action: MediaAction.addToQueue,
    label: 'Add to Queue',
    icon: Icons.queue_music_rounded,
    showWhen: (e, _) => e.song != null,
  ),
  _ActionDef(
    action: MediaAction.dismissQueue,
    label: 'Dismiss Queue',
    icon: Icons.playlist_remove_rounded,
    showWhen: (_, ref) => ref.read(playerProvider).queue.isNotEmpty,
  ),
  _ActionDef(
    action: MediaAction.viewQueue,
    label: 'View Queue',
    icon: Icons.queue_music_rounded,
    showWhen: (_, ref) => ref.read(playerProvider).queue.isNotEmpty,
  ),
  const _ActionDef(
    action: MediaAction.saveToLibrary,
    label: 'Like Song',
    icon: Icons.favorite_border_rounded,
  ),
  _ActionDef(
    action: MediaAction.download,
    label: 'Download',
    icon: Icons.arrow_circle_down_outlined,
    showWhen: (e, _) => e.song != null,
  ),
  _ActionDef(
    action: MediaAction.pinToSpeedDial,
    label: 'Pin to Speed Dial',
    icon: Icons.push_pin_outlined,
    showWhen: (e, _) => e.song != null,
  ),
  _ActionDef(
    action: MediaAction.viewSongCredits,
    label: 'View Song Credits',
    icon: Icons.info_outline_rounded,
    showWhen: (e, _) => e.song != null,
  ),
  const _ActionDef(
    action: MediaAction.sleepTimer,
    label: 'Sleep Timer',
    icon: Icons.timer_outlined,
  ),
  const _ActionDef(
    action: MediaAction.alarm,
    label: 'Alarm',
    icon: Icons.alarm,
  ),
  const _ActionDef(
    action: MediaAction.equalizer,
    label: 'Equalizer',
    icon: Icons.equalizer_rounded,
  ),
];

// ================================================================
//  CENTRALIZED ACTION EXECUTOR — single handler for all actions
// ================================================================

/// Debounce guard to prevent rapid repeated taps.
DateTime _lastActionTime = DateTime(2000);

Future<void> executeMediaAction({
  required MediaAction action,
  required MediaEntity entity,
  required WidgetRef ref,
}) async {
  // Debounce: ignore taps within 300ms of last action
  final now = DateTime.now();
  if (now.difference(_lastActionTime).inMilliseconds < 300) return;
  _lastActionTime = now;

  final player = ref.read(playerProvider.notifier);
  final library = ref.read(libraryProvider.notifier);
  final nav = ref.read(navigationProvider.notifier);

  switch (action) {
    case MediaAction.playNext:
      await _unwrapAndInsert(entity: entity, player: player, mode: _QueueInsertMode.next);
      break;

    case MediaAction.saveToPlaylist:
      if (entity.song != null) {
        showPlaylistPicker(ref, entity.song!);
      }
      break;

    case MediaAction.share:
      Share.share('${entity.name} — Ninaada Music');
      break;

    case MediaAction.startMix:
      if (entity.song != null) {
        _showSnack('Starting mix from ${entity.song!.name}...');
        await player.startMix(entity.song!);
      }
      break;

    case MediaAction.addToQueue:
      await _unwrapAndInsert(entity: entity, player: player, mode: _QueueInsertMode.end);
      break;

    case MediaAction.saveToLibrary:
      if (entity.song != null) {
        await library.toggleLike(entity.song!);
        final liked = library.isLiked(entity.song!.id);
        _showSnack(liked ? 'Saved to library' : 'Removed from library');
      }
      break;

    case MediaAction.download:
      if (entity.song != null) {
        _showSnack('Downloading ${entity.song!.name}...');
        await DownloadManager().download(entity.song!);
        await library.loadAll();
        _showSnack('Download complete');
      }
      break;

    case MediaAction.goToAlbum:
      if (entity.song != null) {
        nav.setSubView({
          'type': 'album',
          'id': entity.song!.album,
        });
      }
      break;

    case MediaAction.viewSongCredits:
      if (entity.song != null) {
        nav.setSubView({
          'type': 'credits',
          'data': entity.song!.toJson(),
        });
      }
      break;

    case MediaAction.pinToSpeedDial:
      if (entity.song != null) {
        final svc = SpeedDialService();
        if (svc.isPinned(entity.song!.id)) {
          await svc.unpin(entity.song!.id);
          _showSnack('Unpinned from Speed Dial');
        } else {
          await svc.pin(entity.song!);
          _showSnack('Pinned to Speed Dial');
        }
      }
      break;

    case MediaAction.dismissQueue:
      player.dismissQueue();
      _showSnack('Queue dismissed');
      break;

    case MediaAction.viewQueue:
      final ctx = navigatorKey.currentContext;
      if (ctx != null) showQueueBottomSheet(ctx);
      break;

    case MediaAction.sleepTimer:
      _showSleepTimerPicker(ref);
      break;

    case MediaAction.alarm:
      final ctx = navigatorKey.currentContext;
      if (ctx != null) showAlarmSetupModal(ctx);
      break;

    case MediaAction.equalizer:
      final ctx = navigatorKey.currentContext;
      if (ctx != null) showEqualizerModal(ctx);
      break;
  }
}

// ================================================================
//  COLLECTION UNWRAPPING — resolves Album/Playlist → List<Song>
// ================================================================

enum _QueueInsertMode { next, end }

/// Resolves the [entity] to its child songs and inserts them into the queue.
///
/// - **Song**: Immediate single-song insert (no network).
/// - **Album/Playlist with pre-loaded songs**: Uses local data.
/// - **Album/Playlist without songs**: Fetches from backend, then inserts.
///
/// Deduplication is handled by the batch methods in QueueManager /
/// NinaadaAudioHandler — no duplicate `song.id` will survive.
Future<void> _unwrapAndInsert({
  required MediaEntity entity,
  required PlayerNotifier player,
  required _QueueInsertMode mode,
}) async {
  // ── Case 1: Single song ──
  if (entity.type == MediaEntityType.song && entity.song != null) {
    if (mode == _QueueInsertMode.next) {
      player.insertNext(entity.song!);
      _showSnack('${entity.song!.name} will play next');
    } else {
      player.addToQueue(entity.song!);
      _showSnack('Added to queue');
    }
    return;
  }

  // ── Case 2: Collection (Album / Playlist / Folder) ──
  List<Song> songs = entity.songs ?? [];

  // If songs are already populated locally, use them directly.
  // Otherwise, fetch from the API.
  if (songs.isEmpty) {
    final id = entity.id;
    if (id.isEmpty) {
      _showSnack('Cannot resolve songs — no ID available');
      return;
    }

    _showSnack('Fetching songs…');

    try {
      final api = ApiService();
      BrowseItem? result;

      if (entity.type == MediaEntityType.playlist) {
        result = await api.fetchPlaylist(id);
      } else if (entity.type == MediaEntityType.album) {
        result = await api.fetchAlbum(id);
      } else {
        // Fallback: try auto-detect
        result = await api.fetchAlbumOrPlaylist(id);
      }

      songs = result?.songs ?? [];
    } catch (e) {
      debugPrint('=== UNWRAP ERROR: $e ===');
      _showSnack('Failed to fetch songs');
      return;
    }
  }

  if (songs.isEmpty) {
    _showSnack('No songs found in ${entity.name}');
    return;
  }

  // ── Insert batch ──
  if (mode == _QueueInsertMode.next) {
    await player.insertAllNext(songs);
    _showSnack('${songs.length} songs will play next');
  } else {
    await player.addAllToQueue(songs);
    _showSnack('Added ${songs.length} songs to queue');
  }
}

/// Show a snackbar using the global ScaffoldMessengerKey — survives bottom sheet pops.
void _showSnack(String msg) {
  final messenger = scaffoldMessengerKey.currentState;
  if (messenger == null) return;
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13)),
      backgroundColor: NinaadaColors.surface,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
      duration: const Duration(seconds: 2),
    ),
  );
}

// ================================================================
//  BOTTOM SHEET UI — the action menu itself
// ================================================================

/// Show the three-dots action sheet for any media entity.
/// This is the single entry point used across the entire app.
void showMediaActionSheet(BuildContext context, WidgetRef ref, MediaEntity entity) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _MediaActionSheet(entity: entity, parentRef: ref),
  );
}

/// Convenience — show action sheet for a [Song].
void showSongActionSheet(BuildContext context, WidgetRef ref, Song song) {
  showMediaActionSheet(context, ref, MediaEntity.fromSong(song));
}

/// Show the action sheet without requiring a WidgetRef.
/// Used by UniversalContextMenu.showSheet() from non-Consumer contexts.
void showMediaActionSheetDirect(BuildContext context, MediaEntity entity) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => MediaActionSheetContent(entity: entity),
  );
}

/// Public action sheet content widget.
/// Can be used directly inside a showModalBottomSheet builder
/// when no external WidgetRef is available (the widget obtains
/// its own ref via ConsumerWidget).
class MediaActionSheetContent extends ConsumerWidget {
  final MediaEntity entity;
  const MediaActionSheetContent({super.key, required this.entity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final sleepTimer = ref.watch(sleepAlarmProvider);
    final isLiked = entity.song != null && library.likedSongs.any((s) => s.id == entity.song!.id);
    final isDled = entity.song != null && library.downloadedSongs.any((s) => s.id == entity.song!.id);
    final isPinned = entity.song != null && SpeedDialService().isPinned(entity.song!.id);

    // Filter actions based on entity type and state
    final visible = _actionDefs.where((def) {
      if (def.showWhen != null && !def.showWhen!(entity, ref)) return false;
      return true;
    }).toList();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF141824).withOpacity(0.78),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Entity header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: safeImageUrl(entity.image),
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 48,
                      height: 48,
                      color: NinaadaColors.surfaceLight,
                      child: const Icon(Icons.music_note, color: Color(0xFF666666), size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entity.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entity.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Divider
          Container(height: 1, color: Colors.white.withOpacity(0.06)),

          // Action list
          Flexible(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final def = visible[index];
                // Dynamic icon & label overrides based on state
                IconData icon = def.icon;
                String label = def.label;
                Color iconColor = Colors.white.withOpacity(0.7);

                if (def.action == MediaAction.saveToLibrary && isLiked) {
                  icon = Icons.favorite_rounded;
                  label = 'Remove from Liked';
                  iconColor = NinaadaColors.liked;
                }
                if (def.action == MediaAction.download && isDled) {
                  icon = Icons.check_circle_rounded;
                  label = 'Downloaded';
                  iconColor = NinaadaColors.primary;
                }
                if (def.action == MediaAction.pinToSpeedDial && isPinned) {
                  icon = Icons.push_pin_rounded;
                  label = 'Unpin from Speed Dial';
                  iconColor = NinaadaColors.primary;
                }
                if (def.action == MediaAction.sleepTimer && sleepTimer.sleepActive) {
                  label = 'Sleep Timer (${fmt(sleepTimer.sleepRemaining)})';
                  iconColor = NinaadaColors.primaryLight;
                }

                return _ActionTile(
                  icon: icon,
                  label: label,
                  iconColor: iconColor,
                  onTap: () async {
                    Navigator.pop(context); // Close sheet
                    // Small delay so the pop animation completes before action
                    await Future.delayed(const Duration(milliseconds: 50));
                    await executeMediaAction(
                      action: def.action,
                      entity: entity,
                      ref: ref,
                    );
                  },
                );
              },
            ),
          ),

          // Bottom safe area padding
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),       // Column
      ),       // Container
      ),       // BackdropFilter
    );         // ClipRRect
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: NinaadaColors.primary.withOpacity(0.08),
        highlightColor: Colors.white.withOpacity(0.03),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          child: Row(
            children: [
              Icon(icon, size: 22, color: iconColor),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: Colors.white.withOpacity(0.15)),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
//  PLAYLIST PICKER — for "Save to Playlist"
// ================================================================

void showPlaylistPicker(WidgetRef ref, Song song) {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return;
  showModalBottomSheet(
    context: ctx,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _PlaylistPickerSheet(song: song, parentRef: ref),
  );
}

class _PlaylistPickerSheet extends ConsumerStatefulWidget {
  final Song song;
  final WidgetRef parentRef;
  const _PlaylistPickerSheet({required this.song, required this.parentRef});

  @override
  ConsumerState<_PlaylistPickerSheet> createState() => _PlaylistPickerSheetState();
}

class _PlaylistPickerSheetState extends ConsumerState<_PlaylistPickerSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(libraryProvider).playlists;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
      decoration: BoxDecoration(
        color: const Color(0xFF141824).withOpacity(0.78),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text(
            'Save to Playlist',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          // Create new playlist row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'New playlist...',
                      hintStyle: const TextStyle(color: Color(0xFF666666)),
                      filled: true,
                      fillColor: NinaadaColors.surfaceLight,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: NinaadaColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: NinaadaColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: NinaadaColors.primary),
                      ),
                    ),
                    onSubmitted: (_) => _createAndAdd(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _createAndAdd,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: NinaadaColors.surfaceLight,
                      border: Border.all(color: NinaadaColors.border),
                    ),
                    child: const Icon(Icons.add, size: 18, color: Color(0xFF888888)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Playlist list
          Flexible(
            child: playlists.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No playlists yet', style: TextStyle(color: Color(0xFF888888))),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final pl = playlists[index];
                      final alreadyIn = pl.songs.any((s) => s.id == widget.song.id);
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: alreadyIn
                              ? null
                              : () async {
                                  await ref.read(libraryProvider.notifier).addToPlaylist(widget.song, pl.id);
                                  if (context.mounted) Navigator.pop(context);
                                  _showSnack('Added to ${pl.name}');
                                },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: const Color(0xFF121826),
                                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                                  ),
                                  child: const Icon(Icons.library_music, size: 18, color: Colors.white),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(pl.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                                      Text('${pl.songs.length} songs', style: const TextStyle(color: Color(0xFF888888), fontSize: 11)),
                                    ],
                                  ),
                                ),
                                if (alreadyIn)
                                  const Icon(Icons.check_circle, size: 18, color: NinaadaColors.primary),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),       // Column
      ),       // Container
      ),       // BackdropFilter
    );         // ClipRRect
  }

  void _createAndAdd() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    ref.read(libraryProvider.notifier).createPlaylist(name);
    _controller.clear();
    // Auto-add to the newly created playlist after a tick
    Future.microtask(() {
      final playlists = ref.read(libraryProvider).playlists;
      if (playlists.isNotEmpty) {
        ref.read(libraryProvider.notifier).addToPlaylist(widget.song, playlists.last.id);
        if (mounted) Navigator.pop(context);
        _showSnack('Created "$name" & added song');
      }
    });
  }
}

// ================================================================
//  SLEEP TIMER PICKER — delegates to shared modal
// ================================================================

void _showSleepTimerPicker(WidgetRef ref) {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return;
  showSleepTimerModal(ctx);
}

// ================================================================
//  OVERFLOW ICON WIDGET — inject into any row/card/grid
// ================================================================

/// A reusable three-dot overflow icon that opens the media action sheet.
/// Place this anywhere a song, album, or playlist item is displayed.
/// Private wrapper that delegates to the public content widget.
/// Kept for backward-compatibility with showMediaActionSheet().
class _MediaActionSheet extends ConsumerWidget {
  final MediaEntity entity;
  final WidgetRef parentRef;
  const _MediaActionSheet({required this.entity, required this.parentRef});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MediaActionSheetContent(entity: entity);
  }
}

class OverflowMenuButton extends ConsumerWidget {
  final MediaEntity entity;
  final double size;
  final Color? color;

  const OverflowMenuButton({
    super.key,
    required this.entity,
    this.size = 20,
    this.color,
  });

  /// Shortcut constructor for songs.
  factory OverflowMenuButton.song(Song song, {Key? key, double size = 20, Color? color}) {
    return OverflowMenuButton(
      key: key,
      entity: MediaEntity.fromSong(song),
      size: size,
      color: color,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => showMediaActionSheet(context, ref, entity),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Icon(
          Icons.more_vert,
          size: size,
          color: color ?? const Color(0xFF666666),
        ),
      ),
    );
  }
}
