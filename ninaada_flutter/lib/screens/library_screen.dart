import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/providers/app_providers.dart';
import 'package:ninaada_music/providers/network_provider.dart';
import 'package:ninaada_music/widgets/media_action_sheet.dart';
import 'package:ninaada_music/widgets/song_tile.dart';
import 'package:ninaada_music/widgets/song_widgets.dart';
import 'package:ninaada_music/services/download_manager.dart';
import 'package:ninaada_music/widgets/download_indicator.dart';

/// Library screen — Your Library header, 4 sub-tabs, tab content
/// Matches RN library tab pixel-perfect
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _playlistInput = TextEditingController();

  @override
  void dispose() {
    _playlistInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider);
    final topPad = MediaQuery.of(context).padding.top;

    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        // Header gradient — scrolls away
        SliverToBoxAdapter(
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(16, topPad + 18, 16, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A1333), Color(0xFF0B0F1A)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your Library', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                const SizedBox(height: 6),
                Text(
                  '${lib.playlists.length} playlists · ${lib.downloadedSongs.length} downloads · ${lib.likedSongs.length} liked',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                ),
              ],
            ),
          ),
        ),

        // Tabs — scrolls away with header
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _LibTab(label: 'Playlists', icon: Icons.library_music, active: lib.libraryTab == 'playlists', onTap: () => ref.read(libraryProvider.notifier).setLibraryTab('playlists')),
                _LibTab(label: 'Downloads', icon: Icons.arrow_circle_down_outlined, active: lib.libraryTab == 'downloads', onTap: () => ref.read(libraryProvider.notifier).setLibraryTab('downloads')),
                _LibTab(label: 'Liked', icon: Icons.favorite, active: lib.libraryTab == 'liked', onTap: () => ref.read(libraryProvider.notifier).setLibraryTab('liked')),
                _LibTab(label: 'Smart', icon: Icons.flash_on, active: lib.libraryTab == 'smart', onTap: () => ref.read(libraryProvider.notifier).setLibraryTab('smart')),
              ],
            ),
          ),
        ),
      ],

      // Tab content fills remaining space and scrolls independently
      body: switch (lib.libraryTab) {
        'liked' => _LikedTab(songs: lib.likedSongs),
        'downloads' => _DownloadsTab(songs: lib.downloadedSongs),
        'playlists' => lib.selectedPlaylist != null
            ? _PlaylistDetailView(playlist: lib.selectedPlaylist!)
            : _PlaylistsTab(playlists: lib.playlists, controller: _playlistInput),
        'smart' => const _SmartTab(),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

// ──────────────────────────────────────────────────────
//  Library Sub-tab widget
// ──────────────────────────────────────────────────────
class _LibTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _LibTab({required this.label, required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: active ? const Color(0xFF7C4DFF).withOpacity(0.18) : Colors.transparent,
            border: Border.all(color: active ? const Color(0xFF7C4DFF).withOpacity(0.4) : NinaadaColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: active ? const Color(0xFF7C4DFF) : const Color(0xFF888888)),
              const SizedBox(width: 3),
              Flexible(
                child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1, style: TextStyle(color: active ? const Color(0xFF7C4DFF) : const Color(0xFF888888), fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────
//  LIKED TAB
// ──────────────────────────────────────────────────────
class _LikedTab extends ConsumerWidget {
  final List<Song> songs;
  const _LikedTab({required this.songs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border, size: 60, color: const Color(0xFF333333)),
            const SizedBox(height: 12),
            const Text('No Liked Songs', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    final reversed = songs.reversed.toList();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 140),
      itemCount: reversed.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          // Play All button
          return GestureDetector(
            onTap: () {
              ref.read(playerProvider.notifier).setQueue(reversed);
              ref.read(playerProvider.notifier).playSong(reversed[0]);
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: const Color(0xFF7C4DFF).withOpacity(0.10),
                border: Border.all(color: const Color(0xFF7C4DFF).withOpacity(0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.play_arrow, size: 18, color: Color(0xFF7C4DFF)),
                  SizedBox(width: 6),
                  Text('Play All Liked', style: TextStyle(color: Color(0xFF7C4DFF), fontWeight: FontWeight.w700, fontSize: 14)),
                ],
              ),
            ),
          );
        }
        final song = reversed[index - 1];
        final network = ref.watch(networkProvider);
        return SongTile(
          song: song,
          index: index,
          enabled: isSongAvailable(network, song.id),
          onTap: () => ref.read(playerProvider.notifier).playSong(song),
          onMenu: () => showSongActionSheet(context, ref, song),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────
//  DOWNLOADS TAB — Offline Music Library (Phase 9)
// ──────────────────────────────────────────────────────
class _DownloadsTab extends ConsumerWidget {
  final List<Song> songs;
  const _DownloadsTab({required this.songs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Granular selectors — only rebuild on count changes, not every progress tick.
    final pendingCount = ref.watch(downloadProvider.select((s) => s.pendingCount));
    final failedCount  = ref.watch(downloadProvider.select((s) => s.failedCount));

    if (songs.isEmpty && pendingCount == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_outlined, size: 60, color: const Color(0xFF333333)),
            const SizedBox(height: 12),
            const Text('No Downloads', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Downloaded songs will appear here',
                style: TextStyle(color: Color(0xFF666666), fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 140),
      itemCount: songs.length + 3, // +1 Play All, +1 Shuffle, +1 Storage info
      itemBuilder: (context, index) {
        // ── Row 0: Play All + Shuffle buttons ──
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: songs.isEmpty
                        ? null
                        : () {
                            ref.read(playerProvider.notifier).setQueue(songs);
                            ref.read(playerProvider.notifier).playSong(songs[0]);
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        color: const Color(0xFF7C4DFF).withOpacity(0.10),
                        border: Border.all(color: const Color(0xFF7C4DFF).withOpacity(0.5)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_arrow, size: 18, color: Color(0xFF7C4DFF)),
                          SizedBox(width: 6),
                          Text('Play All',
                              style: TextStyle(
                                  color: Color(0xFF7C4DFF), fontWeight: FontWeight.w700, fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: songs.isEmpty
                        ? null
                        : () {
                            final shuffled = List<Song>.from(songs)..shuffle();
                            ref.read(playerProvider.notifier).setQueue(shuffled);
                            ref.read(playerProvider.notifier).playSong(shuffled[0]);
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        color: Colors.white.withOpacity(0.04),
                        border: Border.all(color: Colors.white.withOpacity(0.12)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shuffle, size: 18, color: Color(0xFF9B7AFF)),
                          SizedBox(width: 6),
                          Text('Shuffle',
                              style: TextStyle(
                                  color: Color(0xFF9B7AFF),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // ── Row 1: Active downloads progress (if any) ──
        if (index == 1) {
          if (pendingCount == 0 && failedCount == 0) {
            return const SizedBox.shrink();
          }
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: NinaadaColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: NinaadaColors.border),
            ),
            child: Row(
              children: [
                if (pendingCount > 0) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: NinaadaColors.primaryLight),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$pendingCount downloading...',
                    style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
                  ),
                ],
                if (pendingCount > 0 && failedCount > 0)
                  const SizedBox(width: 12),
                if (failedCount > 0) ...[
                  const Icon(Icons.error_outline, size: 16, color: Color(0xFFFF5252)),
                  const SizedBox(width: 4),
                  Text(
                    '$failedCount failed',
                    style: const TextStyle(color: Color(0xFFFF5252), fontSize: 12),
                  ),
                ],
                const Spacer(),
                Text(
                  '${songs.length} offline',
                  style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
                ),
              ],
            ),
          );
        }

        // ── Row 2: Storage info ──
        if (index == 2) {
          return _StorageInfoTile(songCount: songs.length);
        }

        // ── Song rows ──
        final song = songs[index - 3];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: SongTile(
                  song: song,
                  index: index - 2,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  onTap: () => ref.read(playerProvider.notifier).playSong(song),
                  onMenu: () => showSongActionSheet(context, ref, song),
                ),
              ),
              GestureDetector(
                onTap: () => _confirmDelete(context, ref, song),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.delete_outline, size: 18, color: NinaadaColors.primary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Song song) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NinaadaColors.surface,
        title: const Text('Remove Download?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete "${song.name}" from offline storage?\nThis will remove the downloaded file.',
          style: const TextStyle(color: Color(0xFF888888)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              // Remove from both DownloadManager (files + Hive 'downloads')
              // and LibraryNotifier (Hive 'library' downloadedSongs list)
              DownloadManager().deleteDownload(song.id);
              ref.read(libraryProvider.notifier).deleteDownload(song.id);
              // Hot-swap back to remote source if song is in active queue
              ref.read(playerProvider.notifier).handleDownloadDeleted(song.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Color(0xFFFF5252))),
          ),
        ],
      ),
    );
  }
}

/// Async storage size tile — computes actual disk usage without blocking.
class _StorageInfoTile extends StatefulWidget {
  final int songCount;
  const _StorageInfoTile({required this.songCount});

  @override
  State<_StorageInfoTile> createState() => _StorageInfoTileState();
}

class _StorageInfoTileState extends State<_StorageInfoTile> {
  int _bytes = 0;

  @override
  void initState() {
    super.initState();
    _loadSize();
  }

  Future<void> _loadSize() async {
    final size = await DownloadManager().getStorageUsed();
    if (mounted) setState(() => _bytes = size);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final quality = ref.watch(downloadQualityProvider);

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NinaadaColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: NinaadaColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.folder_outlined, size: 18, color: Color(0xFF888888)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Offline Storage',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.songCount} songs · ${_formatBytes(_bytes)}',
                          style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: Color(0xFF222222)),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Download Quality',
                      style: TextStyle(color: Color(0xFF888888), fontSize: 11, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  _QualityChip(
                    label: 'Low',
                    active: quality == 'Low',
                    onTap: () => ref.read(downloadQualityProvider.notifier).state = 'Low',
                  ),
                  const SizedBox(width: 6),
                  _QualityChip(
                    label: 'Med',
                    active: quality == 'Medium',
                    onTap: () => ref.read(downloadQualityProvider.notifier).state = 'Medium',
                  ),
                  const SizedBox(width: 6),
                  _QualityChip(
                    label: 'High',
                    active: quality == 'High',
                    onTap: () => ref.read(downloadQualityProvider.notifier).state = 'High',
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QualityChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _QualityChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: active ? NinaadaColors.primary.withOpacity(0.12) : Colors.white.withOpacity(0.04),
          border: Border.all(
            color: active ? NinaadaColors.primary.withOpacity(0.4) : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? NinaadaColors.primary : const Color(0xFF888888),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────
//  PLAYLISTS TAB
// ──────────────────────────────────────────────────────
class _PlaylistsTab extends ConsumerWidget {
  final List<PlaylistModel> playlists;
  final TextEditingController controller;
  const _PlaylistsTab({required this.playlists, required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (playlists.isEmpty) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 140),
        children: [
          _buildCreateRow(ref),
          const SizedBox(height: 80),
          Center(
            child: Column(
              children: [
                Icon(Icons.library_music_outlined, size: 60, color: const Color(0xFF333333)),
                const SizedBox(height: 12),
                const Text('No Playlists', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 140),
      itemCount: playlists.length + 1, // +1 for create row
      itemBuilder: (context, index) {
        if (index == 0) return _buildCreateRow(ref);
        final pl = playlists[index - 1];
        return GestureDetector(
          onTap: () => ref.read(libraryProvider.notifier).selectPlaylist(pl),
          onLongPress: () => showMediaActionSheet(
            context,
            ref,
            MediaEntity.fromPlaylist(pl),
          ),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NinaadaColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NinaadaColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(colors: [NinaadaColors.primary, NinaadaColors.primaryDark]),
                  ),
                  child: const Icon(Icons.library_music, size: 22, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pl.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text('${pl.songs.length} songs', style: const TextStyle(color: Color(0xFF888888), fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 20, color: Color(0xFF666666)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCreateRow(WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'New playlist...',
                hintStyle: const TextStyle(color: Color(0xFF666666)),
                filled: true,
                fillColor: NinaadaColors.surfaceLight,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: NinaadaColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: NinaadaColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: NinaadaColors.primary)),
              ),
              onSubmitted: (_) => _create(ref),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _create(ref),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: NinaadaColors.surfaceLight,
                border: Border.all(color: NinaadaColors.border),
              ),
              child: const Icon(Icons.add, size: 20, color: Color(0xFF888888)),
            ),
          ),
        ],
      ),
    );
  }

  void _create(WidgetRef ref) {
    final name = controller.text.trim();
    if (name.isEmpty) return;
    ref.read(libraryProvider.notifier).createPlaylist(name);
    controller.clear();
  }
}

// ──────────────────────────────────────────────────────
//  PLAYLIST DETAIL VIEW
// ──────────────────────────────────────────────────────
class _PlaylistDetailView extends ConsumerWidget {
  final PlaylistModel playlist;
  const _PlaylistDetailView({required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (playlist.songs.isEmpty) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 140),
        children: [
          _buildHeader(context, ref),
          const SizedBox(height: 80),
          const Center(child: Text('Empty playlist', style: TextStyle(color: Color(0xFF888888)))),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 140),
      itemCount: playlist.songs.length + 2, // +1 header, +1 action pills
      itemBuilder: (context, index) {
        if (index == 0) return _buildHeader(context, ref);
        if (index == 1) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PlaylistActionPill(
                  icon: Icons.play_arrow,
                  label: 'Play All',
                  color: NinaadaColors.primary.withOpacity(0.15),
                  borderColor: NinaadaColors.primary.withOpacity(0.3),
                  onTap: () {
                    ref.read(playerProvider.notifier).setQueue(playlist.songs);
                    ref.read(playerProvider.notifier).playSong(playlist.songs[0]);
                  },
                ),
                const SizedBox(width: 10),
                _PlaylistActionPill(
                  icon: Icons.shuffle,
                  label: 'Shuffle',
                  color: Colors.white.withOpacity(0.06),
                  borderColor: Colors.white.withOpacity(0.1),
                  onTap: () {
                    final shuffled = List<Song>.from(playlist.songs)..shuffle();
                    ref.read(playerProvider.notifier).setQueue(shuffled);
                    ref.read(playerProvider.notifier).toggleShuffle();
                    ref.read(playerProvider.notifier).playSong(shuffled[0]);
                  },
                ),
              ],
            ),
          );
        }
        final song = playlist.songs[index - 2];
        final network = ref.watch(networkProvider);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: SongTile(
                  song: song,
                  index: index - 1,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  enabled: isSongAvailable(network, song.id),
                  onTap: () => ref.read(playerProvider.notifier).playSong(song),
                  onMenu: () => showSongActionSheet(context, ref, song),
                ),
              ),
              GestureDetector(
                onTap: () => _confirmRemove(context, ref, song),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.close, size: 18, color: NinaadaColors.primary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => ref.read(libraryProvider.notifier).selectPlaylist(null),
            child: Icon(Icons.chevron_left, size: 20, color: Colors.white.withOpacity(0.5)),
          ),
          Expanded(
            child: Text(
              playlist.name,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          GestureDetector(
            onTap: () => _confirmDeletePlaylist(context, ref, playlist),
            child: const Icon(Icons.delete_outline, size: 18, color: NinaadaColors.primary),
          ),
        ],
      ),
    );
  }

  void _confirmDeletePlaylist(BuildContext context, WidgetRef ref, PlaylistModel playlist) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NinaadaColors.surface,
        title: const Text('Delete Playlist?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${playlist.name}"? This cannot be undone.',
          style: const TextStyle(color: Color(0xFF888888)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(libraryProvider.notifier).deletePlaylist(playlist.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Color(0xFFFF5252))),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context, WidgetRef ref, Song song) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NinaadaColors.surface,
        title: const Text('Remove Song?', style: TextStyle(color: Colors.white)),
        content: Text('Remove "${song.name}" from this playlist?', style: const TextStyle(color: Color(0xFF888888))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(libraryProvider.notifier).removeFromPlaylist(song.id, playlist.id);
              Navigator.pop(ctx);
            },
            child: const Text('Remove', style: TextStyle(color: Color(0xFFFF5252))),
          ),
        ],
      ),
    );
  }
}

