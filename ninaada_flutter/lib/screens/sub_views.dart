import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/helpers.dart';
import 'package:ninaada_music/core/media_theme_engine.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/data/api_service.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/providers/app_providers.dart';
import 'package:ninaada_music/providers/network_provider.dart';
import 'package:ninaada_music/widgets/media_action_sheet.dart';
import 'package:ninaada_music/widgets/song_tile.dart';
import 'package:ninaada_music/widgets/song_widgets.dart';
import 'package:ninaada_music/widgets/universal_context_menu.dart';
import 'package:ninaada_music/screens/recommendation_detail_view.dart';

/// Clean up artist bio — handles JSON arrays, HTML tags, and extra brackets
String _cleanBio(String raw) {
  String text = raw.trim();
  // If it looks like JSON array '[{"text": "..."}]', parse it
  if (text.startsWith('[')) {
    try {
      final list = jsonDecode(text);
      if (list is List) {
        text = list
            .whereType<Map>()
            .map((m) => m['text']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .join(' ');
      }
    } catch (_) {
      // Not valid JSON — strip brackets manually
      text = text.replaceAll(RegExp(r'^\[|\]$'), '');
      text = text.replaceAll(RegExp(r'\{"text":\s*"'), '');
      text = text.replaceAll(RegExp(r'"\}'), '');
    }
  }
  // Strip HTML tags
  text = text.replaceAll(RegExp(r'<[^>]+>'), '');
  // Clean up any stray quotes/brackets
  text = text.replaceAll(RegExp(r'^\[?\{?"?|"?\}?\]?$'), '');
  return text.trim();
}

/// Sub-views: ArtistDetail, AlbumDetail, Credits, ViewAll, Recommendation
/// Rendered when navigationProvider.subView is set
/// Matches RN sub-view patterns pixel-perfect

class SubViewRouter extends ConsumerWidget {
  const SubViewRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(navigationProvider);
    final sub = nav.subView;
    if (sub == null) return const SizedBox.shrink();

    final type = sub['type'] as String?;
    switch (type) {
      case 'artist':
        return _ArtistDetailView(key: ValueKey('artist_${sub['id']}'), data: sub);
      case 'album':
        return _AlbumDetailView(key: ValueKey('album_${sub['id']}'), data: sub);
      case 'credits':
        return _CreditsView(data: sub);
      case 'viewAll':
        return _ViewAllGrid(data: sub);
      case 'recommendation':
        return RecommendationDetailView(data: sub);
      default:
        return const SizedBox.shrink();
    }
  }
}

// ──────────────────────────────────────────────────────
//  ARTIST DETAIL VIEW
// ──────────────────────────────────────────────────────
class _ArtistDetailView extends ConsumerStatefulWidget {
  final Map<String, dynamic> data;
  const _ArtistDetailView({super.key, required this.data});

  @override
  ConsumerState<_ArtistDetailView> createState() => _ArtistDetailViewState();
}

