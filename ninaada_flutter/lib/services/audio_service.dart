// ================================================================
//  DEPRECATED — Replaced by NinaadaAudioHandler
// ================================================================
//
//  The old AudioService singleton wrapper has been replaced by
//  NinaadaAudioHandler which integrates:
//
//  ● audio_service (BaseAudioHandler) — OS media session
//    → Lock screen controls, notification player
//    → Audio focus, background execution
//  ● ConcatenatingAudioSource — gapless/seamless track transitions
//    → Pre-buffers next track while current plays
//    → Zero-latency transitions within a queue
//
//  Migration:
//    OLD: AudioService().playTrack(song)
//    NEW: ref.read(audioHandlerProvider).playSong(song)
//
//    OLD: AudioService().stop()
//    NEW: ref.read(audioHandlerProvider).stop()
//
//  The audioHandlerProvider is initialized in main.dart via
//  AudioService.init<NinaadaAudioHandler>() and overridden in ProviderScope.
//
//  See: lib/services/ninaada_audio_handler.dart
// ================================================================

// Re-export handler for convenience
export 'ninaada_audio_handler.dart';
