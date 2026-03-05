import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/helpers.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/providers/app_providers.dart';
import 'package:ninaada_music/providers/network_provider.dart';
import 'package:ninaada_music/services/download_manager.dart';
import 'package:ninaada_music/widgets/media_action_sheet.dart';

// ================================================================
//  QUEUE BOTTOM SHEET — Interactive drag-and-swipe queue viewer
// ================================================================
//
//  Entry point:  showQueueBottomSheet(context)
//
//  Features:
//  ● ReorderableListView.builder with custom drag handles
//  ● Dismissible swipe-to-delete (endToStart)
//  ● Current song highlighted with accent color
//  ● Tap any row to jump to that song
//  ● ValueKey(song.id) for safe reorder + dismiss
//  ● Riverpod-driven — rebuilds on every queue mutation
//
//  Data flow:
//    User drag → PlayerNotifier.reorderQueue()
//                → NinaadaAudioHandler._reorderQueueImpl()
//                  → _songs.move + _playlist.move (mutex-locked)
//                → QueueManager.reorder() → new QueueSnapshot
//
//    User swipe → PlayerNotifier.removeFromQueue()
//                → NinaadaAudioHandler._removeFromQueueImpl()
//                  → _songs.removeAt + _playlist.removeAt (mutex-locked)
//                → QueueManager.removeAt() → new QueueSnapshot
// ================================================================

/// Show the queue as a modal bottom sheet.
void showQueueBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const QueueBottomSheet(),
  );
}

class QueueBottomSheet extends ConsumerStatefulWidget {
  const QueueBottomSheet({super.key});

  @override
  ConsumerState<QueueBottomSheet> createState() => _QueueBottomSheetState();
}

class _QueueBottomSheetState extends ConsumerState<QueueBottomSheet> {
  final ScrollController _scrollController = ScrollController();
  int? _lastCurrentIndex;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final network = ref.watch(networkProvider);
    final isOffline = network == NetworkStatus.offline;
    final queue = playerState.queue;
    final currentIndex = playerState.queueSnapshot.currentIndex;
    final autoPlayStart = playerState.queueSnapshot.effectiveAutoPlayStart;
    final shuffleEnabled = playerState.shuffle;
    final shuffleIndices = playerState.shuffleIndices;

    // ── Shuffle-aware projection ──
    // When shuffle is ON, project the queue in shuffle playback order
    // starting from the current song. When OFF, show full source order.
    List<Song> visibleQueue;
    List<int> sourceIndices; // maps visible index → source index

    if (shuffleEnabled && shuffleIndices != null && shuffleIndices.isNotEmpty) {
      // Find where currentIndex sits in the shuffle order
      final shuffledPos = shuffleIndices.indexOf(currentIndex);
      if (shuffledPos >= 0) {
        // Show from current position onwards in shuffle order
        final projected = shuffleIndices.sublist(shuffledPos);
        visibleQueue = projected
            .where((i) => i >= 0 && i < queue.length)
            .map((i) => queue[i])
            .toList();
        sourceIndices = projected.where((i) => i >= 0 && i < queue.length).toList();
      } else {
        // Fallback: show full queue
        visibleQueue = queue;
        sourceIndices = List.generate(queue.length, (i) => i);
      }
    } else {
      visibleQueue = queue;
      sourceIndices = List.generate(queue.length, (i) => i);
    }