class _ArtistDetailViewState extends ConsumerState<_ArtistDetailView> {
  ArtistDetail? artist;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ArtistDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Safety net: if Flutter reuses state with new data, re-fetch
    if (oldWidget.data['id'] != widget.data['id']) {
      setState(() { artist = null; loading = true; });
      _load();
    }
  }

  Future<void> _load() async {
    try {
      // Check if full data was passed or just an ID
      final id = widget.data['id'] as String? ?? '';
      if (id.isEmpty && widget.data['data'] != null) {
        // Full data was passed
        setState(() {
          artist = ArtistDetail.fromJson(widget.data['data'] as Map<String, dynamic>);
          loading = false;
        });
        return;
      }
      final result = await ApiService().fetchArtist(id);
      setState(() {
        artist = result;
        loading = false;
      });
    } catch (_) {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nav = ref.read(navigationProvider.notifier);
    final player = ref.read(playerProvider.notifier);

    if (loading) {
      return const Center(child: CircularProgressIndicator(color: NinaadaColors.primary));
    }

    if (artist == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.music_off, color: Color(0xFF666666), size: 48),
            const SizedBox(height: 16),
            const Text('Could not load artist', style: TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => nav.setSubView(null),
              child: const Text('Go back', style: TextStyle(color: NinaadaColors.primary)),
            ),
          ],
        ),
      );
    }

    // If the artist has no songs, show a clean "Empty" state
    if (artist!.topSongs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(50),
              child: CachedNetworkImage(
                imageUrl: safeImageUrl(artist!.image),
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(width: 100, height: 100, color: NinaadaColors.surfaceLight, child: const Icon(Icons.person, color: Color(0xFF666666), size: 40)),
              ),
            ),
            const SizedBox(height: 16),
            Text(artist!.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Empty', style: TextStyle(color: Color(0xFF888888), fontSize: 15)),
            const SizedBox(height: 4),
            const Text('This artist has no songs available', style: TextStyle(color: Color(0xFF666666), fontSize: 13)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => nav.setSubView(null),
              child: const Text('Go back', style: TextStyle(color: NinaadaColors.primary, fontSize: 15)),
            ),
          ],
        ),
      );
    }

    final a = artist!;
    final songs = a.topSongs;
    final albums = a.topAlbums;
    final similar = a.similarArtists;

    return CustomScrollView(
      slivers: [
        // Gradient header — dynamic from media theme engine
        SliverToBoxAdapter(
          child: _AnimatedHeaderGradient(
            padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 24),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => nav.setSubView(null),
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.arrow_back, size: 24, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(60),
                  child: CachedNetworkImage(
                    imageUrl: safeImageUrl(a.image),
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(width: 120, height: 120, color: NinaadaColors.surfaceLight, child: const Icon(Icons.person, color: Color(0xFF666666), size: 40)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(a.name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                if (a.followerCount != null)
                  Text('${a.followerCount} followers', style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 13)),
              ],
            ),
          ),
        ),

        // Play / Shuffle buttons
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ActionButton(
                  icon: Icons.play_arrow,
                  label: 'Play',
                  gradient: true,
                  onTap: () {
                    if (songs.isNotEmpty) player.playSong(songs[0]);
                  },
                ),
                const SizedBox(width: 12),
                _ActionButton(
                  icon: Icons.shuffle,
                  label: 'Shuffle',
                  gradient: false,
                  onTap: () {
                    if (songs.isNotEmpty) {
                      player.setQueue(songs);
                      player.toggleShuffle();
                      player.playSong(songs[songs.length ~/ 2]);
                    }
                  },
                ),
              ],
            ),
          ),
        ),

        // Bio — clean up any remaining HTML tags or JSON artifacts
        if (a.bio != null && a.bio!.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                _cleanBio(a.bio!),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF888888), fontSize: 13, height: 1.5),
              ),
            ),
          ),

        // Top Songs
        if (songs.isNotEmpty) ...[
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Top Songs', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
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
                  enabled: isSongAvailable(network, song.id),
                  onTap: () => player.playSong(song),
                  onMenu: () => showSongActionSheet(context, ref, song),
                );
              },
              childCount: songs.length.clamp(0, 10),
            ),
          ),
        ],

        // Albums carousel
        if (albums.isNotEmpty)
          SliverToBoxAdapter(
            child: CarouselSection(
              title: 'Albums',
              children: albums.map((album) => CarouselCard(
                imageUrl: album.image,
                name: album.name,
                onTap: () => nav.setSubView({'type': 'album', 'id': album.id}),
                onLongPress: () => UniversalContextMenu.showSheet(context, ref, album),
              )).toList(),
            ),
          ),

        // Similar artists carousel
        if (similar.isNotEmpty)
          SliverToBoxAdapter(
            child: CarouselSection(
              title: 'Similar Artists',
              children: similar.map((sa) => CarouselCard(
                imageUrl: sa.image,
                name: sa.name,
                isRound: true,
                onTap: () => nav.setSubView({'type': 'artist', 'id': sa.id}),
              )).toList(),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 140)),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────
//  ALBUM DETAIL VIEW
// ──────────────────────────────────────────────────────
class _AlbumDetailView extends ConsumerStatefulWidget {
  final Map<String, dynamic> data;
  const _AlbumDetailView({super.key, required this.data});

