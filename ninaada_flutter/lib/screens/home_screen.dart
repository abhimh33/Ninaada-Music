import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/constants.dart';
import 'package:ninaada_music/core/helpers.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/providers/app_providers.dart';
import 'package:ninaada_music/providers/network_provider.dart';
import 'package:ninaada_music/providers/sleep_alarm_provider.dart';
import 'package:ninaada_music/services/speed_dial_service.dart';
import 'package:ninaada_music/widgets/media_action_sheet.dart';
import 'package:ninaada_music/widgets/skeleton_widgets.dart';
import 'package:ninaada_music/widgets/song_tile.dart';
import 'package:ninaada_music/widgets/song_widgets.dart';
import 'package:ninaada_music/widgets/recommendation_widgets.dart';
import 'package:ninaada_music/widgets/made_for_you_grid.dart';
import 'package:ninaada_music/widgets/universal_context_menu.dart';
import 'package:ninaada_music/providers/made_for_you_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Home screen — matches RN home tab pixel-perfect
/// Header gradient, mood pills, recently played, quick picks, trending, most played,
/// albums, top songs, new releases, featured, downloads
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    final library = ref.watch(libraryProvider);
    final sleep = ref.watch(sleepAlarmProvider);
    final network = ref.watch(networkProvider);

    return CustomScrollView(
      slivers: [
        // === HEADER GRADIENT ===
        SliverToBoxAdapter(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1C1336), Color(0xFF0B0F1A)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 44, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            getGreeting(),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.5),
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 1),
                          const Text(
                            'Ninaada',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.8,
                              height: 1.15,
                            ),
                          ),
                          Text(
                            'Resonating Beyond Listening',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.35),
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Search icon — ghost button
                    GestureDetector(
                      onTap: () => ref.read(navigationProvider.notifier).toggleSearch(true),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.05),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Icon(
                          Icons.search_rounded,
                          size: 21,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Overflow menu — ghost button
                    GestureDetector(
                      onTap: () => _showAboutNinaada(context),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.05),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Icon(
                          Icons.more_vert_rounded,
                          size: 21,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ),
                  ],
                ),
                // Mood pills
                const SizedBox(height: 14),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    cacheExtent: 500.0,
                    itemCount: moods.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final m = moods[i];
                      return GestureDetector(
                        onTap: () {
                          ref.read(navigationProvider.notifier).goTab(AppTab.explore);
                          ref.read(exploreProvider.notifier).loadMood(
                            m.name,
                            m.query,
                            m.color,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: Colors.white.withOpacity(0.06),
                            border: Border.all(color: m.color.withOpacity(0.27)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(m.icon, size: 14, color: m.color),
                              const SizedBox(width: 6),
                              Text(
                                m.name,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // === VIBES (time-aware mood strip, refreshed on resume) ===
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vibes Right Now',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withOpacity(0.85),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    cacheExtent: 500.0,
                    itemCount: getVibes().length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final v = getVibes()[i];
                      return GestureDetector(
                        onTap: () {
                          ref.read(navigationProvider.notifier).goTab(AppTab.explore);
                          ref.read(exploreProvider.notifier).loadMood(v.name, v.query, v.color);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: Colors.white.withOpacity(0.06),
                            border: Border.all(color: v.color.withOpacity(0.27)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(v.icon, size: 14, color: v.color),
                              const SizedBox(width: 6),
                              Text(
                                v.name,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // === SLEEP / DOWNLOAD BANNERS ===
        if (sleep.sleepActive)
          SliverToBoxAdapter(
            child: _Banner(
              icon: Icons.nightlight_round,
              text: sleep.endOfSong
                  ? 'Stopping after song'
                  : 'Sleep: ${fmt(sleep.sleepRemaining)}',
              trailing: GestureDetector(
                onTap: () => ref.read(sleepAlarmProvider.notifier).startSleep(0),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFFFF5252), fontSize: 12)),
              ),
            ),
          ),

        // === LOADING (shimmer skeleton) ===
        if (home.loading)
          const SliverToBoxAdapter(child: HomeScreenSkeleton()),

        // === RECENTLY PLAYED (pinned songs first, then regular) ===
        if (library.recentlyPlayed.isNotEmpty)
          SliverToBoxAdapter(
            child: Builder(builder: (_) {
              final pinned = SpeedDialService().loadAll();
              final pinnedIds = pinned.map((s) => s.id).toSet();
              // Merge: pinned first (LIFO), then regular (excluding already-pinned)
              final merged = [
                ...pinned,
                ...library.recentlyPlayed.where((s) => !pinnedIds.contains(s.id)),
              ].take(12).toList();
              return CarouselSection(
                title: 'Recently Played',
                action: 'Clear',
                onAction: () => ref.read(libraryProvider.notifier).clearRecent(),
                children: merged.map((song) {
                  final isPinned = pinnedIds.contains(song.id);
                  return CarouselCard(
                    imageUrl: song.image,
                    name: song.name,
                    subtitle: song.artist,
                    onTap: () => ref.read(playerProvider.notifier).playSong(song),
                    onLongPress: () => showSongActionSheet(context, ref, song),
                    overlay: isPinned
                        ? Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: NinaadaColors.primary.withOpacity(0.85),
                              ),
                              child: const Icon(Icons.push_pin_rounded, size: 12, color: Colors.white),
                            ),
                          )
                        : null,
                  );
                }).toList(),
              );
            }),
          ),

        // === QUICK PICKS ===
        if (home.quickPicks.isNotEmpty)
          SliverToBoxAdapter(
            child: _QuickPicksSection(
              picks: home.quickPicks,
              onPlay: (song) => ref.read(playerProvider.notifier).playSong(song),
              onMenu: (song) => showSongActionSheet(context, ref, song),
              onPlayAll: () {
                ref.read(playerProvider.notifier).setQueue(home.quickPicks);
                ref.read(playerProvider.notifier).playSong(home.quickPicks.first);
              },
            ),
          ),

        // ═══════════════════════════════════════════
        //  RECOMMENDATION SECTIONS (populated by engine)
        // ═══════════════════════════════════════════

        // === MADE FOR YOU (Glassmorphic 2×3 Grid) ===
        const SliverToBoxAdapter(
          child: MadeForYouGrid(),
        ),

        // === DAILY MIX ===
        if (home.recommendationsReady && home.dailyMix.isNotEmpty)
          SliverToBoxAdapter(
            child: DailyMixCarousel(
              mixes: home.dailyMix,
              onTapMix: (mix, index) {
                if (mix.isNotEmpty) {
                  ref.read(playerProvider.notifier).setQueue(mix);
                  ref.read(playerProvider.notifier).playSong(mix.first);
                }
              },
            ),
          ),

        // === DISCOVER WEEKLY ===
        if (home.recommendationsReady && home.discoverWeekly.isNotEmpty)
          SliverToBoxAdapter(
            child: DiscoverWeeklySection(
              songs: home.discoverWeekly,
              onPlay: (song) => ref.read(playerProvider.notifier).playSong(song),
              onLongPressSong: (song) => showSongActionSheet(context, ref, song),
              onPlayAll: () {
                ref.read(playerProvider.notifier).setQueue(home.discoverWeekly);
                ref.read(playerProvider.notifier).playSong(home.discoverWeekly.first);
              },
            ),
          ),

        // === TOP PICKS FOR YOU ===
        if (home.recommendationsReady && home.topPicks.isNotEmpty)
          SliverToBoxAdapter(
            child: TopPicksSection(
              cards: home.topPicks,
              onPlaySong: (song) => ref.read(playerProvider.notifier).playSong(song),
              onMenuSong: (song) => showSongActionSheet(context, ref, song),
              onPlayAll: (card) {
                if (card.backingSongs.isNotEmpty) {
                  ref.read(playerProvider.notifier).setQueue(card.backingSongs);
                  ref.read(playerProvider.notifier).playSong(card.backingSongs.first);
                }
              },
            ),
          ),

        // === INDIA'S BIGGEST HITS ===
        if (home.trending.isNotEmpty)
          SliverToBoxAdapter(
            child: _BrowseCarousel(
              title: "India's Biggest Hits",
              items: home.trending.take(8).toList(),
              onViewAll: () => ref.read(navigationProvider.notifier).setSubView({
                'type': 'viewAll',
                'title': "India's Biggest Hits",
                'items': home.trending,
                'kind': 'playlist',
              }),
              onTapItem: (item) => _openAlbum(ref, item),
            ),
          ),

        // === MOST PLAYED ===
        if (library.playCounts.isNotEmpty)
          SliverToBoxAdapter(
            child: CarouselSection(
              title: 'Most Played',
              children: ref.read(libraryProvider.notifier).getMostPlayed().take(8).map((song) {
                return CarouselCard(
                  imageUrl: song.image,
                  name: song.name,
                  subtitle: song.artist,
                  onTap: () => ref.read(playerProvider.notifier).playSong(song),
                  onLongPress: () => showSongActionSheet(context, ref, song),
                );
              }).toList(),
            ),
          ),

        // === ALBUMS FOR YOU === REMOVED (duplicates New Releases)

        // === TOP SONGS ===
        if (home.topSongs.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Top Songs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final song = home.topSongs[index];
                return SongTile(
                  song: song,
                  enabled: isSongAvailable(network, song.id),
                  onTap: () => ref.read(playerProvider.notifier).playSong(song),
                  onMenu: () => showSongActionSheet(context, ref, song),
                );
              },
              childCount: home.topSongs.take(8).length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
        ],

        // === NEW RELEASES ===
        if (home.newReleases.isNotEmpty)
          SliverToBoxAdapter(
            child: _BrowseCarousel(
              title: 'New Releases',
              items: home.newReleases.take(10).toList(),
              onTapItem: (item) => _openAlbum(ref, item),
            ),
          ),

        // === FEATURED PLAYLISTS ===
        if (home.featured.isNotEmpty)
          SliverToBoxAdapter(
            child: _BrowseCarousel(
              title: 'Featured Playlists',
              items: home.featured.take(10).toList(),
              onTapItem: (item) => _openAlbum(ref, item),
            ),
          ),

        // === DOWNLOADS SHORTCUT ===
        if (library.downloadedSongs.isNotEmpty)
          SliverToBoxAdapter(
            child: CarouselSection(
              title: 'Downloaded',
              action: 'View All',
              onAction: () {
                ref.read(navigationProvider.notifier).goTab(AppTab.library);
                ref.read(libraryProvider.notifier).setLibraryTab('downloads');
              },
              children: library.downloadedSongs.take(6).map((song) {
                return CarouselCard(
                  imageUrl: song.image,
                  name: song.name,
                  onTap: () => ref.read(playerProvider.notifier).playSong(song, context: 'downloaded'),
                  onLongPress: () => showSongActionSheet(context, ref, song),
                  overlay: const Positioned(
                    top: 6,
                    right: 6,
                    child: Icon(Icons.cloud_done, size: 12, color: NinaadaColors.primary),
                  ),
                );
              }).toList(),
            ),
          ),

        // === ERROR STATE ===
        if (!home.loading && home.error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Column(
                children: [
                  const Icon(Icons.cloud_off, size: 60, color: Color(0xFFFF5252)),
                  const SizedBox(height: 16),
                  const Text(
                    'Connection Error',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      home.error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF888888), fontSize: 13),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => ref.read(homeProvider.notifier).fetchHome(),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NinaadaColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // === EMPTY STATE (no error, just no data) ===
        if (!home.loading && home.error == null && library.recentlyPlayed.isEmpty && home.topSongs.isEmpty && home.trending.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Column(
                children: [
                  const Icon(Icons.music_note, size: 80, color: NinaadaColors.primary),
                  const SizedBox(height: 16),
                  const Text(
                    'Your Music Awaits',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'Tap the search icon to find songs, artists, or albums',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: const Color(0xFF888888), fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Bottom padding for mini player + bottom nav
        const SliverToBoxAdapter(child: SizedBox(height: 150)),
      ],
    );
  }

  void _openAlbum(WidgetRef ref, BrowseItem item) {
    ref.read(navigationProvider.notifier).setSubView({
      'type': 'album',
      'id': item.id,
      'data': item,
      'isPlaylist': item.type == 'playlist',
    });
  }
}

// === HELPER WIDGETS ===

class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? trailing;

  const _Banner({required this.icon, required this.text, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: NinaadaColors.primary.withOpacity(0.06),
        border: Border.all(color: NinaadaColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: NinaadaColors.primaryLight),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: NinaadaColors.primaryLight, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _QuickPicksSection extends ConsumerWidget {
  final List<Song> picks;
  final void Function(Song) onPlay;
  final void Function(Song) onMenu;
  final VoidCallback onPlayAll;

  const _QuickPicksSection({required this.picks, required this.onPlay, required this.onMenu, required this.onPlayAll});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(networkProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Quick Picks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
              GestureDetector(
                onTap: onPlayAll,
                child: const Text('Play all', style: TextStyle(color: NinaadaColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ...picks.take(6).map((song) {
          return SongTile(
            song: song,
            showDuration: false,
            enabled: isSongAvailable(network, song.id),
            onTap: () => onPlay(song),
            onMenu: () => onMenu(song),
          );
        }),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _BrowseCarousel extends StatelessWidget {
  final String title;
  final List<BrowseItem> items;
  final VoidCallback? onViewAll;
  final void Function(BrowseItem) onTapItem;

  const _BrowseCarousel({
    required this.title,
    required this.items,
    this.onViewAll,
    required this.onTapItem,
  });

  @override
  Widget build(BuildContext context) {
    return CarouselSection(
      title: title,
      action: onViewAll != null ? 'View all' : null,
      onAction: onViewAll,
      children: items.map((item) {
        return CarouselCard(
          imageUrl: item.image,
          name: item.name,
          subtitle: item.subtitle ?? item.primaryArtists ?? 'Playlist',
          onTap: () => onTapItem(item),
          onLongPress: () => UniversalContextMenu.showSheetDirect(context, item),
        );
      }).toList(),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  ABOUT NINAADA — clean bottom sheet
// ════════════════════════════════════════════════════════════════

void _showAboutNinaada(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF10141F),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _AboutNinaadaSheet(),
  );
}

class _AboutNinaadaSheet extends StatelessWidget {
  const _AboutNinaadaSheet();

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          // App name + version
          const Text(
            'Ninaada Music',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'v1.0',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 16),
          // Credit
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Engineered with ',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
                const TextSpan(
                  text: '❤️',
                  style: TextStyle(fontSize: 14),
                ),
                TextSpan(
                  text: ' by ',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
                const TextSpan(
                  text: 'Abhi M',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Links
          _AboutLink(
            icon: Icons.code_rounded,
            label: 'GitHub',
            onTap: () => _open('https://github.com/abhimh33'),
          ),
          _AboutLink(
            icon: Icons.work_outline_rounded,
            label: 'LinkedIn',
            onTap: () => _open('https://www.linkedin.com/in/abdulappa-m-4262a328a'),
          ),
          _AboutLink(
            icon: Icons.alternate_email_rounded,
            label: 'Twitter',
            onTap: () => _open('https://twitter.com/abhim_12/'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _AboutLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AboutLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF8B5CF6)),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withOpacity(0.85),
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: Colors.white.withOpacity(0.3),
            ),
          ],
        ),
      ),
    );
  }
}
