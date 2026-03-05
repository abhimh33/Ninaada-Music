import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:ninaada_music/core/theme.dart';

// ================================================================
//  SHIMMER SKELETON WIDGETS
//  Single Shimmer wrapper per skeleton list — avoids per-element
//  Shimmer overhead and stays well under 60fps budget.
// ================================================================

/// Reusable bone shape — a rounded rectangle in the shimmer base color.
class _Bone extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const _Bone({
    required this.width,
    required this.height,
    this.borderRadius = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white, // actual colour comes from Shimmer
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

// ================================================================
//  SONG TILE SKELETON — matches SongRow (46×46 image, 2 text bars)
// ================================================================

/// A single phantom SongRow.  Use inside [SongListSkeleton].
class _SongTileBone extends StatelessWidget {
  const _SongTileBone();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        children: [
          // Album art placeholder
          const _Bone(width: 46, height: 46, borderRadius: 8),
          const SizedBox(width: 12),
          // Text lines
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _Bone(width: 160, height: 12), // title
                SizedBox(height: 8),
                _Bone(width: 100, height: 10), // artist
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Duration placeholder
          const _Bone(width: 28, height: 10),
        ],
      ),
    );
  }
}

/// Full shimmer-wrapped list of song tile skeletons.
/// Uses a SINGLE [Shimmer.fromColors] wrapper for efficiency.
class SongListSkeleton extends StatelessWidget {
  final int count;
  const SongListSkeleton({super.key, this.count = 8});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: NinaadaColors.surfaceLight,
      highlightColor: NinaadaColors.border,
      child: Column(
        children: List.generate(count, (_) => const _SongTileBone()),
      ),
    );
  }
}

// ================================================================
//  CAROUSEL SKELETON — matches CarouselCard (130×130 + text)
// ================================================================

/// A single phantom CarouselCard.
class _CarouselCardBone extends StatelessWidget {
  final bool isRound;
  const _CarouselCardBone({this.isRound = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Bone(
            width: 130,
            height: 130,
            borderRadius: isRound ? 65 : 10,
          ),
          const SizedBox(height: 8),
          const _Bone(width: 90, height: 10),
          const SizedBox(height: 4),
          const _Bone(width: 60, height: 8),
        ],
      ),
    );
  }
}

/// Shimmer-wrapped horizontal carousel of card skeletons.
class CarouselSkeleton extends StatelessWidget {
  final int count;
  final bool isRound;
  const CarouselSkeleton({super.key, this.count = 4, this.isRound = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section title bone
        Shimmer.fromColors(
          baseColor: NinaadaColors.surfaceLight,
          highlightColor: NinaadaColors.border,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _Bone(width: 120, height: 14),
          ),
        ),
        const SizedBox(height: 12),
        // Horizontal card row
        SizedBox(
          height: 178, // 130 image + 8 + 10 + 4 + 8 + padding
          child: Shimmer.fromColors(
            baseColor: NinaadaColors.surfaceLight,
            highlightColor: NinaadaColors.border,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: count,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) => _CarouselCardBone(isRound: isRound),
            ),
          ),
        ),
      ],
    );
  }
}

// ================================================================
//  ALBUM GRID SKELETON — matches search result grid (2 columns)
// ================================================================

class _AlbumGridCellBone extends StatelessWidget {
  const _AlbumGridCellBone();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const _Bone(width: 80, height: 10),
        const SizedBox(height: 4),
        const _Bone(width: 50, height: 8),
      ],
    );
  }
}

/// Shimmer-wrapped 2-column grid of album/playlist card skeletons.
class AlbumGridSkeleton extends StatelessWidget {
  final int count;
  const AlbumGridSkeleton({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: NinaadaColors.surfaceLight,
      highlightColor: NinaadaColors.border,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.75,
        ),
        itemCount: count,
        itemBuilder: (_, __) => const _AlbumGridCellBone(),
      ),
    );
  }
}

// ================================================================
//  HOME SCREEN SKELETON — combined song list + carousels
// ================================================================

/// Full-page skeleton for the home screen cold-start state.
/// Shows a song list skeleton + two carousel skeletons.
class HomeScreenSkeleton extends StatelessWidget {
  const HomeScreenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        SizedBox(height: 8),
        SongListSkeleton(count: 5),
        SizedBox(height: 24),
        CarouselSkeleton(count: 4),
        SizedBox(height: 24),
        CarouselSkeleton(count: 4, isRound: true),
      ],
    );
  }
}
