// ========== TRACK PLAYER AUDIO SERVICE ==========
// Premium audio service wrapping react-native-track-player
// Replaces expo-av with background audio, lock screen controls, notification player

import TrackPlayer, {
  Capability,
  State,
  Event,
  useProgress,
  usePlaybackState,
  useActiveTrack,
  RepeatMode,
  AppKilledPlaybackBehavior,
} from 'react-native-track-player';

let _isSetup = false;

// ========== SETUP ==========
export async function setupTrackPlayer() {
  if (_isSetup) return;
  try {
    await TrackPlayer.setupPlayer({
      // Buffer duration in seconds
      minBuffer: 30,
      maxBuffer: 120,
      playBuffer: 5,
      backBuffer: 30,
      waitForBuffer: true,
    });

    await TrackPlayer.updateOptions({
      // What capabilities show in the notification
      capabilities: [
        Capability.Play,
        Capability.Pause,
        Capability.SkipToNext,
        Capability.SkipToPrevious,
        Capability.SeekTo,
        Capability.Stop,
      ],
      // What capabilities show on the compact notification view
      compactCapabilities: [
        Capability.Play,
        Capability.Pause,
        Capability.SkipToNext,
      ],
      // Notification styling
      notificationCapabilities: [
        Capability.Play,
        Capability.Pause,
        Capability.SkipToNext,
        Capability.SkipToPrevious,
      ],
      // Android specific — stop playback when app is swiped away from recents
      android: {
        appKilledPlaybackBehavior: AppKilledPlaybackBehavior.StopPlaybackAndRemoveNotification,
      },
      // Progress updating
      progressUpdateEventInterval: 1,
    });

    _isSetup = true;
    console.log('[TrackPlayer] Setup complete');
  } catch (e) {
    console.log('[TrackPlayer] Setup error:', e);
    // Try resetting if already initialized
    if (e.message?.includes('already been initialized')) {
      _isSetup = true;
    }
  }
}

// ========== PLAY A SONG ==========
export async function playTrack(song, positionMs = 0) {
  if (!_isSetup) await setupTrackPlayer();

  const uri = song.localUri || song.media_url;
  if (!uri) throw new Error('No media URL');

  // Reset queue and add new track
  await TrackPlayer.reset();

  const track = {
    id: song.id || `track-${Date.now()}`,
    url: uri,
    title: song.name || 'Unknown',
    artist: song.artist || 'Unknown Artist',
    artwork: song.image || undefined,
    duration: parseInt(song.duration) || 0,
    album: song.album || '',
  };

  await TrackPlayer.add(track);
  
  if (positionMs > 0) {
    await TrackPlayer.seekTo(positionMs / 1000);
  }

  await TrackPlayer.play();
}

// ========== ADD TO QUEUE ==========
export async function addToQueue(songs) {
  if (!_isSetup) await setupTrackPlayer();
  
  const tracks = songs.map(song => ({
    id: song.id || `track-${Date.now()}-${Math.random()}`,
    url: song.localUri || song.media_url || '',
    title: song.name || 'Unknown',
    artist: song.artist || 'Unknown Artist',
    artwork: song.image || undefined,
    duration: parseInt(song.duration) || 0,
    album: song.album || '',
  })).filter(t => t.url);

  await TrackPlayer.add(tracks);
}

// ========== QUEUE MANAGEMENT ==========
export async function setQueueAndPlay(songs, startIndex = 0, positionMs = 0) {
  if (!_isSetup) await setupTrackPlayer();

  await TrackPlayer.reset();

  const tracks = songs.map(song => ({
    id: song.id || `track-${Date.now()}-${Math.random()}`,
    url: song.localUri || song.media_url || '',
    title: song.name || 'Unknown',
    artist: song.artist || 'Unknown Artist',
    artwork: song.image || undefined,
    duration: parseInt(song.duration) || 0,
    album: song.album || '',
  })).filter(t => t.url);

  if (tracks.length === 0) return;

  await TrackPlayer.add(tracks);
  
  if (startIndex > 0 && startIndex < tracks.length) {
    await TrackPlayer.skip(startIndex);
  }

  if (positionMs > 0) {
    await TrackPlayer.seekTo(positionMs / 1000);
  }

  await TrackPlayer.play();
}

// ========== PLAYBACK CONTROLS ==========
export async function togglePlayback() {
  const state = await TrackPlayer.getPlaybackState();
  const playing = state.state === State.Playing;
  if (playing) {
    await TrackPlayer.pause();
  } else {
    await TrackPlayer.play();
  }
  return !playing;
}

export async function seekTo(positionSec) {
  await TrackPlayer.seekTo(positionSec);
}

export async function setRate(rate) {
  await TrackPlayer.setRate(rate);
}

export async function setVolume(vol) {
  await TrackPlayer.setVolume(vol);
}

export async function skipToNext() {
  try {
    await TrackPlayer.skipToNext();
  } catch (e) {
    // No more tracks
    console.log('[TrackPlayer] No next track');
  }
}

export async function skipToPrevious() {
  try {
    await TrackPlayer.skipToPrevious();
  } catch (e) {
    console.log('[TrackPlayer] No previous track');
  }
}

export async function stopPlayback() {
  try {
    await TrackPlayer.reset();
  } catch (e) {
    console.log('[TrackPlayer] Stop error:', e);
  }
}

export async function getPosition() {
  try {
    const { position, duration } = await TrackPlayer.getProgress();
    return { position, duration };
  } catch {
    return { position: 0, duration: 0 };
  }
}

export async function getState() {
  try {
    const state = await TrackPlayer.getPlaybackState();
    return state.state;
  } catch {
    return State.None;
  }
}

export async function setRepeatMode(mode) {
  // mode: 'off' | 'all' | 'one'
  if (mode === 'one') await TrackPlayer.setRepeatMode(RepeatMode.Track);
  else if (mode === 'all') await TrackPlayer.setRepeatMode(RepeatMode.Queue);
  else await TrackPlayer.setRepeatMode(RepeatMode.Off);
}

// ========== RADIO STREAM ==========
export async function playRadioStream(station) {
  if (!_isSetup) await setupTrackPlayer();

  await TrackPlayer.reset();

  const url = station.url || '';
  // Detect stream type from URL for proper player handling
  const isHLS = url.includes('.m3u8') || url.includes('m3u8');
  const isAAC = url.endsWith('.aac');

  const track = {
    id: `radio-${station.id || Date.now()}`,
    url: url,
    title: station.name || 'Radio',
    artist: 'Live Radio',
    artwork: undefined,
    isLiveStream: true,
    // Explicitly set type for HLS/AAC streams so TrackPlayer uses correct decoder
    ...(isHLS ? { type: 'hls' } : {}),
    // Add headers for AIR streams that may require a browser-like user-agent
    headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    },
  };

  await TrackPlayer.add(track);
  await TrackPlayer.play();
}

// ========== EXPORTS FOR HOOKS ==========
export {
  TrackPlayer,
  State,
  Event,
  useProgress,
  usePlaybackState,
  useActiveTrack,
  RepeatMode,
};
