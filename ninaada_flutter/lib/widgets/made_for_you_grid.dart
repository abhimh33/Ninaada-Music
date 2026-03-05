import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/providers/app_providers.dart';
import 'package:ninaada_music/providers/made_for_you_provider.dart';

// ════════════════════════════════════════════════════════════════
//  MADE FOR YOU GRID — Premium 2×3 glassmorphic card layout
// ════════════════════════════════════════════════════════════════
//
//  Architecture:
//  • Reads from dedicated [madeForYouProvider] (NOT homeProvider)
//  • Zero inline song rendering — cards are navigation entry points
//  • Each card taps → navigationProvider.setSubView('recommendation')
//  • LayoutBuilder ensures responsive sizing across screens
//  • BackdropFilter glassmorphism + gradient overlay per card
//  • Scale animation on press (0.96 → 1.0) for tactile feedback
//
// ════════════════════════════════════════════════════════════════

class MadeForYouGrid extends ConsumerWidget {
  const MadeForYouGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mfy = ref.watch(madeForYouProvider);

    if (!mfy.isReady && !mfy.loading) return const SizedBox.shrink();

    if (mfy.loading && !mfy.isReady) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: NinaadaColors.primary.withOpacity(0.5),
            ),
          ),
        ),
      );
    }

    final cards = mfy.cards;
    if (cards.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header + refresh
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Made For You',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Personalized Picks',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.4),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => ref.read(madeForYouProvider.notifier).refresh(),
                child: AnimatedRotation(
                  turns: mfy.loading ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 600),
                  child: Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    color: Colors.white.withOpacity(0.4),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 2×3 grid using LayoutBuilder for responsive card sizing
          LayoutBuilder(
            builder: (context, constraints) {
              const crossAxisCount = 2;
              const spacing = 12.0;
              final cardWidth =
                  (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
                      crossAxisCount;
              // Fixed aspect ratio 1.10 → taller than wide
              final cardHeight = cardWidth / 1.10;

              // Build rows of 2
              final rows = <Widget>[];
              for (int i = 0; i < cards.length; i += crossAxisCount) {
                final rowCards = <Widget>[];
                for (int j = 0;
                    j < crossAxisCount && i + j < cards.length;
                    j++) {
                  if (j > 0) {
                    rowCards.add(const SizedBox(width: spacing));
                  }
                  rowCards.add(
                    SizedBox(
                      width: cardWidth,
                      height: cardHeight,
                      child: _GlassCard(
                        card: cards[i + j],
                        onTap: () {
                          final card = cards[i + j];
                          ref
                              .read(navigationProvider.notifier)
                              .setSubView({
                            'type': 'recommendation',
                            'title': card.title.replaceAll('\n', ' '),
                            'subtitle': card.subtitle,
                            'songs': card.songs,
                            'color': card.color.value,
                            'iconName': card.iconName,
                            'songCount': card.songCount,
                          });
                        },
                      ),
                    ),
                  );
                }
                // If odd number of cards, pad with empty space
                if (rowCards.length < crossAxisCount * 2 - 1) {
                  rowCards.add(const SizedBox(width: spacing));
                  rowCards.add(SizedBox(width: cardWidth));
                }
                rows.add(Row(children: rowCards));
                if (i + crossAxisCount < cards.length) {
                  rows.add(const SizedBox(height: 12));
                }
              }

              return Column(children: rows);
            },
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  GLASS CARD — Individual glassmorphic recommendation card
// ════════════════════════════════════════════════════════════════

class _GlassCard extends StatefulWidget {
  final MadeForYouCard card;
  final VoidCallback onTap;

  const _GlassCard({required this.card, required this.onTap});

  @override
  State<_GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<_GlassCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final baseColor = card.color;

    return GestureDetector(
      onTapDown: (_) => _scaleCtrl.forward(),
      onTapUp: (_) {
        _scaleCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _scaleCtrl.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnim.value,
            child: child,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: const Color(0xFF121826),
            border: Border.all(
              color: Colors.white.withOpacity(0.05),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon — accent color preserved
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: baseColor.withOpacity(0.20),
                  ),
                  child: Icon(
                    _resolveIcon(card.iconName),
                    size: 16,
                    color: baseColor,
                  ),
                ),
                const Spacer(),
                // Title
                Text(
                  card.title.replaceAll('\n', ' '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                // Subtitle
                Text(
                  card.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.55),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 5),
                // Song count badge — accent color preserved
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: baseColor.withOpacity(0.15),
                  ),
                  child: Text(
                    '${card.songs.length} songs',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: baseColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
