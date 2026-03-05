import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/data/api_service.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/data/user_profile.dart';
import 'package:ninaada_music/data/user_taste_profile.dart';
import 'package:ninaada_music/providers/onboarding_provider.dart';

// ════════════════════════════════════════════════════════════════
//  ONBOARDING SCREEN — Cold Start Taste Bootstrapping
// ════════════════════════════════════════════════════════════════
//
//  Two-step flow:
//    Step 1 — Pick at least 1 language (FilterChip grid)
//    Step 2 — Pick at least 3 artists (CircleAvatar grid)
//
//  On "Finish":
//    Inject affinities via TasteProfileManager.seedFromOnboarding()
//    Set hasCompletedOnboarding = true
//    pushReplacement → AppShell
//
//  "Skip" is always available to prevent forced-onboarding uninstalls.
// ════════════════════════════════════════════════════════════════

/// Language choices for onboarding Step 1.
class _LangOption {
  final String id;
  final String displayName;
  final IconData icon;
  final Color color;

  const _LangOption({
    required this.id,
    required this.displayName,
    required this.icon,
    required this.color,
  });
}

const List<_LangOption> _languages = [
  _LangOption(id: 'hindi', displayName: 'Hindi', icon: Icons.music_note, color: Color(0xFFFF6B35)),
  _LangOption(id: 'english', displayName: 'English', icon: Icons.headset, color: Color(0xFF8B5CF6)),
  _LangOption(id: 'kannada', displayName: 'Kannada', icon: Icons.audiotrack, color: Color(0xFFFFD700)),
  _LangOption(id: 'tamil', displayName: 'Tamil', icon: Icons.library_music, color: Color(0xFFFF4D6D)),
  _LangOption(id: 'telugu', displayName: 'Telugu', icon: Icons.album, color: Color(0xFF00B4D8)),
  _LangOption(id: 'punjabi', displayName: 'Punjabi', icon: Icons.queue_music, color: Color(0xFF7B2FBE)),
  _LangOption(id: 'malayalam', displayName: 'Malayalam', icon: Icons.piano, color: Color(0xFF2A9D8F)),
  _LangOption(id: 'marathi', displayName: 'Marathi', icon: Icons.music_note, color: Color(0xFFE63946)),
  _LangOption(id: 'bengali', displayName: 'Bengali', icon: Icons.queue_music, color: Color(0xFF2A9D8F)),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  final ApiService _api = ApiService();

  // Step 1 state
  final Set<String> _selectedLanguages = {};

  // Step 2 state
  final Set<String> _selectedArtists = {};
  List<ArtistBrief> _availableArtists = [];
  bool _loadingArtists = false;
  String? _artistError;
  bool _seeding = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ── Skip: complete onboarding with no data ──
  Future<void> _skip() async {
    await ref.read(onboardingProvider.notifier).completeOnboarding();
    // NinaadaApp.build() watches onboardingProvider — it will rebuild
    // and replace OnboardingScreen with _AppShell automatically.
  }

  // ── Next: move from Step 1 → Step 2, fetch artists ──
  void _goToStep2() {
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
    _fetchArtists();
  }

  // ── Back: return from Step 2 → Step 1 ──
  void _goBackToStep1() {
    _pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  // ── Fetch artists for selected languages via search API ──
  Future<void> _fetchArtists() async {
    if (_loadingArtists) return;
    setState(() {
      _loadingArtists = true;
      _artistError = null;
    });

    try {
      final Map<String, ArtistBrief> uniqueArtists = {};

      // Search for artists in each selected language
      for (final lang in _selectedLanguages) {
        try {
          final results = await _api.search('$lang songs popular');
          final artists = results['artists'] as List<ArtistBrief>? ?? [];
          for (final a in artists) {
            if (a.name.isNotEmpty && a.image.isNotEmpty) {
              uniqueArtists[a.id] = a;
            }
          }

          // Also extract unique artists from song results
          final songs = results['songs'] as List<Song>? ?? [];
          final seenArtistNames = uniqueArtists.values.map((a) => a.name.toLowerCase()).toSet();
          for (final s in songs) {
            for (final part in s.artist.split(RegExp(r'[,;]'))) {
              final name = part.trim();
              if (name.isNotEmpty && !seenArtistNames.contains(name.toLowerCase())) {
                seenArtistNames.add(name.toLowerCase());
                uniqueArtists['name_${name.hashCode}'] = ArtistBrief(
                  id: 'name_${name.hashCode}',
                  name: name,
                  image: s.image, // use the song image as fallback
                );
              }
            }
          }
        } catch (_) {
          // Continue with other languages even if one fails
        }
      }

      if (mounted) {
        setState(() {
          _availableArtists = uniqueArtists.values.toList();
          _loadingArtists = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingArtists = false;
          _artistError = 'Could not load artists. Check your connection.';
        });
      }
    }
  }

  // ── Finish: seed the taste profile and navigate out ──
  Future<void> _finish() async {
    if (_seeding) return;
    setState(() => _seeding = true);

    // Mandate 3: Safe Injection — 15.0 for language, 18.0 for artist
    final manager = TasteProfileManager.instance;
    await manager.seedFromOnboarding(
      languages: _selectedLanguages.toList(),
      artists: _selectedArtists.toList(),
      languageScore: 15.0,
      artistScore: 18.0,
    );

    // Phase 9A: Persist structured UserProfile (non-decaying, permanent)
    await ref.read(userProfileProvider.notifier).saveFromOnboarding(
      languages: _selectedLanguages.toList(),
      artistNames: _selectedArtists.toList(),
    );

    // Mark complete
    await ref.read(onboardingProvider.notifier).completeOnboarding();
    // NinaadaApp.build() watches onboardingProvider — it will rebuild
    // and replace OnboardingScreen with _AppShell automatically.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NinaadaColors.background,
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildStep1(),
            _buildStep2(),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════
  //  STEP 1: Language Selection
  // ════════════════════════════════════════════════
  Widget _buildStep1() {
    final canProceed = _selectedLanguages.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          // Header
          const Text(
            'Welcome to\nNinaada Music',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'What languages do you listen to?',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 32),
          // Language grid
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.1,
              ),
              itemCount: _languages.length,
              itemBuilder: (context, index) {
                final lang = _languages[index];
                final selected = _selectedLanguages.contains(lang.id);
                return _LanguageChip(
                  lang: lang,
                  selected: selected,
                  onTap: () {
                    setState(() {
                      if (selected) {
                        _selectedLanguages.remove(lang.id);
                      } else {
                        _selectedLanguages.add(lang.id);
                      }
                    });
                  },
                );
              },
            ),
          ),
          // Bottom buttons
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Row(
              children: [
                // Skip
                TextButton(
                  onPressed: _skip,
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 15,
                    ),
                  ),
                ),
                const Spacer(),
                // Next
                AnimatedOpacity(
                  opacity: canProceed ? 1.0 : 0.4,
                  duration: const Duration(milliseconds: 200),
                  child: ElevatedButton(
                    onPressed: canProceed ? _goToStep2 : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NinaadaColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                    ),
                    child: const Text('Next',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════
  //  STEP 2: Artist Selection
  // ════════════════════════════════════════════════
  Widget _buildStep2() {
    final canFinish = _selectedArtists.length >= 3;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          // Back arrow + Header
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios,
                    color: Colors.white, size: 20),
                onPressed: _goBackToStep1,
              ),
              const SizedBox(width: 4),
              const Expanded(
                child: Text(
                  'Pick your artists',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Text(
              'Choose at least 3 to personalize your music',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.6),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Artist grid
          Expanded(
            child: _loadingArtists
                ? _buildArtistShimmer()
                : _artistError != null
                    ? _buildArtistError()
                    : _availableArtists.isEmpty
                        ? _buildArtistEmpty()
                        : GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                              childAspectRatio: 0.75,
                            ),
                            itemCount: _availableArtists.length,
                            itemBuilder: (context, index) {
                              final artist = _availableArtists[index];
                              final selected =
                                  _selectedArtists.contains(artist.name);
                              return _ArtistTile(
                                artist: artist,
                                selected: selected,
                                onTap: () {
                                  setState(() {
                                    if (selected) {
                                      _selectedArtists.remove(artist.name);
                                    } else {
                                      _selectedArtists.add(artist.name);
                                    }
                                  });
                                },
                              );
                            },
                          ),
          ),
          // Bottom buttons
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Row(
              children: [
                TextButton(
                  onPressed: _skip,
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 15,
                    ),
                  ),
                ),
                const Spacer(),
                // Selection counter
                if (_selectedArtists.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      '${_selectedArtists.length} selected',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 13,
                      ),
                    ),
                  ),
                AnimatedOpacity(
                  opacity: canFinish ? 1.0 : 0.4,
                  duration: const Duration(milliseconds: 200),
                  child: ElevatedButton(
                    onPressed: canFinish && !_seeding ? _finish : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NinaadaColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                    ),
                    child: _seeding
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Finish',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArtistShimmer() {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.75,
      ),
      itemCount: 12,
      itemBuilder: (context, index) {
        return Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NinaadaColors.surface.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 60,
              height: 12,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: NinaadaColors.surface.withOpacity(0.5),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildArtistError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off, color: Colors.white.withOpacity(0.4), size: 48),
          const SizedBox(height: 16),
          Text(
            _artistError ?? 'Something went wrong',
            style: TextStyle(color: Colors.white.withOpacity(0.6)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _fetchArtists,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: NinaadaColors.primary.withOpacity(0.5)),
            ),
            child: const Text('Retry',
                style: TextStyle(color: NinaadaColors.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildArtistEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_search,
              color: Colors.white.withOpacity(0.4), size: 48),
          const SizedBox(height: 16),
          Text(
            'No artists found.\nTry going back and selecting different languages.',
            style: TextStyle(color: Colors.white.withOpacity(0.6)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  LANGUAGE CHIP — Step 1 selectable tile with scale animation
// ════════════════════════════════════════════════════════════════
class _LanguageChip extends StatefulWidget {
  final _LangOption lang;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageChip({
    required this.lang,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_LanguageChip> createState() => _LanguageChipState();
}

class _LanguageChipState extends State<_LanguageChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _LanguageChip old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) {
      _anim.forward().then((_) => _anim.reverse());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: widget.selected
                ? widget.lang.color.withOpacity(0.2)
                : NinaadaColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.selected
                  ? widget.lang.color
                  : NinaadaColors.border,
              width: widget.selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.lang.icon,
                color: widget.selected
                    ? widget.lang.color
                    : Colors.white.withOpacity(0.6),
                size: 28,
              ),
              const SizedBox(height: 6),
              Text(
                widget.lang.displayName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: widget.selected
                      ? Colors.white
                      : Colors.white.withOpacity(0.7),
                ),
              ),
              if (widget.selected)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(
                    Icons.check_circle,
                    color: widget.lang.color,
                    size: 16,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  ARTIST TILE — Step 2 circular avatar with selection overlay
// ════════════════════════════════════════════════════════════════
class _ArtistTile extends StatefulWidget {
  final ArtistBrief artist;
  final bool selected;
  final VoidCallback onTap;

  const _ArtistTile({
    required this.artist,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_ArtistTile> createState() => _ArtistTileState();
}

class _ArtistTileState extends State<_ArtistTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ArtistTile old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) {
      _anim.forward().then((_) => _anim.reverse());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                // Avatar
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.selected
                          ? NinaadaColors.primary
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: ClipOval(
                    child: Image.network(
                      widget.artist.image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: NinaadaColors.surface,
                        child: const Icon(Icons.person,
                            color: Colors.white54, size: 32),
                      ),
                    ),
                  ),
                ),
                // Checkmark overlay
                if (widget.selected)
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: NinaadaColors.primary.withOpacity(0.4),
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              widget.artist.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: widget.selected
                    ? Colors.white
                    : Colors.white.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
