import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/constants.dart';
import 'package:ninaada_music/core/helpers.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/providers/app_providers.dart';
import 'package:ninaada_music/providers/network_provider.dart';
import 'package:ninaada_music/widgets/media_action_sheet.dart';
import 'package:ninaada_music/widgets/skeleton_widgets.dart';
import 'package:ninaada_music/widgets/song_tile.dart';
import 'package:ninaada_music/widgets/song_widgets.dart';
import 'package:ninaada_music/widgets/universal_context_menu.dart';

/// Search overlay — full-screen search with filter tabs,
/// recent searches, search suggestions, results
/// Matches RN showSearch overlay pixel-perfect
class SearchOverlay extends ConsumerStatefulWidget {
  const SearchOverlay({super.key});

  @override
  ConsumerState<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends ConsumerState<SearchOverlay> {
  final _controller = TextEditingController();

  bool _currentFilterEmpty(SearchState s) {
    final list = s.results[s.filter] ?? [];
    return list.isEmpty;
  }

  @override
  void initState() {
    super.initState();
    // Always start fresh — clear stale results from previous session
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(searchProvider.notifier).clearResults();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSubmit() {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    ref.read(searchProvider.notifier).doSearch(q);
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchProvider);
    final hasQuery = search.query.isNotEmpty;

    return Column(
      children: [
        // Search bar area
        Padding(
          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 12, 16, 0),
          child: Column(
            children: [
              // Search bar row
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: NinaadaColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: NinaadaColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, size: 20, color: Color(0xFF888888)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              autofocus: true,
                              style: const TextStyle(color: Colors.white, fontSize: 15),
                              decoration: const InputDecoration(
                                hintText: 'Songs, artists, albums...',
                                hintStyle: TextStyle(color: Color(0xFF666666)),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(vertical: 12),
                              ),
                              onSubmitted: (_) => _onSubmit(),
                              onChanged: (val) {
                                if (val.isEmpty) {
                                  ref.read(searchProvider.notifier).clearResults();
                                } else {
                                  // Debounced live search — 400ms delay
                                  ref.read(searchProvider.notifier).debouncedSearch(val);
                                }
                              },
                            ),
                          ),
                          if (_controller.text.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _controller.clear();
                                ref.read(searchProvider.notifier).clearResults();
                                setState(() {});
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(14),
                                child: Icon(Icons.close, size: 20, color: Color(0xFF888888)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // Filter tabs
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 12),
                child: Row(
                  children: [
                    for (final f in ['songs', 'albums', 'artists'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () {
                            ref.read(searchProvider.notifier).setFilter(f);
                            if (_controller.text.isNotEmpty) _onSubmit();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: search.filter == f ? const Color(0xFF7C4DFF).withOpacity(0.18) : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: search.filter == f ? const Color(0xFF7C4DFF).withOpacity(0.4) : NinaadaColors.border,
                              ),
                            ),
                            child: Text(
                              f[0].toUpperCase() + f.substring(1),
                              style: TextStyle(
                                color: search.filter == f ? const Color(0xFF7C4DFF) : const Color(0xFF888888),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Loading (shimmer skeleton)
        if (search.searching)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: SongListSkeleton(count: 6),
          ),

        // Initial view (recent + suggestions) — wrapped in Expanded to prevent overflow
        if (!search.searching && _controller.text.isEmpty && !hasQuery)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Recent searches
                  if (search.recentSearches.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Recent Searches', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                              GestureDetector(
                                onTap: () => ref.read(searchProvider.notifier).clearRecentSearches(),
                                child: const Text('Clear', style: TextStyle(color: NinaadaColors.primary, fontSize: 13)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          for (final q in search.recentSearches)
                            GestureDetector(
                              onTap: () {
                                _controller.value = TextEditingValue(
                                  text: q,
                                  selection: TextSelection.collapsed(offset: q.length),
                                );
                                ref.read(searchProvider.notifier).doSearch(q);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  children: [
                                    const Icon(Icons.history, size: 18, color: Color(0xFF666666)),
                                    const SizedBox(width: 10),
                                    Text(q, style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 14)),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                  // Search suggestions
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Try Searching For', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: searchSuggestions.map((sug) {
                            return GestureDetector(
                              onTap: () {
                                _controller.value = TextEditingValue(
                                  text: sug,
                                  selection: TextSelection.collapsed(offset: sug.length),
                                );
                                ref.read(searchProvider.notifier).doSearch(sug);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7C4DFF).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFF7C4DFF).withOpacity(0.25)),
                                ),
                                child: Text(sug, style: const TextStyle(color: Color(0xFF7C4DFF), fontSize: 13, fontWeight: FontWeight.w500)),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Search results — only show when there's an active query
        if (!search.searching && hasQuery) ...[
          // Songs results
          if (search.filter == 'songs' && (search.results['songs'] ?? []).isNotEmpty)
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 140),
                itemCount: (search.results['songs'] as List).length.clamp(0, 20),
                itemBuilder: (context, index) {
                  final song = (search.results['songs'] as List)[index] as Song;
                  final network = ref.watch(networkProvider);
                  return SongTile(
                    song: song,
                    enabled: isSongAvailable(network, song.id),
                    onTap: () => ref.read(playerProvider.notifier).playSong(song),
                    onMenu: () => showSongActionSheet(context, ref, song),
                  );
                },
              ),
            ),

          // Albums results
          if (search.filter == 'albums' && (search.results['albums'] ?? []).isNotEmpty)
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 140),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.75,
                ),
                itemCount: (search.results['albums'] as List).length,
                itemBuilder: (context, index) {
                  final album = (search.results['albums'] as List)[index] as BrowseItem;
                  return UniversalContextMenu(
                    mediaItem: album,
                    child: GestureDetector(
                    onTap: () {
                      ref.read(navigationProvider.notifier).setSubView({'type': 'album', 'id': album.id});
                      ref.read(navigationProvider.notifier).toggleSearch(false);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: safeImageUrl(album.image),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorWidget: (_, __, ___) => Container(color: NinaadaColors.surfaceLight, child: const Icon(Icons.album, color: Color(0xFF666666))),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(album.name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                        Text(album.subtitle ?? '', style: const TextStyle(color: Color(0xFF888888), fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                  );
                },
              ),
            ),

          // Artists results
          if (search.filter == 'artists' && (search.results['artists'] ?? []).isNotEmpty)
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 140),
                itemCount: (search.results['artists'] as List).length,
                itemBuilder: (context, index) {
                  final raw = (search.results['artists'] as List)[index];
                  final String name;
                  final String image;
                  final String artistId;
                  if (raw is ArtistBrief) {
                    name = raw.name;
                    image = raw.image;
                    artistId = raw.id;
                  } else if (raw is Map) {
                    name = (raw['name'] ?? '').toString();
                    image = (raw['image'] ?? '').toString();
                    artistId = (raw['id'] ?? '').toString();
                  } else {
                    name = '';
                    image = '';
                    artistId = '';
                  }
                  return GestureDetector(
                    onTap: () {
                      ref.read(navigationProvider.notifier).setSubView({'type': 'artist', 'id': artistId});
                      ref.read(navigationProvider.notifier).toggleSearch(false);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(25),
                            child: CachedNetworkImage(
                              imageUrl: safeImageUrl(image),
                              width: 46,
                              height: 46,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: NinaadaColors.surfaceLight,
                                ),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: NinaadaColors.surfaceLight,
                                ),
                                child: const Icon(Icons.person, color: Color(0xFF666666), size: 20),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name.isNotEmpty ? name : 'Unknown Artist', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                                const Text('Artist', style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 18, color: Color(0xFF666666)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          // Empty state — no results for current filter
          if (_currentFilterEmpty(search))
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search_off, size: 48, color: Colors.white.withOpacity(0.3)),
                    const SizedBox(height: 12),
                    Text(
                      'No ${search.filter} found',
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 15),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Try a different search term',
                      style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () {
                        ref.read(searchProvider.notifier).doSearch(search.query);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: NinaadaColors.primary.withOpacity(0.5)),
                        ),
                        child: const Text('Retry', style: TextStyle(color: NinaadaColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}
