// ========== TRACK PLAYER PLAYBACK SERVICE ==========
// This runs as an Android foreground service for background audio + notification controls
import TrackPlayer, { Event } from 'react-native-track-player';

module.exports = async function () {
  // Remote controls from notification / lock screen / bluetooth
  TrackPlayer.addEventListener(Event.RemotePlay, () => TrackPlayer.play());
  TrackPlayer.addEventListener(Event.RemotePause, () => TrackPlayer.pause());
  TrackPlayer.addEventListener(Event.RemoteStop, () => TrackPlayer.stop());
  TrackPlayer.addEventListener(Event.RemoteNext, () => TrackPlayer.skipToNext());
  TrackPlayer.addEventListener(Event.RemotePrevious, () => TrackPlayer.skipToPrevious());

  // Seek from notification (e.g. Android 13+ seek bar)
  TrackPlayer.addEventListener(Event.RemoteSeek, (event) => {
    TrackPlayer.seekTo(event.position);
  });

  // Duck audio when phone call / notification sound
  TrackPlayer.addEventListener(Event.RemoteDuck, async (event) => {
    if (event.paused) {
      await TrackPlayer.pause();
    } else if (event.permanent) {
      await TrackPlayer.stop();
    } else {
      await TrackPlayer.setVolume(event.ducking ? 0.3 : 1.0);
    }
  });
};