  @override
  ConsumerState<_AlbumDetailView> createState() => _AlbumDetailViewState();
}

class _AlbumDetailViewState extends ConsumerState<_AlbumDetailView> {
  BrowseItem? album;
  List<Song> songs = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _AlbumDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data['id'] != widget.data['id']) {
      setState(() { album = null; songs = []; loading = true; });
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final id = widget.data['id'] as String? ?? '';
      final isPlaylist = widget.data['isPlaylist'] as bool? ?? false;
      final result = await ApiService().fetchAlbumOrPlaylist(id, isPlaylist: isPlaylist);

      // If API returned a broken/empty image, use the image from the home page BrowseItem
      BrowseItem? finalResult = result;
      if (result != null) {
        final resultImage = result.image;
        final passedData = widget.data['data'];
        if ((resultImage.isEmpty || !resultImage.startsWith('http'))
            && passedData is BrowseItem
            && passedData.image.startsWith('http')) {
          finalResult = BrowseItem(
            id: result.id,
            name: result.name,
            subtitle: result.subtitle,
            image: passedData.image,
            type: result.type,
            primaryArtists: result.primaryArtists,
            count: result.count,
            year: result.year,
            songs: result.songs,
          );
        }
      }

      setState(() {
        album = finalResult;
        songs = finalResult?.songs ?? [];
        loading = false;
      });
    } catch (_) {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nav = ref.read(navigationProvider.notifier);
    final player = ref.read(playerProvider.notifier);

    if (loading) {
      return const Center(child: CircularProgressIndicator(color: NinaadaColors.primary));
    }

    final name = album?.name ?? 'Album';
    final image = album?.image ?? '';
    final subtitle = album?.primaryArtists ?? album?.subtitle ?? '';
    final year = album?.year ?? '';
    final gradColors = getGradientFromId(album?.id ?? '');

    return CustomScrollView(
      slivers: [
        // Gradient header — dynamic from media theme engine
        SliverToBoxAdapter(
          child: _AnimatedHeaderGradient(
            padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 24),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => nav.setSubView(null),
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.arrow_back, size: 24, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: safeImageUrl(image),
                    width: 180,
                    height: 180,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(width: 180, height: 180, color: NinaadaColors.surfaceLight, child: const Icon(Icons.album, color: Color(0xFF666666), size: 40)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                if (subtitle.isNotEmpty)
                  Text(subtitle, style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 13), textAlign: TextAlign.center),
                if (year.isNotEmpty)
                  Text('$year · ${songs.length} songs', style: const TextStyle(color: Color(0xFF666666), fontSize: 12)),
              ],
            ),
          ),
        ),

        // Play All / Shuffle buttons
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ActionButton(
                  icon: Icons.play_arrow,
                  label: 'Play All',
                  gradient: true,
                  onTap: () {
                    if (songs.isNotEmpty) {
                      player.setQueue(songs);
                      player.playSong(songs[0]);
                    }
                  },
                ),
                const SizedBox(width: 12),
                _ActionButton(
                  icon: Icons.shuffle,
                  label: 'Shuffle',
                  gradient: false,
                  onTap: () {
                    if (songs.isNotEmpty) {
                      final shuffled = List<Song>.from(songs)..shuffle();
                      player.setQueue(shuffled);
                      player.toggleShuffle();
                      player.playSong(shuffled[0]);
                    }
                  },
                ),
              ],
            ),
          ),
        ),

        // Song list
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final song = songs[index];
              final network = ref.watch(networkProvider);
              return SongTile(
                song: song,
                index: index + 1,
                enabled: isSongAvailable(network, song.id),
                onTap: () => player.playSong(song),
                onMenu: () => showSongActionSheet(context, ref, song),
              );
            },
            childCount: songs.length,
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 140)),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────
//  CREDITS VIEW
// ──────────────────────────────────────────────────────
class _CreditsView extends ConsumerWidget {
  final Map<String, dynamic> data;
  const _CreditsView({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.read(navigationProvider.notifier);
    final song = data['data'] as Map<String, dynamic>? ?? {};

    final name = song['name'] ?? '';
    final image = song['image'] ?? '';
    final artist = song['artist'] ?? '';

    final credits = <MapEntry<String, String>>[
      if (song['album'] != null) MapEntry('Album', song['album'].toString()),
      if (song['primary_artists'] != null || song['artist'] != null)
        MapEntry('Artists', (song['primary_artists'] ?? song['artist']).toString()),
      if (song['label'] != null) MapEntry('Label', song['label'].toString()),
      if (song['year'] != null) MapEntry('Year', song['year'].toString()),
      if (song['language'] != null) MapEntry('Language', song['language'].toString()),
      if (song['duration'] != null) MapEntry('Duration', fmt(int.tryParse(song['duration'].toString()) ?? 0)),
      MapEntry('Explicit', song['explicit'] == true ? 'Yes' : 'No'),
      if (song['id'] != null) MapEntry('Song ID', song['id'].toString()),
    ];

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 140),
      child: Column(
        children: [
          // Back button
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => nav.setSubView(null),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.arrow_back, size: 24, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Song image + info
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: safeImageUrl(image),
              width: 140,
              height: 140,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(width: 140, height: 140, color: NinaadaColors.surfaceLight, child: const Icon(Icons.music_note, color: Color(0xFF666666), size: 32)),
            ),
          ),
          const SizedBox(height: 12),
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
          Text(artist, style: const TextStyle(color: Color(0xFF888888), fontSize: 14)),
          const SizedBox(height: 24),
          // Credits title
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Song Credits', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          // Credit rows
          for (final c in credits)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: NinaadaColors.border)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(c.key, style: const TextStyle(color: Color(0xFF888888), fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: Text(c.value, style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────
//  VIEW ALL GRID
// ──────────────────────────────────────────────────────
class _ViewAllGrid extends ConsumerWidget {
  final Map<String, dynamic> data;
  const _ViewAllGrid({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.read(navigationProvider.notifier);
    final title = data['title'] as String? ?? '';
    final items = (data['items'] as List?)?.cast<BrowseItem>() ?? [];

    return Column(
      children: [
        // Gradient header
        Container(
          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 18),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF3D1A8F), Color(0xFF1C1336), Color(0xFF0B0F1A)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => nav.setSubView(null),
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.arrow_back, size: 24, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 36, top: 4),
                child: Text('${items.length} items', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
              ),
            ],
          ),
        ),

        // Grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.72,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return UniversalContextMenu(
                mediaItem: item,
                child: GestureDetector(
                onTap: () => nav.setSubView({'type': 'album', 'id': item.id}),
                child: Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: safeImageUrl(item.image),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorWidget: (_, __, ___) => Container(color: NinaadaColors.surfaceLight, child: const Icon(Icons.album, color: Color(0xFF666666))),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(item.name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                    Text(item.subtitle ?? '', style: const TextStyle(color: Color(0xFF888888), fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
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

// ──────────────────────────────────────────────────────
//  Shared Action Button
// ──────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool gradient;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.gradient, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: gradient ? const Color(0xFF7C4DFF).withOpacity(0.10) : Colors.white.withOpacity(0.04),
          border: Border.all(
            color: gradient ? const Color(0xFF7C4DFF).withOpacity(0.5) : Colors.white.withOpacity(0.12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: gradient ? const Color(0xFF7C4DFF) : Colors.white.withOpacity(0.7)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: gradient ? const Color(0xFF7C4DFF) : Colors.white.withOpacity(0.7), fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// Animated gradient header that reacts to the current media theme
class _AnimatedHeaderGradient extends ConsumerWidget {
  final EdgeInsetsGeometry padding;
  final Widget child;

  const _AnimatedHeaderGradient({required this.padding, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(mediaThemeProvider.select((s) => s.palette));
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            palette.dominant,
            Color.lerp(palette.dominant, const Color(0xFF0B0F1A), 0.7)!,
            const Color(0xFF0B0F1A),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: child,
    );
  }
}
