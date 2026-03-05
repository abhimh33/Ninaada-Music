// ========== APP CONSTANTS ==========
// Mirrors all constants from the React Native codebase

import 'package:flutter/material.dart';

// API base URL — change this when deploying to production
// Local dev:   'http://10.20.3.243:8000'
// Production:  'https://miracle-of-music.onrender.com'
const String apiBase = 'https://miracle-of-music.onrender.com';

// Optional API key — set when backend has API_KEY enabled
// Leave empty string for no auth
const String apiKey = 'e96f9d0215b0d4f329c3f31d631f7f07ec5ef87a710c0d623e955aaa368729e2';

// Genre definitions matching RN GENRES array
class GenreItem {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  const GenreItem({required this.id, required this.name, required this.icon, required this.color});
}

const List<GenreItem> genres = [
  GenreItem(id: 'hindi', name: 'Bollywood', icon: Icons.music_note, color: Color(0xFFA0522D)),
  GenreItem(id: 'english', name: 'English Pop', icon: Icons.headset, color: Color(0xFF6B3FA0)),
  GenreItem(id: 'punjabi', name: 'Punjabi', icon: Icons.queue_music, color: Color(0xFF5C248C)),
  GenreItem(id: 'tamil', name: 'Tamil', icon: Icons.library_music, color: Color(0xFF9B3344)),
  GenreItem(id: 'telugu', name: 'Telugu', icon: Icons.album, color: Color(0xFF3A6B8C)),
  GenreItem(id: 'kannada', name: 'Kannada', icon: Icons.audiotrack, color: Color(0xFFB8942B)),
  GenreItem(id: 'marathi', name: 'Marathi', icon: Icons.music_note, color: Color(0xFF8B2E36)),
  GenreItem(id: 'bengali', name: 'Bengali', icon: Icons.queue_music, color: Color(0xFF2A7A6F)),
];

class MoodItem {
  final String id;
  final String name;
  final IconData icon;
  final String query;
  final Color color;
  const MoodItem({required this.id, required this.name, required this.icon, required this.query, required this.color});
}

const List<MoodItem> moods = [
  MoodItem(id: 'chill', name: 'Chill', icon: Icons.spa, query: 'chill vibes lofi', color: Color(0xFF2A7A6F)),
  MoodItem(id: 'workout', name: 'Workout', icon: Icons.fitness_center, query: 'workout energy pump', color: Color(0xFF9B3344)),
  MoodItem(id: 'party', name: 'Party', icon: Icons.celebration, query: 'party dance hits', color: Color(0xFFB8942B)),
  MoodItem(id: 'romance', name: 'Romance', icon: Icons.favorite, query: 'romantic love songs', color: Color(0xFF8C4466)),
  MoodItem(id: 'focus', name: 'Focus', icon: Icons.psychology, query: 'focus study instrumental', color: Color(0xFF6B3FA0)),
  MoodItem(id: 'sad', name: 'Sad', icon: Icons.water_drop, query: 'sad heartbreak emotional', color: Color(0xFF3A6B8C)),
  MoodItem(id: 'devotional', name: 'Devotional', icon: Icons.self_improvement, query: 'devotional bhajan', color: Color(0xFFA0522D)),
  MoodItem(id: 'retro', name: 'Retro', icon: Icons.radio, query: 'retro classic old hindi', color: Color(0xFF8B2E36)),
];

// Genre explore quotes matching RN genreQuotes
const Map<String, String> genreQuotes = {
  'hindi': 'The soul of Bollywood beats',
  'english': 'Global vibes, timeless hits',
  'punjabi': 'Feel the Punjabi energy',
  'tamil': 'Melodies from the south',
  'telugu': 'Tollywood magic',
  'kannada': 'Sandalwood serenades',
  'marathi': 'Rhythms of Maharashtra',
  'bengali': 'Poetry in every note',
  'Chill': 'Unwind and let the music flow',
  'Workout': 'Push harder, play louder',
  'Party': 'Turn up the night',
  'Romance': 'Love is in the air',
  'Focus': 'Deep focus, zero distractions',
  'Sad': 'Feel every emotion',
  'Devotional': 'Spiritual harmony',
  'Retro': 'Golden era classics',
};