    // ── Auto-scroll to current song when sheet opens ──
    // (no continuous scroll-to-0 — let user scroll freely)

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          decoration: BoxDecoration(
            color: NinaadaColors.surface.withOpacity(0.78),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag pill ──
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: NinaadaColors.textTertiary.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // ── Header ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(
                  Icons.queue_music_rounded,
                  color: NinaadaColors.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  shuffleEnabled ? 'Shuffle Queue' : 'Up Next',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (shuffleEnabled) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.shuffle_rounded,
                      color: NinaadaColors.primary, size: 16),
                ],
                const Spacer(),
                Text(
                  shuffleEnabled
                      ? '${visibleQueue.length} songs'
                      : autoPlayStart < queue.length
                          ? '$autoPlayStart queued \u2022 ${queue.length - autoPlayStart} autoplay'
                          : '${queue.length} songs',
                  style: const TextStyle(
                    color: NinaadaColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Divider(
            color: NinaadaColors.border.withOpacity(0.5),
            height: 1,
            indent: 20,
            endIndent: 20,
          ),

          // ── Queue list ──
          if (visibleQueue.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(
                    Icons.music_off_rounded,
                    color: NinaadaColors.textTertiary,
                    size: 40,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Queue is empty',
                    style: TextStyle(
                      color: NinaadaColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ReorderableListView.builder(
                scrollController: _scrollController,
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                proxyDecorator: _proxyDecorator,
                // ── Disable reorder when shuffle is active ──
                onReorder: shuffleEnabled
                    ? (_, __) {} // no-op (can't be null)
                    : (oldIndex, newIndex) {
                        ref.read(playerProvider.notifier).reorderQueue(
                              oldIndex,
                              newIndex,
                            );
                      },
                itemCount: visibleQueue.length,
                itemBuilder: (context, index) {
                  final song = visibleQueue[index];
                  final srcIdx = sourceIndices[index];
                  final isCurrent = srcIdx == currentIndex;
                  final isAutoPlayBoundary = !shuffleEnabled &&
                      srcIdx == autoPlayStart &&
                      autoPlayStart < queue.length;

                  // ── Phase 6, Step 4: Offline disable for remote-only songs ──
                  final songAvailable = !isOffline ||
                      DownloadManager().isDownloaded(song.id);

                  Widget tile = Dismissible(
                    key: ValueKey('dismiss_${song.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      decoration: BoxDecoration(
                        color: NinaadaColors.error.withOpacity(0.15),
                        border: Border(
                          bottom: BorderSide(
                            color: NinaadaColors.border.withOpacity(0.3),
                          ),
                        ),
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        color: NinaadaColors.error,
                        size: 24,
                      ),
                    ),
                    onDismissed: (_) {
                      ref.read(playerProvider.notifier).removeFromQueue(srcIdx);
                    },
                    child: Material(
                      color: Colors.transparent,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOut,
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? NinaadaColors.primary.withOpacity(0.06)
                              : Colors.transparent,
                          border: isCurrent
                              ? const Border(
                                  left: BorderSide(
                                    color: NinaadaColors.primary,
                                    width: 4,
                                  ),
                                )
                              : null,
                        ),
                        child: InkWell(
                        onTap: songAvailable
                            ? () {
                                // Jump to this song via its source index
                                final handler = ref.read(audioHandlerProvider);
                                handler.seekToIndex(srcIdx);
                              }
                            : () {
                                // Step 12: Subtle snackbar on disabled song tap
                                ScaffoldMessenger.of(context)
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(const SnackBar(
                                    content: Text('Download to play offline',
                                        style: TextStyle(color: Colors.white, fontSize: 13)),
                                    backgroundColor: Color(0xFF1A1A2E),
                                    behavior: SnackBarBehavior.floating,
                                    duration: Duration(seconds: 2),
                                  ));
                              },
                        onLongPress: () => showSongActionSheet(context, ref, song),
                        splashColor: NinaadaColors.primary.withOpacity(0.1),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              // ── Now-playing indicator or index ──
                              SizedBox(
                                width: 28,
                                child: isCurrent
                                    ? const Icon(
                                        Icons.equalizer_rounded,
                                        color: NinaadaColors.primary,
                                        size: 18,
                                      )
                                    : Text(
                                        '${index + 1}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: NinaadaColors.textTertiary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 10),

                              // ── Album art ──
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: safeImageUrl(song.image),
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(
                                    width: 44,
                                    height: 44,
                                    color: NinaadaColors.surfaceLight,
                                  ),
                                  errorWidget: (_, __, ___) => Container(
                                    width: 44,
                                    height: 44,
                                    color: NinaadaColors.surfaceLight,
                                    child: const Icon(
                                      Icons.music_note,
                                      color: NinaadaColors.textTertiary,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // ── Song info ──
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      song.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isCurrent
                                            ? NinaadaColors.primary
                                            : Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      song.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isCurrent
                                            ? NinaadaColors.primaryLight
                                                .withOpacity(0.7)
                                            : NinaadaColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // ── Drag handle — hidden when shuffle is active or song unavailable offline ──
                              if (!shuffleEnabled && songAvailable)
                                ReorderableDragStartListener(
                                  index: index,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Icon(
                                      Icons.drag_handle_rounded,
                                      color: isCurrent
                                          ? NinaadaColors.primaryLight
                                          : NinaadaColors.textTertiary,
                                      size: 22,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      ),
                    ),
                  );

                  // ── Phase 6: Opacity dim for unavailable songs ──
                  final wrappedTile = songAvailable
                      ? tile
                      : Opacity(opacity: 0.4, child: tile);

                  // ── Phase 7: RepaintBoundary per queue item for scroll perf ──
                  final boundedTile = RepaintBoundary(child: wrappedTile);

                  // ── Autoplay boundary divider (only in normal order) ──
                  if (!isAutoPlayBoundary) {
                    return KeyedSubtree(
                      key: ValueKey(song.id),
                      child: boundedTile,
                    );
                  }
                  return KeyedSubtree(
                    key: ValueKey(song.id),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── "Autoplay" header ──
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: NinaadaColors.primary.withOpacity(0.3),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                color: NinaadaColors.primary.withOpacity(0.7),
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Autoplay \u2022 Similar Songs',
                                style: TextStyle(
                                  color:
                                      NinaadaColors.primary.withOpacity(0.7),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        boundedTile,
                      ],
                    ),
                  );
                },
              ),
            ),

          // ── Bottom safe area ──
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),       // Column
      ),       // Container
      ),       // BackdropFilter
    );         // ClipRRect
  }

  /// Proxy decorator for the dragged item — elevated with accent glow.
  static Widget _proxyDecorator(
    Widget child,
    int index,
    Animation<double> animation,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final elevation = Tween<double>(begin: 0, end: 8).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeInOut),
        );
        return Material(
          elevation: elevation.value,
          color: const Color(0xFF1A1A30),
          shadowColor: NinaadaColors.primary.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          child: child,
        );
      },
      child: child,
    );
  }
}
