import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/constants.dart';
import 'package:ninaada_music/core/helpers.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/data/user_profile.dart';
import 'package:ninaada_music/providers/app_providers.dart';
import 'package:ninaada_music/providers/network_provider.dart';
import 'package:ninaada_music/widgets/media_action_sheet.dart';
import 'package:ninaada_music/widgets/song_tile.dart';
import 'package:ninaada_music/widgets/song_widgets.dart';

/// Explore screen — genres grid + moods grid + genre detail sub-view
/// Matches RN explore tab exactly
class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final explore = ref.watch(exploreProvider);

    // Genre/Mood detail sub-view
    if (explore.selectedGenre != null) {
      return _GenreDetailView(
        name: explore.selectedGenre!,
        color: explore.genreColor,
        songs: explore.genreSongs,
        loading: explore.genreLoading,
      );
    }

    // Main explore view
    // Phase 9A: Reorder genres — user's preferred languages first
    final profile = ref.watch(userProfileProvider);
    final preferred = profile.preferredLanguages.toSet();
    final orderedGenres = <GenreItem>[
      ...genres.where((g) => preferred.contains(g.id)),
      ...genres.where((g) => !preferred.contains(g.id)),
    ];

    return CustomScrollView(
      slivers: [
        // Header
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Explore',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.8),
                    ),
                    Text(
                      'Discover new music',
                      style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.35), letterSpacing: 0.3),
                    ),
                  ],
                ),
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
                    child: Icon(Icons.search_rounded, size: 21, color: Colors.white.withOpacity(0.7)),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Genres title
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text('Genres', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.8))),
          ),
        ),

        // Genres grid (ordered by user's preferred languages)
        SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 74,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final g = orderedGenres[index];
                return GestureDetector(
                  onTap: () => ref.read(exploreProvider.notifier).loadGenre(g.id, g.color),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [g.color.withOpacity(0.18), g.color.withOpacity(0.04)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        // Watermark icon — deep background texture
                        Positioned(
                          right: -10,
                          bottom: -10,
                          child: Icon(g.icon, size: 60, color: Colors.white.withOpacity(0.06)),
                        ),
                        // Content
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(g.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              childCount: orderedGenres.length,
            ),
          ),
        ),

        // Moods title
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Text('Moods & Activities', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.8))),
          ),
        ),

        // Moods grid
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 74,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final m = moods[index];
                return GestureDetector(
                  onTap: () => ref.read(exploreProvider.notifier).loadMood(m.name, m.query, m.color),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [m.color.withOpacity(0.18), m.color.withOpacity(0.04)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        // Watermark icon — deep background texture
                        Positioned(
                          right: -10,
                          bottom: -10,
                          child: Icon(m.icon, size: 60, color: Colors.white.withOpacity(0.06)),
                        ),
                        // Content
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(m.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              childCount: moods.length,
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 150)),
      ],
    );
  }
}

/// Genre/Mood detail view — colored header gradient, song list
class _GenreDetailView extends ConsumerWidget {
  final String name;
  final Color color;
  final List songs;
  final bool loading;

  const _GenreDetailView({
    required this.name,
    required this.color,
    required this.songs,
    required this.loading,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = titleCase(name);
    final quote = genreQuotes[name] ?? 'Curated just for you';

    if (loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header gradient (visible during loading)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1C1336), Color(0xFF0B0F1A)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 44, 16, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => ref.read(exploreProvider.notifier).clearGenre(),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.arrow_back, size: 24, color: Colors.white.withOpacity(0.6)),
                  ),
                ),
                const SizedBox(height: 10),
                Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              ],
            ),
          ),
          const Expanded(
            child: Center(child: CircularProgressIndicator(color: NinaadaColors.primary)),
          ),
        ],
      );
    }

    return CustomScrollView(
      slivers: [
        // Header gradient — scrolls with content
        SliverToBoxAdapter(
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1C1336), Color(0xFF0B0F1A)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 44, 16, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => ref.read(exploreProvider.notifier).clearGenre(),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.arrow_back, size: 24, color: Colors.white.withOpacity(0.6)),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  displayName,
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                ),
                const SizedBox(height: 4),
                Text(
                  quote,
                  style: TextStyle(color: color.withOpacity(0.8), fontSize: 13, fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 6),
                Text(
                  '${songs.length} songs',
                  style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        // Song list — scrolls as one page with header
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final song = songs[index];
              final network = ref.watch(networkProvider);
              return SongTile(
                song: song,
                enabled: isSongAvailable(network, song.id),
                onTap: () => ref.read(playerProvider.notifier).playSong(song),
                onMenu: () => showSongActionSheet(context, ref, song),
              );
            },
            childCount: songs.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 150)),
      ],
    );
  }
}