class _PlaylistActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color borderColor;
  final VoidCallback onTap;

  const _PlaylistActionPill({required this.icon, required this.label, required this.color, required this.borderColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: Colors.white.withOpacity(0.6)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────
//  SMART FOLDERS TAB (Phase 6 — Advanced Grouping)
// ──────────────────────────────────────────────────────
//
//  Generates auto-organized folders from liked songs across
//  4 dimensions, each with a minimum threshold of 3 songs:
//
//    1. Language   — group by song.language ("Hindi", "English"…)
//    2. Artist     — group by primary artist
//    3. Decade     — extract decade from song.year ("2020s", "2010s"…)
//    4. Mood/Vibe  — keyword matching in song name/artist/album
//
//  Folders are sorted by song count (descending) within each section,
//  sections are separated by headers.
// ──────────────────────────────────────────────────────

/// Minimum songs required before a smart folder is rendered.
const int _kSmartFolderThreshold = 3;

class _SmartTab extends ConsumerWidget {
  const _SmartTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final sections = _generateSmartSections(lib.likedSongs);

    if (sections.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.flash_on_outlined, size: 60, color: const Color(0xFF333333)),
              const SizedBox(height: 12),
              const Text('Smart Folders', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text(
                'Like or download songs to auto-organize by language, artist, decade & mood',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF888888), fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    // Flatten sections into a list of widgets
    final items = <Widget>[];
    for (final section in sections) {
      // Section header
      items.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Row(
          children: [
            Icon(section.sectionIcon, size: 16, color: NinaadaColors.primary),
            const SizedBox(width: 8),
            Text(
              section.sectionTitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Container(height: 1, color: const Color(0xFF222222))),
          ],
        ),
      ));

      // Folders in this section
      for (final folder in section.folders) {
        items.add(_SmartFolderTile(folder: folder));
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 140),
      children: items,
    );
  }

  /// Build all smart folder sections from liked songs.
  List<_SmartSection> _generateSmartSections(List<Song> likedSongs) {
    if (likedSongs.length < _kSmartFolderThreshold) return [];

    final sections = <_SmartSection>[];

    // ── 1. Language folders ──
    final byLanguage = <String, List<Song>>{};
    for (final song in likedSongs) {
      final lang = song.language.trim();
      if (lang.isEmpty) continue;
      final displayLang = '${lang[0].toUpperCase()}${lang.substring(1).toLowerCase()}';
      byLanguage.putIfAbsent(displayLang, () => []).add(song);
    }
    final langFolders = byLanguage.entries
        .where((e) => e.value.length >= _kSmartFolderThreshold)
        .map((e) => _SmartFolder(name: e.key, icon: Icons.language, songs: e.value))
        .toList()
      ..sort((a, b) => b.songs.length.compareTo(a.songs.length));
    if (langFolders.isNotEmpty) {
      sections.add(_SmartSection(
        sectionTitle: 'BY LANGUAGE',
        sectionIcon: Icons.language,
        folders: langFolders,
      ));
    }

    // ── 2. Artist folders ──
    final byArtist = <String, List<Song>>{};
    for (final song in likedSongs) {
      final artist = song.artist.split(',').first.trim();
      if (artist.isEmpty) continue;
      byArtist.putIfAbsent(artist, () => []).add(song);
    }
    final artistFolders = byArtist.entries
        .where((e) => e.value.length >= _kSmartFolderThreshold)
        .map((e) => _SmartFolder(name: e.key, icon: Icons.person, songs: e.value))
        .toList()
      ..sort((a, b) => b.songs.length.compareTo(a.songs.length));
    if (artistFolders.isNotEmpty) {
      sections.add(_SmartSection(
        sectionTitle: 'BY ARTIST',
        sectionIcon: Icons.person,
        folders: artistFolders,
      ));
    }

    // ── 3. Decade folders ──
    final byDecade = <String, List<Song>>{};
    for (final song in likedSongs) {
      final yearStr = song.year.trim();
      if (yearStr.isEmpty) continue;
      final year = int.tryParse(yearStr);
      if (year == null || year < 1900 || year > 2099) continue;
      final decade = '${(year ~/ 10) * 10}s'; // "2020s", "1990s"
      byDecade.putIfAbsent(decade, () => []).add(song);
    }
    final decadeFolders = byDecade.entries
        .where((e) => e.value.length >= _kSmartFolderThreshold)
        .map((e) => _SmartFolder(name: e.key, icon: Icons.calendar_month, songs: e.value))
        .toList()
      ..sort((a, b) => b.name.compareTo(a.name)); // most recent decade first
    if (decadeFolders.isNotEmpty) {
      sections.add(_SmartSection(
        sectionTitle: 'BY DECADE',
        sectionIcon: Icons.calendar_month,
        folders: decadeFolders,
      ));
    }

    // ── 4. Mood / Vibe folders ──
    final moodDefs = <String, List<String>>{
      'Chill & Lofi': ['lofi', 'chill', 'relax', 'calm', 'ambient', 'soft', 'sleep', 'peaceful'],
      'Party & Dance': ['party', 'dance', 'club', 'dj', 'remix', 'bass', 'beat', 'groove'],
      'Romantic': ['love', 'romantic', 'heart', 'valentine', 'pyaar', 'ishq', 'dil'],
      'Workout & Energy': ['workout', 'energy', 'pump', 'power', 'run', 'gym', 'motivation'],
      'Devotional': ['bhajan', 'prayer', 'devotion', 'spiritual', 'god', 'aarti', 'mantra'],
      'Sad & Emotional': ['sad', 'heartbreak', 'pain', 'cry', 'broken', 'tanha', 'judai'],
    };
    final byMood = <String, List<Song>>{};
    final usedInMood = <String>{}; // A song can appear in multiple moods
    for (final entry in moodDefs.entries) {
      final matching = likedSongs.where((s) {
        final text = '${s.name} ${s.artist} ${s.album} ${s.subtitle ?? ''}'.toLowerCase();
        return entry.value.any((kw) => text.contains(kw));
      }).toList();
      if (matching.length >= _kSmartFolderThreshold) {
        byMood[entry.key] = matching;
      }
    }
    final moodFolders = byMood.entries
        .map((e) => _SmartFolder(
              name: e.key,
              icon: _moodIcon(e.key),
              songs: e.value,
            ))
        .toList()
      ..sort((a, b) => b.songs.length.compareTo(a.songs.length));
    if (moodFolders.isNotEmpty) {
      sections.add(_SmartSection(
        sectionTitle: 'BY MOOD & VIBE',
        sectionIcon: Icons.auto_awesome,
        folders: moodFolders,
      ));
    }

    return sections;
  }

  /// Map mood folder names to appropriate icons.
  IconData _moodIcon(String mood) {
    return switch (mood) {
      'Chill & Lofi' => Icons.headphones,
      'Party & Dance' => Icons.celebration,
      'Romantic' => Icons.favorite,
      'Workout & Energy' => Icons.fitness_center,
      'Devotional' => Icons.self_improvement,
      'Sad & Emotional' => Icons.water_drop,
      _ => Icons.auto_awesome,
    };
  }
}