// Gradient palettes matching RN PALETTES
const List<List<int>> gradientPalettes = [
  [0xFF141424, 0xFF16213E, 0xFF0F3460],
  [0xFF2D132C, 0xFF141424, 0xFF0A0A14],
  [0xFF0F4C75, 0xFF1B262C, 0xFF0A0A14],
  [0xFF3C1642, 0xFF086375, 0xFF0A0A14],
  [0xFF1E3A5F, 0xFF0A0A14, 0xFF141424],
  [0xFF2C3E50, 0xFF141424, 0xFF0A0A14],
  [0xFF4A0E4E, 0xFF141424, 0xFF0A0A14],
];

// Search suggestions matching RN
const List<String> searchSuggestions = [
  'Kannada songs', 'Arijit Singh', 'Hindi romantic', 'English party',
  'Devotional', 'SPB hits', 'AR Rahman', 'Retro classics', 'Lo-fi chill', 'Trending hits',
];

/// Time-aware Vibes strip (4 slots, refreshed on resume).
/// Morning 5-11 → Sunrise Calm, Chai Vibes
/// Afternoon 12-16 → Focus Flow, Work Mode
/// Evening 17-20 → Sunset Chill, Wine Down
/// Night 21-4 → Sleep Lofi, Midnight Jazz
List<MoodItem> getVibes() {
  final h = DateTime.now().hour;
  if (h >= 5 && h <= 11) {
    return const [
      MoodItem(id: 'sunrise_calm', name: 'Sunrise Calm', icon: Icons.wb_twilight, query: 'morning calm peaceful acoustic', color: Color(0xFFFFB347)),
      MoodItem(id: 'chai_vibes', name: 'Chai Vibes', icon: Icons.coffee, query: 'chai morning acoustic indian chill', color: Color(0xFF8D6E63)),
      MoodItem(id: 'fresh_start', name: 'Fresh Start', icon: Icons.wb_sunny, query: 'morning energy upbeat feel good', color: Color(0xFF66BB6A)),
      MoodItem(id: 'soft_morning', name: 'Soft Morning', icon: Icons.cloud, query: 'soft morning gentle piano', color: Color(0xFF90CAF9)),
    ];
  }
  if (h >= 12 && h <= 16) {
    return const [
      MoodItem(id: 'focus_flow', name: 'Focus Flow', icon: Icons.psychology, query: 'focus instrumental study concentration', color: Color(0xFF42A5F5)),
      MoodItem(id: 'work_mode', name: 'Work Mode', icon: Icons.work, query: 'work productivity beats electronic', color: Color(0xFF66BB6A)),
      MoodItem(id: 'power_lunch', name: 'Power Lunch', icon: Icons.bolt, query: 'upbeat energetic pop hits', color: Color(0xFFFFCA28)),
      MoodItem(id: 'steady_grind', name: 'Steady Grind', icon: Icons.trending_up, query: 'lofi beats study hip hop instrumental', color: Color(0xFF7E57C2)),
    ];
  }
  if (h >= 17 && h <= 20) {
    return const [
      MoodItem(id: 'sunset_chill', name: 'Sunset Chill', icon: Icons.wb_sunny, query: 'sunset chill evening vibes relaxing', color: Color(0xFFFF7043)),
      MoodItem(id: 'wine_down', name: 'Wine Down', icon: Icons.wine_bar, query: 'evening relaxing smooth jazz acoustic', color: Color(0xFFAB47BC)),
      MoodItem(id: 'golden_hour', name: 'Golden Hour', icon: Icons.filter_drama, query: 'golden hour dreamy indie', color: Color(0xFFFFB74D)),
      MoodItem(id: 'unwind', name: 'Unwind', icon: Icons.spa, query: 'unwind destress calm ambient', color: Color(0xFF26A69A)),
    ];
  }
  // Night 21-4
  return const [
    MoodItem(id: 'sleep_lofi', name: 'Sleep Lofi', icon: Icons.nightlight, query: 'sleep lofi calm night ambient', color: Color(0xFF5C6BC0)),
    MoodItem(id: 'midnight_jazz', name: 'Midnight Jazz', icon: Icons.music_note, query: 'midnight jazz smooth late night', color: Color(0xFF26A69A)),
    MoodItem(id: 'dream_state', name: 'Dream State', icon: Icons.cloud, query: 'dreamy ambient sleep relax', color: Color(0xFF7986CB)),
    MoodItem(id: 'night_drive', name: 'Night Drive', icon: Icons.directions_car, query: 'night drive electronic synthwave', color: Color(0xFFEF5350)),
  ];
}
