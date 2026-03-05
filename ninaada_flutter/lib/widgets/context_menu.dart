import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/providers/app_providers.dart';
import 'package:share_plus/share_plus.dart';

/// Context menu overlay — matches RN ContextMenu
/// Shows song name/artist header + Add to Playlist, Speed, Share, Download, Credits options
class ContextMenuOverlay extends ConsumerWidget {
  final Song? song;
  final VoidCallback onClose;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onShowSpeed;
  final VoidCallback onDownload;
  final VoidCallback onShowCredits;

  const ContextMenuOverlay({
    super.key,
    required this.song,
    required this.onClose,
    required this.onAddToPlaylist,
    required this.onShowSpeed,
    required this.onDownload,
    required this.onShowCredits,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (song == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black.withOpacity(0.6),
        child: Center(
          child: GestureDetector(
            onTap: () {}, // Prevent tap-through
            child: Container(
              width: MediaQuery.of(context).size.width * 0.82,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF141428),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: NinaadaColors.primary.withOpacity(0.12),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    song!.artist,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _CtxOption(
                    icon: Icons.playlist_add,
                    label: 'Add to Playlist',
                    onTap: () {
                      onClose();
                      onAddToPlaylist();
                    },
                  ),
                  _CtxOption(
                    icon: Icons.speed,
                    label: 'Speed',
                    onTap: () {
                      onClose();
                      onShowSpeed();
                    },
                  ),
                  _CtxOption(
                    icon: Icons.share,
                    label: 'Share',
                    onTap: () {
                      Share.share('${song!.name} by ${song!.artist} — Ninaada Music');
                      onClose();
                    },
                  ),
                  _CtxOption(
                    icon: Icons.file_download,
                    label: 'Download',
                    onTap: () {
                      onClose();
                      onDownload();
                    },
                  ),
                  _CtxOption(
                    icon: Icons.info_outline,
                    label: 'Song Credits',
                    onTap: () {
                      onClose();
                      onShowCredits();
                    },
                    isLast: true,
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: onClose,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: NinaadaColors.border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
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
  }
}

class _CtxOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isLast;

  const _CtxOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(
                  bottom: BorderSide(
                    color: NinaadaColors.surfaceLight,
                    width: 1,
                  ),
                ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF888888)),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

/// Playlist picker modal — matches RN PlaylistPicker
class PlaylistPickerSheet extends ConsumerStatefulWidget {
  final Song? song;
  
  const PlaylistPickerSheet({super.key, this.song});

  @override
  ConsumerState<PlaylistPickerSheet> createState() => _PlaylistPickerSheetState();
}

class _PlaylistPickerSheetState extends ConsumerState<PlaylistPickerSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);

    return Container(
      decoration: BoxDecoration(
        color: NinaadaColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: NinaadaColors.primary.withOpacity(0.1),
        ),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Add to Playlist',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, size: 24, color: NinaadaColors.primary),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: NinaadaColors.border),
          // New playlist row
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: NinaadaColors.surfaceLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: NinaadaColors.border),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'New playlist...',
                        hintStyle: TextStyle(color: Color(0xFF666666)),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    if (_controller.text.trim().isEmpty || widget.song == null) return;
                    ref.read(libraryProvider.notifier).createPlaylist(_controller.text.trim());
                    // Add song to new playlist
                    final playlists = ref.read(libraryProvider).playlists;
                    if (playlists.isNotEmpty) {
                      ref.read(libraryProvider.notifier).addToPlaylist(
                        widget.song!,
                        playlists.last.id,
                      );
                    }
                    _controller.clear();
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: NinaadaColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Create',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Playlist list
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: library.playlists.length,
              itemBuilder: (context, index) {
                final pl = library.playlists[index];
                return GestureDetector(
                  onTap: () {
                    if (widget.song != null) {
                      ref.read(libraryProvider.notifier).addToPlaylist(widget.song!, pl.id);
                    }
                    Navigator.pop(context);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: NinaadaColors.surfaceLight),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.library_music, size: 22, color: NinaadaColors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            pl.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${pl.songs.length}',
                          style: const TextStyle(
                            color: Color(0xFF888888),
                            fontSize: 13,
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
    );
  }
}
