import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:ninaada_music/core/helpers.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/widgets/download_indicator.dart';

/// Song row widget — matches RN SongRow exactly
/// Optional index number, image, name, artist, explicit badge, duration, menu button
class SongRow extends StatelessWidget {
  final Song song;
  final String? context;
  final bool showIdx;
  final int? idx;
  final void Function(Song song, String? ctx) onPlay;
  final void Function(Song song) onMenu;

  const SongRow({
    super.key,
    required this.song,
    this.context,
    this.showIdx = false,
    this.idx,
    required this.onPlay,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context2) {
    return GestureDetector(
      onTap: () => onPlay(song, context),
      onLongPress: () => onMenu(song),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: Row(
          children: [
            if (showIdx && idx != null)
              SizedBox(
                width: 24,
                child: Text(
                  '$idx',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF666666),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            if (showIdx) const SizedBox(width: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: safeImageUrl(song.image),
                width: 46,
                height: 46,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 46,
                  height: 46,
                  color: NinaadaColors.surfaceLight,
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 46,
                  height: 46,
                  color: NinaadaColors.surfaceLight,
                  child: const Icon(Icons.music_note, color: Color(0xFF666666)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist,
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
            if (song.explicit)
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF666666),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text(
                  'E',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            Text(
              fmt(song.duration),
              style: const TextStyle(
                color: Color(0xFF666666),
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 4),
            DownloadIndicator(songId: song.id, size: 16),
            const SizedBox(width: 2),
            GestureDetector(
              onTap: () => onMenu(song),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Icon(Icons.more_vert, size: 20, color: Color(0xFF666666)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Song card (grid) — matches RN SongCard
class SongCard extends StatelessWidget {
  final Song song;
  final String? context;
  final String? currentSongId;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const SongCard({
    super.key,
    required this.song,
    this.context,
    this.currentSongId,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context2) {
    final screenWidth = MediaQuery.of(context2).size.width;
    final cardWidth = (screenWidth - 48) / 2;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(maxWidth: cardWidth),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with play button overlay
            Stack(
              children: [
                CachedNetworkImage(
                  imageUrl: safeImageUrl(song.image),
                  width: double.infinity,
                  height: 140,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    height: 140,
                    color: NinaadaColors.surfaceLight,
                  ),
                  errorWidget: (_, __, ___) => Container(
                    height: 140,
                    color: NinaadaColors.surfaceLight,
                    child: const Icon(Icons.music_note, color: Color(0xFF666666)),
                  ),
                ),
                // Play button
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: NinaadaColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow, size: 20, color: Colors.white),
                  ),
                ),
                // Now playing indicator
                if (currentSongId == song.id)
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Row(
                      children: [
                        Container(width: 3, height: 8, color: NinaadaColors.primary,
                          margin: const EdgeInsets.only(right: 2)),
                        Container(width: 3, height: 14, color: NinaadaColors.primary,
                          margin: const EdgeInsets.only(right: 2)),
                        Container(width: 3, height: 10, color: NinaadaColors.primary),
                      ],
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Text(
                song.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal carousel — matches RN Carousel component
class CarouselSection extends StatelessWidget {
  final String? title;
  final String? action;
  final VoidCallback? onAction;
  final List<Widget> children;
  final double itemWidth;

  const CarouselSection({
    super.key,
    this.title,
    this.action,
    this.onAction,
    required this.children,
    this.itemWidth = 130,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title!,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                if (action != null)
                  GestureDetector(
                    onTap: onAction,
                    child: Text(
                      action!,
                      style: const TextStyle(
                        color: NinaadaColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (title != null) const SizedBox(height: 12),
        SizedBox(
          height: 180, // image 130 + text ~50
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            cacheExtent: 500.0,
            itemCount: children.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => children[i],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Carousel card — 130x130 image + title + subtitle
class CarouselCard extends StatelessWidget {
  final String imageUrl;
  final String name;
  final String? subtitle;
  final VoidCallback onTap;
  final bool isRound;
  final Widget? overlay;
  final VoidCallback? onLongPress;

  const CarouselCard({
    super.key,
    required this.imageUrl,
    required this.name,
    this.subtitle,
    required this.onTap,
    this.isRound = false,
    this.overlay,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(isRound ? 65 : 10),
                  child: CachedNetworkImage(
                    imageUrl: safeImageUrl(imageUrl),
                    width: 130,
                    height: 130,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        color: NinaadaColors.surfaceLight,
                        borderRadius: BorderRadius.circular(isRound ? 65 : 10),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        color: NinaadaColors.surfaceLight,
                        borderRadius: BorderRadius.circular(isRound ? 65 : 10),
                      ),
                      child: const Icon(Icons.music_note, color: Color(0xFF666666)),
                    ),
                  ),
                ),
                if (overlay != null) overlay!,
              ],
            ),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
