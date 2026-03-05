import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/helpers.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/services/recommendation_engine.dart';
import 'package:ninaada_music/providers/network_provider.dart';
import 'package:ninaada_music/widgets/song_tile.dart';

// ════════════════════════════════════════════════════════════════
//  RECOMMENDATION WIDGETS — Glassy cards for Home screen sections
// ════════════════════════════════════════════════════════════════

/// ─────────────────────────────────────────────────
///  MADE FOR YOU — scrollable tab chips + song list
///  Tapping a chip switches displayed songs (no playback).
/// ─────────────────────────────────────────────────
class MadeForYouSection extends ConsumerWidget {
  final List<MadeForYouTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;
  final void Function(Song song) onPlaySong;
  final void Function(Song song) onMenu;

  const MadeForYouSection({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelectTab,
    required this.onPlaySong,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tabs.isEmpty) return const SizedBox.shrink();

    final idx = selectedIndex.clamp(0, tabs.length - 1);
    final activeTab = tabs[idx];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text(
            'Made For You',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        // ── Tab chips ──
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            physics: const BouncingScrollPhysics(),
            cacheExtent: 500.0,
            itemCount: tabs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final tab = tabs[i];
              final selected = i == idx;
              final baseColor = tab.color ?? NinaadaColors.primary;
              return GestureDetector(
                onTap: () => onSelectTab(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: selected
                        ? baseColor.withOpacity(0.25)
                        : Colors.white.withOpacity(0.06),
                    border: Border.all(
                      color: selected
                          ? baseColor.withOpacity(0.5)
                          : Colors.white.withOpacity(0.08),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _iconForTabName(tab.icon),
                        size: 14,
                        color: selected ? baseColor : Colors.white.withOpacity(0.6),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tab.title.replaceAll('\n', ' '),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected
                              ? Colors.white
                              : Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        // ── Song list for selected tab ──
        ...activeTab.songs.take(6).map((song) {
          final network = ref.watch(networkProvider);
          return SongTile(
            song: song,
            showDuration: false,
            enabled: isSongAvailable(network, song.id),
            onTap: () => onPlaySong(song),
            onMenu: () => onMenu(song),
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }

  IconData _iconForTabName(String name) {
    switch (name) {
      case 'person':
        return Icons.person;
      case 'language':
        return Icons.language;
      case 'wb_sunny':
        return Icons.wb_sunny;
      case 'headphones':
        return Icons.headphones;
      case 'flash_on':
        return Icons.flash_on;
      default:
        return Icons.music_note;
    }
  }
}

/// ─────────────────────────────────────────────────
///  DAILY MIX — horizontal carousel of clustered mixes
/// ─────────────────────────────────────────────────
class DailyMixCarousel extends StatelessWidget {
  final List<List<Song>> mixes;
  final void Function(List<Song> mix, int index) onTapMix;

  const DailyMixCarousel({
    super.key,
    required this.mixes,
    required this.onTapMix,
  });

  @override
  Widget build(BuildContext context) {
    if (mixes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text(
            'Daily Mix',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            physics: const BouncingScrollPhysics(),
            cacheExtent: 500.0,
            itemCount: mixes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, index) {
              final mix = mixes[index];
              if (mix.isEmpty) return const SizedBox.shrink();

              // Use first song's image as the card art
              final coverSong = mix.first;
              final mixColors = [
                const Color(0xFF6D28D9),
                const Color(0xFF0D9488),
                const Color(0xFFBE185D),
                const Color(0xFFD97706),
                const Color(0xFF065F46),
              ];
              final color = mixColors[index % mixColors.length];

              return GestureDetector(
                onTap: () => onTapMix(mix, index),
                child: SizedBox(
                  width: 130,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          children: [
                            CachedNetworkImage(
                              imageUrl: safeImageUrl(coverSong.image),
                              width: 130,
                              height: 130,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                width: 130,
                                height: 130,
                                color: color.withOpacity(0.3),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                width: 130,
                                height: 130,
                                color: color.withOpacity(0.3),
                                child: const Icon(Icons.music_note,
                                    color: Colors.white38, size: 28),
                              ),
                            ),
                            Positioned(
                              bottom: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${mix.length} songs',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Daily Mix ${index + 1}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        coverSong.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 11,
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
    );
  }
}

/// ─────────────────────────────────────────────────
///  DISCOVER WEEKLY — horizontal song list with play button
/// ─────────────────────────────────────────────────
class DiscoverWeeklySection extends StatelessWidget {
  final List<Song> songs;
  final void Function(Song song) onPlay;
  final VoidCallback? onPlayAll;
  final void Function(Song song)? onLongPressSong;

  const DiscoverWeeklySection({
    super.key,
    required this.songs,
    required this.onPlay,
    this.onPlayAll,
    this.onLongPressSong,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Discover Weekly',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              if (onPlayAll != null)
                GestureDetector(
                  onTap: onPlayAll,
                  child: const Text(
                    'Play all',
                    style: TextStyle(
                      color: NinaadaColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            physics: const BouncingScrollPhysics(),
            cacheExtent: 500.0,
            itemCount: songs.take(10).length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, index) {
              final song = songs[index];
              return GestureDetector(
                onTap: () => onPlay(song),
                onLongPress: onLongPressSong != null ? () => onLongPressSong!(song) : null,
                child: SizedBox(
                  width: 120,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: safeImageUrl(song.image),
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            width: 120,
                            height: 120,
                            color: NinaadaColors.surfaceLight,
                          ),
                          errorWidget: (_, __, ___) => Container(
                            width: 120,
                            height: 120,
                            color: NinaadaColors.surfaceLight,
                            child: const Icon(Icons.music_note,
                                size: 24, color: Color(0xFF666666)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        song.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 11,
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
    );
  }
}

/// ─────────────────────────────────────────────────
///  TOP PICKS — horizontal cards, each with 6-song row display
/// ─────────────────────────────────────────────────
class TopPicksSection extends ConsumerWidget {
  final List<TopPicksCard> cards;
  final void Function(Song song) onPlaySong;
  final void Function(TopPicksCard card) onPlayAll;
  final void Function(Song song)? onMenuSong;

  const TopPicksSection({
    super.key,
    required this.cards,
    required this.onPlaySong,
    required this.onPlayAll,
    this.onMenuSong,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (cards.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text(
            'Top Picks For You',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(
          height: 448,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            physics: const BouncingScrollPhysics(),
            cacheExtent: 500.0,
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, index) {
              final card = cards[index];
              return _TopPickCard(
                card: card,
                index: index,
                onPlaySong: onPlaySong,
                onPlayAll: () => onPlayAll(card),
                onMenuSong: onMenuSong,
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _TopPickCard extends ConsumerWidget {
  final TopPicksCard card;
  final int index;
  final void Function(Song) onPlaySong;
  final VoidCallback onPlayAll;
  final void Function(Song)? onMenuSong;

  const _TopPickCard({
    required this.card,
    required this.index,
    required this.onPlaySong,
    required this.onPlayAll,
    this.onMenuSong,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF121826),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    card.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onPlayAll,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: NinaadaColors.primary.withOpacity(0.15),
                    ),
                    child: const Text(
                      'Play All',
                      style: TextStyle(
                        color: NinaadaColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Song rows (6 max) — matched to Quick Picks dimensions
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              physics: const NeverScrollableScrollPhysics(),
              itemCount: card.displaySongs.take(6).length,
              itemBuilder: (_, i) {
                final song = card.displaySongs[i];
                final network = ref.watch(networkProvider);
                return SongTile(
                  song: song,
                  showDuration: false,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  enabled: isSongAvailable(network, song.id),
                  onTap: () => onPlaySong(song),
                  onMenu: () => onMenuSong?.call(song),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
