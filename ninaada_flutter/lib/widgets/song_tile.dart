import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:ninaada_music/core/helpers.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/data/models.dart';

/// Global reusable song tile — enforces strict alignment:
///
///   Row(
///     Expanded(Row(index?, artwork, title/artist)),
///     SizedBox(width: 75, Row(duration?, 3-dot icon)),
///   )
///
/// The fixed-width trailing SizedBox guarantees the 3-dot menus
/// form a perfect vertical line on the right edge of every song list.
///
/// Phase 6: [enabled] controls offline interactivity.
/// When false, tile renders at 0.4 opacity and tap shows a snackbar.
class SongTile extends StatelessWidget {
  final Song song;

  /// Optional 1-based index number shown before the artwork.
  final int? index;

  /// Whether to show the formatted duration text (e.g. "4:21").
  final bool showDuration;

  /// Padding around the entire tile. Override for contexts with
  /// different spacing (e.g. inside narrow cards).
  final EdgeInsetsGeometry padding;

  /// Called when the tile is tapped (typically plays the song).
  final VoidCallback onTap;

  /// Called when the 3-dot icon is tapped OR the tile is long-pressed.
  final VoidCallback onMenu;

  /// Optional override for long-press (defaults to [onMenu]).
  final VoidCallback? onLongPress;

  /// Phase 6: Whether this tile is interactive. When false (offline +
  /// no local file), the tile is dimmed and tap shows an offline hint.
  final bool enabled;

  const SongTile({
    super.key,
    required this.song,
    this.index,
    this.showDuration = true,
    this.padding = const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
    required this.onTap,
    required this.onMenu,
    this.onLongPress,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget tile = GestureDetector(
      onTap: enabled
          ? onTap
          : () {
              // Phase 6 Step 12: subtle offline hint
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
      onLongPress: onLongPress ?? onMenu,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            // ── LEADING: index? + artwork + title/artist ──
            Expanded(
              child: Row(
                children: [
                  if (index != null) ...[
                    SizedBox(
                      width: 24,
                      child: Text(
                        '$index',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF666666),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
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
                        child: const Icon(
                          Icons.music_note,
                          size: 16,
                          color: Color(0xFF666666),
                        ),
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
                ],
              ),
            ),
            // ── TRAILING: duration? + 3-dot menu (FIXED WIDTH) ──
            SizedBox(
              width: 75,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (showDuration)
                    Text(
                      fmt(song.duration),
                      style: const TextStyle(
                        color: Color(0xFF666666),
                        fontSize: 11,
                      ),
                    ),
                  if (showDuration) const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onMenu,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.more_vert,
                        size: 20,
                        color: Color(0xFF666666),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return enabled ? tile : Opacity(opacity: 0.4, child: tile);
  }
}
