import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/services/download_manager.dart';

// ══════════════════════════════════════════════════
//  DOWNLOAD INDICATOR — Phase 9 Reactive Widget
// ══════════════════════════════════════════════════
//
//  Isolated ConsumerWidget so only this 24×24 area repaints
//  during download progress ticks — the parent list does NOT
//  rebuild, guaranteeing 60fps scroll performance.
//
//  States:
//    downloading → CircularProgressIndicator bound to progress
//    queued      → grey downloading icon
//    completed   → green check circle
//    failed      → red error icon (tap to retry)
//    null        → invisible (no download state)
// ══════════════════════════════════════════════════

class DownloadIndicator extends ConsumerWidget {
  final String songId;
  final double size;

  const DownloadIndicator({
    super.key,
    required this.songId,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Granular selector — only rebuilds when THIS song's record changes.
    final record = ref.watch(
      downloadProvider.select((s) => s.records[songId]),
    );

    if (record == null) return const SizedBox.shrink();

    switch (record.status) {
      case DownloadStatus.downloading:
        return SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            value: record.progress > 0 ? record.progress : null,
            strokeWidth: 2.5,
            color: NinaadaColors.primaryLight,
            backgroundColor: NinaadaColors.border,
          ),
        );

      case DownloadStatus.queued:
        return Icon(
          Icons.downloading,
          size: size,
          color: const Color(0xFF666666),
        );

      case DownloadStatus.completed:
        return Icon(
          Icons.check_circle,
          size: size,
          color: const Color(0xFF4CAF50),
        );

      case DownloadStatus.failed:
        return Icon(
          Icons.error_outline,
          size: size,
          color: const Color(0xFFFF5252),
        );
    }
  }
}
