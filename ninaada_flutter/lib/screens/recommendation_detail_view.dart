import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/helpers.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/providers/app_providers.dart';
import 'package:ninaada_music/providers/network_provider.dart';
import 'package:ninaada_music/widgets/media_action_sheet.dart';
import 'package:ninaada_music/widgets/song_tile.dart';

// ════════════════════════════════════════════════════════════════
//  RECOMMENDATION DETAIL VIEW — Full-screen song list
// ════════════════════════════════════════════════════════════════
//
//  Opened when a Made For You card is tapped.
//  Receives pre-computed song list via subView data — no re-fetch.
//  Design: gradient header matching card color → scrollable song list
//
// ════════════════════════════════════════════════════════════════

class RecommendationDetailView extends ConsumerWidget {
  final Map<String, dynamic> data;
  const RecommendationDetailView({super.key, required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.read(navigationProvider.notifier);
    final player = ref.read(playerProvider.notifier);

    final title = (data['title'] as String?) ?? 'Recommendation';
    final subtitle = (data['subtitle'] as String?) ?? '';
    final songs = (data['songs'] as List<dynamic>?)?.cast<Song>() ?? [];
    final colorValue = data['color'] as int? ?? 0xFF8B5CF6;
    final baseColor = Color(colorValue);
    final iconName = (data['iconName'] as String?) ?? 'music_note';

    return Container(
      color: NinaadaColors.background,
      child: CustomScrollView(
        slivers: [
          // ── Gradient header ──
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF1C1336),
                    Color(0xFF0B0F1A),
                  ],
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.of(context).padding.top + 16,
                16,
                16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back arrow
                  GestureDetector(
                    onTap: () => nav.setSubView(null),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.08),
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Icon card (solid dark)
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: const Color(0xFF121826),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.05),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      _resolveIcon(iconName),
                      size: 36,
                      color: baseColor,
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Title
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                      height: 1.2,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.55),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    '${songs.length} songs',
                    style: TextStyle(
                      fontSize: 12,
                      color: baseColor.withOpacity(0.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Play / Shuffle row ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                children: [
                  // Play all
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (songs.isNotEmpty) {
                          player.setQueue(songs);
                          player.playSong(songs.first);
                        }
                      },
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          color: const Color(0xFF7C4DFF).withOpacity(0.10),
                          border: Border.all(
                            color: const Color(0xFF7C4DFF).withOpacity(0.5),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.play_arrow_rounded,
                                size: 22, color: Color(0xFF7C4DFF)),
                            SizedBox(width: 6),
                            Text(
                              'Play All',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF7C4DFF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Shuffle
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (songs.isNotEmpty) {
                          player.setQueue(songs);
                          player.toggleShuffle();
                          player.playSong(
                            songs[songs.length ~/ 2],
                          );
                        }
                      },
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          color: Colors.white.withOpacity(0.06),
                          border: Border.all(
                            color: baseColor.withOpacity(0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shuffle_rounded,
                                size: 20, color: baseColor),
                            const SizedBox(width: 6),
                            Text(
                              'Shuffle',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: baseColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Song list ──
          if (songs.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                  child: Text(
                    'No songs yet — keep listening to build\nyour personalized mix!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),

          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final song = songs[index];
                final network = ref.watch(networkProvider);
                return SongTile(
                  song: song,
                  index: index + 1,
                  showDuration: false,
                  enabled: isSongAvailable(network, song.id),
                  onTap: () {
                    player.setQueue(songs);
                    player.playSong(song);
                  },
                  onMenu: () => showSongActionSheet(context, ref, song),
                );
              },
              childCount: songs.length,
            ),
          ),

          // Bottom padding for mini player + nav
          const SliverToBoxAdapter(child: SizedBox(height: 150)),
        ],
      ),
    );
  }

  static IconData _resolveIcon(String name) {
    switch (name) {
      case 'person':
        return Icons.person;
      case 'language':
        return Icons.language;
      case 'wb_sunny':
        return Icons.wb_sunny;
      case 'wb_cloudy':
        return Icons.wb_cloudy;
      case 'nights_stay':
        return Icons.nights_stay;
      case 'dark_mode':
        return Icons.dark_mode;
      case 'headphones':
        return Icons.headphones;
      case 'flash_on':
        return Icons.flash_on;
      default:
        return Icons.music_note;
    }
  }
}