/// A single smart folder tile with tap-to-play and preview songs.
class _SmartFolderTile extends ConsumerWidget {
  final _SmartFolder folder;
  const _SmartFolderTile({required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        // Folder header
        GestureDetector(
          onTap: () {
            ref.read(playerProvider.notifier).setQueue(folder.songs);
            ref.read(playerProvider.notifier).playSong(folder.songs[0]);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(folder.icon, size: 20, color: NinaadaColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(folder.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                ),
                Text('${folder.songs.length} songs', style: const TextStyle(color: Color(0xFF888888), fontSize: 12)),
                const SizedBox(width: 8),
                const Icon(Icons.play_arrow, size: 16, color: NinaadaColors.primary),
              ],
            ),
          ),
        ),
        // Preview songs (up to 4)
        ...folder.songs.take(4).toList().asMap().entries.map(
          (e) {
            final network = ref.watch(networkProvider);
            return SongTile(
              song: e.value,
              index: e.key + 1,
              enabled: isSongAvailable(network, e.value.id),
              onTap: () => ref.read(playerProvider.notifier).playSong(e.value),
              onMenu: () => showSongActionSheet(context, ref, e.value),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// A group of smart folders under a section header.
class _SmartSection {
  final String sectionTitle;
  final IconData sectionIcon;
  final List<_SmartFolder> folders;

  const _SmartSection({
    required this.sectionTitle,
    required this.sectionIcon,
    required this.folders,
  });
}

class _SmartFolder {
  final String name;
  final IconData icon;
  final List<Song> songs;
  _SmartFolder({required this.name, required this.icon, required this.songs});
}
