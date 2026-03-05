import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/widgets/media_action_sheet.dart';

// ================================================================
//  UNIVERSAL CONTEXT MENU — Omnipresent long-press action sheet
// ================================================================
//
//  Wrap ANY playable UI element (card, row, tile) with this widget
//  to automatically enable long-press → MediaActionSheet.
//
//  Usage:
//
//    // Wrap a widget with long-press context menu:
//    UniversalContextMenu(
//      mediaItem: song,           // Song, BrowseItem, or PlaylistModel
//      child: MyCardWidget(...),
//    )
//
//    // Or use the static helper for explicit 3-dot buttons:
//    IconButton(
//      icon: Icon(Icons.more_vert),
//      onPressed: () => UniversalContextMenu.showSheet(context, ref, song),
//    )
//
//  Accepts: Song | BrowseItem | PlaylistModel | MediaEntity
//  Anything else is silently ignored (no crash, no menu).
//
//  Design:
//    • ConsumerWidget — zero overhead, obtains its own WidgetRef
//    • Opaque hit testing — catches taps on empty child areas
//    • Haptic feedback on long-press for premium feel
//    • Delegates everything to the existing MediaActionSheet
// ================================================================

class UniversalContextMenu extends ConsumerWidget {
  /// The child widget to wrap with long-press support.
  final Widget child;

  /// The media item: Song, BrowseItem, PlaylistModel, or MediaEntity.
  final dynamic mediaItem;

  /// Optional callback that fires BEFORE the sheet opens.
  /// Useful for analytics or pre-processing.
  final VoidCallback? onBeforeOpen;

  const UniversalContextMenu({
    super.key,
    required this.child,
    required this.mediaItem,
    this.onBeforeOpen,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () {
        onBeforeOpen?.call();
        HapticFeedback.mediumImpact();
        _openSheet(context, ref);
      },
      child: child,
    );
  }

  void _openSheet(BuildContext context, WidgetRef ref) {
    final entity = _toEntity(mediaItem);
    if (entity == null) return;
    showMediaActionSheet(context, ref, entity);
  }

  // ════════════════════════════════════════════════
  //  STATIC HELPERS — for explicit 3-dot buttons
  // ════════════════════════════════════════════════

  /// Open the MediaActionSheet for any media item.
  /// Requires a WidgetRef — use from ConsumerWidget or Consumer builder.
  ///
  /// Accepts: Song, BrowseItem, PlaylistModel, or MediaEntity.
  static void showSheet(BuildContext context, WidgetRef ref, dynamic mediaItem) {
    final entity = _toEntity(mediaItem);
    if (entity == null) return;
    showMediaActionSheet(context, ref, entity);
  }

  /// Open the MediaActionSheet without requiring a WidgetRef.
  /// Uses the public MediaActionSheetContent (ConsumerWidget) as the
  /// builder, so it obtains its own ref internally.
  /// Safe to call from plain StatelessWidget or StatefulWidget contexts.
  static void showSheetDirect(BuildContext context, dynamic mediaItem) {
    final entity = _toEntity(mediaItem);
    if (entity == null) return;
    showMediaActionSheetDirect(context, entity);
  }

  // ════════════════════════════════════════════════
  //  INTERNAL
  // ════════════════════════════════════════════════

  /// Convert any supported type to MediaEntity.
  /// Returns null for unsupported types (no crash).
  static MediaEntity? _toEntity(dynamic item) {
    if (item is MediaEntity) return item;
    if (item is Song) return MediaEntity.fromSong(item);
    if (item is BrowseItem) return MediaEntity.fromAlbum(item);
    if (item is PlaylistModel) return MediaEntity.fromPlaylist(item);
    return null;
  }
}
