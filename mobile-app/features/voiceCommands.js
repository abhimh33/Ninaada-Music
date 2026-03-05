import React, { useState, useCallback, useRef, useEffect } from 'react';
import {
  View, Text, TouchableOpacity, Modal, StyleSheet, TextInput,
  ToastAndroid, FlatList, ActivityIndicator, Dimensions, ScrollView,
  Image, Animated, Easing, Keyboard,
} from 'react-native';
import { MaterialIcons, Ionicons, Feather, MaterialCommunityIcons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';

const { width: SW } = Dimensions.get('window');
const API_BASE = "http://10.20.3.243:8000";

// ========== NLP COMMAND PARSER ==========
const COMMAND_PATTERNS = [
  // Play commands
  { pattern: /^play\s+(.+)/i, type: 'play', extract: (m) => ({ query: m[1] }) },
  { pattern: /^play$/i, type: 'resume', extract: () => ({}) },
  { pattern: /^resume$/i, type: 'resume', extract: () => ({}) },

  // Pause/Stop
  { pattern: /^(pause|stop)$/i, type: 'pause', extract: () => ({}) },

  // Skip/Next/Previous
  { pattern: /^(skip|next|next song)$/i, type: 'next', extract: () => ({}) },
  { pattern: /^(previous|prev|back|go back)$/i, type: 'previous', extract: () => ({}) },

  // Shuffle
  { pattern: /^shuffle\s+(.+)/i, type: 'shuffle', extract: (m) => ({ query: m[1] }) },
  { pattern: /^shuffle$/i, type: 'shuffle_toggle', extract: () => ({}) },

  // Radio
  { pattern: /^(start\s+)?radio\s+(for|from|by)?\s*(.+)/i, type: 'radio', extract: (m) => ({ query: m[3] }) },
  { pattern: /^(start\s+)?radio$/i, type: 'radio_current', extract: () => ({}) },

  // Search
  { pattern: /^(search|find|look\s+for)\s+(.+)/i, type: 'search', extract: (m) => ({ query: m[2] }) },

  // Like/Unlike
  { pattern: /^(like|love|heart)\s*(this|current|song)?$/i, type: 'like', extract: () => ({}) },
  { pattern: /^(unlike|unlove|remove\s+like)$/i, type: 'unlike', extract: () => ({}) },

  // Sleep timer
  { pattern: /^sleep\s+(?:timer\s+)?(\d+)\s*(?:min(?:utes?)?)?$/i, type: 'sleep', extract: (m) => ({ minutes: parseInt(m[1]) }) },
  { pattern: /^(cancel|stop)\s+(?:sleep\s+)?timer$/i, type: 'sleep_cancel', extract: () => ({}) },
  { pattern: /^sleep\s+after\s+(?:this\s+)?song$/i, type: 'sleep_song', extract: () => ({}) },

  // Queue
  { pattern: /^(add\s+to\s+queue|enqueue)\s+(.+)/i, type: 'add_queue', extract: (m) => ({ query: m[2] }) },
  { pattern: /^(clear|empty)\s+queue$/i, type: 'clear_queue', extract: () => ({}) },
  { pattern: /^(show|open)\s+queue$/i, type: 'show_queue', extract: () => ({}) },

  // Playlist
  { pattern: /^play\s+playlist\s+(.+)/i, type: 'play_playlist', extract: (m) => ({ name: m[1] }) },
  { pattern: /^(add\s+to|save\s+to)\s+playlist\s+(.+)/i, type: 'add_playlist', extract: (m) => ({ name: m[2] }) },
  { pattern: /^create\s+playlist\s+(.+)/i, type: 'create_playlist', extract: (m) => ({ name: m[1] }) },

  // Downloaded/Offline
  { pattern: /^(download|save)\s*(this|current|song)?$/i, type: 'download', extract: () => ({}) },
  { pattern: /^play\s+(downloads|downloaded|offline)$/i, type: 'play_downloads', extract: () => ({}) },

  // Volume
  { pattern: /^volume\s+(up|louder)$/i, type: 'volume_up', extract: () => ({}) },
  { pattern: /^volume\s+(down|quieter|softer)$/i, type: 'volume_down', extract: () => ({}) },

  // Speed
  { pattern: /^speed\s+(up|faster)$/i, type: 'speed_up', extract: () => ({}) },
  { pattern: /^(slow\s+down|speed\s+down|slower)$/i, type: 'speed_down', extract: () => ({}) },
  { pattern: /^(?:set\s+)?speed\s+(\d+(?:\.\d+)?)\s*x?$/i, type: 'set_speed', extract: (m) => ({ speed: parseFloat(m[1]) }) },

  // Lyrics
  { pattern: /^(show|open|get)\s+lyrics$/i, type: 'lyrics', extract: () => ({}) },

  // Navigate
  { pattern: /^(go\s+to|open|show)\s+(home|explore|library|player)$/i, type: 'navigate', extract: (m) => ({ tab: m[2].toLowerCase() }) },

  // Repeat
  { pattern: /^repeat\s+(on|off|one|all)$/i, type: 'repeat', extract: (m) => ({ mode: m[1].toLowerCase() }) },
  { pattern: /^repeat$/i, type: 'repeat_cycle', extract: () => ({}) },

  // What's playing
  { pattern: /^(what('s|s|\s+is)\s+playing|current\s+song|now\s+playing)$/i, type: 'whats_playing', extract: () => ({}) },

  // Mood/Genre play
  { pattern: /^play\s+(chill|party|workout|romance|sad|focus|devotional|retro)\s*(music|songs|vibes)?$/i, type: 'play_mood', extract: (m) => ({ mood: m[1].toLowerCase() }) },
  { pattern: /^play\s+(hindi|english|punjabi|tamil|telugu|kannada|marathi|bengali)\s*(music|songs)?$/i, type: 'play_genre', extract: (m) => ({ genre: m[1].toLowerCase() }) },

  // Help
  { pattern: /^(help|commands|what\s+can\s+you\s+do)$/i, type: 'help', extract: () => ({}) },
];

// ========== NORMALIZE SONG RESULT ==========
const normSong = (s) => ({
  id: s.id,
  name: s.song || s.name || s.title || '',
  artist: s.primary_artists || s.artist || s.singers || '',
  image: s.image || '',
  duration: s.duration || 240,
  media_url: s.media_url || '',
  album: s.album || '',
  language: s.language || '',
  ...s,
});

// ========== SMART SEARCH: extract search query from NLP ==========
const extractSearchQuery = (input) => {
  const trimmed = (input || '').trim();
  if (!trimmed) return null;

  // "play kannada songs" -> "kannada songs"
  const playMatch = trimmed.match(/^play\s+(.+)/i);
  if (playMatch) return playMatch[1].replace(/\s*(songs?|music|vibes)\s*$/i, '').trim() || playMatch[1];

  // "search for arijit" -> "arijit"
  const searchMatch = trimmed.match(/^(?:search|find|look\s+for)\s+(.+)/i);
  if (searchMatch) return searchMatch[1];

  // "shuffle hindi songs" -> "hindi songs"
  const shuffleMatch = trimmed.match(/^shuffle\s+(.+)/i);
  if (shuffleMatch) return shuffleMatch[1];

  // Mood -> mapped query
  const moodMatch = trimmed.match(/^(?:play\s+)?(chill|party|workout|romance|sad|focus|devotional|retro)\s*(music|songs|vibes)?$/i);
  if (moodMatch) {
    const moodQueries = {
      chill: 'chill vibes lofi', party: 'party dance hits', workout: 'workout energy pump',
      romance: 'romantic love songs', sad: 'sad heartbreak emotional', focus: 'focus study instrumental',
      devotional: 'devotional bhajan', retro: 'retro classic old hindi',
    };
    return moodQueries[moodMatch[1].toLowerCase()] || moodMatch[1];
  }

  // Genre -> mapped query
  const genreMatch = trimmed.match(/^(?:play\s+)?(hindi|english|punjabi|tamil|telugu|kannada|marathi|bengali)\s*(music|songs)?$/i);
  if (genreMatch) return `${genreMatch[1]} songs best`;

  // Fallback: use as-is
  return trimmed;
};

// ========== VOICE COMMANDS HOOK ==========
export function useVoiceCommands({
  playSong, togglePlay, playNext, playPrev, setShuffle, shuffle,
  currentSong, doSearch, toggleLike, likedSongs,
  startSleep, queue, setQueue,
  playlists, downloadedSongs, setShowSearch,
  goTab, setRepeat, repeat,
  handleDownload, setDlProgress, reloadDownloads,
  changeSpeed, playbackSpeed, soundRef,
  setSearchQ,
}) {
  const [showVoiceModal, setShowVoiceModal] = useState(false);
  const [voiceQuery, setVoiceQuery] = useState('');
  const [voiceProcessing, setVoiceProcessing] = useState(false);
  const [commandHistory, setCommandHistory] = useState([]);
  const [lastResult, setLastResult] = useState(null);
  // Voice Search state
  const [searchResults, setSearchResults] = useState([]);
  const [searchLoading, setSearchLoading] = useState(false);
  const [searchError, setSearchError] = useState('');
  const searchTimeoutRef = useRef(null);

  // ===== VOICE SEARCH: search songs by query =====
  const voiceSearchSongs = useCallback(async (query) => {
    const q = (query || '').trim();
    if (!q || q.length < 2) { setSearchResults([]); setSearchError(''); return; }

    setSearchLoading(true);
    setSearchError('');
    try {
      // Smart query extraction (NLP-aware)
      const searchQ = extractSearchQuery(q);
      if (!searchQ) { setSearchResults([]); setSearchLoading(false); return; }

      // Parallel fetch for maximum results
      const [songRes, searchRes] = await Promise.all([
        fetch(`${API_BASE}/song/?query=${encodeURIComponent(searchQ)}&limit=30`).then(r => r.json()).catch(() => []),
        fetch(`${API_BASE}/search/?query=${encodeURIComponent(searchQ)}`).then(r => r.json()).catch(() => ({})),
      ]);

      const results = [];
      const seenIds = new Set();

      // Add song-specific results
      const songArr = Array.isArray(songRes) ? songRes : [];
      songArr.forEach(s => {
        const n = normSong(s);
        if (n.id && !seenIds.has(n.id)) { results.push(n); seenIds.add(n.id); }
      });

      // Add search endpoint songs
      const searchSongs = searchRes?.data?.songs || (Array.isArray(searchRes) ? searchRes : []);
      searchSongs.forEach(s => {
        const n = normSong(s);
        if (n.id && !seenIds.has(n.id)) { results.push(n); seenIds.add(n.id); }
      });

      if (results.length === 0) {
        setSearchError(`No songs found for "${searchQ}". Try different keywords.`);
      }
      setSearchResults(results);
    } catch (e) {
      console.log('Voice search error:', e);
      setSearchError('Search failed. Please check your connection and try again.');
      setSearchResults([]);
    }
    setSearchLoading(false);
  }, []);

  // Debounced live search
  const debouncedSearch = useCallback((query) => {
    if (searchTimeoutRef.current) clearTimeout(searchTimeoutRef.current);
    searchTimeoutRef.current = setTimeout(() => {
      voiceSearchSongs(query);
    }, 400);
  }, [voiceSearchSongs]);

  // Play from voice search results
  const playFromVoiceSearch = useCallback((song, allResults) => {
    if (!song) return;
    // Set queue to all search results, play selected
    if (allResults?.length > 1) {
      setQueue(allResults.filter(s => s.media_url));
    }
    playSong(song);
    setShowVoiceModal(false);
    setVoiceQuery('');
    setSearchResults([]);
    ToastAndroid.show(`Playing: ${song.name}`, ToastAndroid.SHORT);
  }, [playSong, setQueue]);

  // Execute NLP command (for command-like inputs)
  const executeCommand = useCallback(async (input) => {
    const trimmed = (input || '').trim();
    if (!trimmed) return;

    setVoiceProcessing(true);
    let result = { success: false, message: 'Command not recognized' };

    try {
      let matched = null;
      for (const cmd of COMMAND_PATTERNS) {
        const match = trimmed.match(cmd.pattern);
        if (match) {
          matched = { type: cmd.type, data: cmd.extract(match) };
          break;
        }
      }

      if (!matched) {
        // Fallback: treat as search
        matched = { type: 'search', data: { query: trimmed } };
      }

      switch (matched.type) {
        case 'play': {
          const pl = playlists?.find(p => p.name.toLowerCase().includes(matched.data.query.toLowerCase()));
          if (pl?.songs?.length) {
            setQueue(pl.songs);
            playSong(pl.songs[0], `playlist-${pl.id}`);
            result = { success: true, message: `Playing playlist: ${pl.name}` };
          } else {
            try {
              const res = await fetch(`${API_BASE}/song/?query=${encodeURIComponent(matched.data.query)}&limit=20`);
              const data = await res.json();
              if (Array.isArray(data) && data.length > 0) {
                const songs = data.map(normSong);
                setQueue(songs);
                playSong(songs[0]);
                result = { success: true, message: `Playing: ${songs[0].name}` };
                setShowVoiceModal(false);
              } else {
                result = { success: false, message: `No results for "${matched.data.query}"` };
              }
            } catch (e) {
              result = { success: false, message: 'Search failed. Try typing the song name.' };
            }
          }
          break;
        }

        case 'resume':
          if (togglePlay) togglePlay();
          result = { success: true, message: 'Resuming playback' };
          break;

        case 'pause':
          if (togglePlay) togglePlay();
          result = { success: true, message: 'Paused' };
          break;

        case 'next':
          if (playNext) playNext();
          result = { success: true, message: 'Skipping to next' };
          break;

        case 'previous':
          if (playPrev) playPrev();
          result = { success: true, message: 'Going back' };
          break;

        case 'shuffle': {
          try {
            const res = await fetch(`${API_BASE}/song/?query=${encodeURIComponent(matched.data.query)}&limit=20`);
            const data = await res.json();
            if (Array.isArray(data) && data.length > 0) {
              const songs = data.map(normSong);
              setQueue(songs);
              setShuffle(true);
              playSong(songs[Math.floor(Math.random() * songs.length)]);
              result = { success: true, message: `Shuffling: ${matched.data.query}` };
              setShowVoiceModal(false);
            }
          } catch (e) {
            result = { success: false, message: 'Search failed' };
          }
          break;
        }

        case 'shuffle_toggle':
          setShuffle(!shuffle);
          result = { success: true, message: shuffle ? 'Shuffle off' : 'Shuffle on' };
          break;

        case 'radio':
        case 'radio_current': {
          result = { success: false, message: 'Radio feature removed' };
          break;
        }

        case 'search':
          if (setSearchQ) setSearchQ(matched.data.query);
          if (doSearch) doSearch(matched.data.query);
          if (setShowSearch) setShowSearch(true);
          setShowVoiceModal(false);
          result = { success: true, message: `Searching: ${matched.data.query}` };
          break;

        case 'like':
          if (currentSong && toggleLike) {
            toggleLike(currentSong);
            result = { success: true, message: `Liked: ${currentSong.name}` };
          } else result = { success: false, message: 'No song playing' };
          break;

        case 'unlike':
          if (currentSong && toggleLike) {
            const isLiked = likedSongs?.find(s => s.id === currentSong.id);
            if (isLiked) toggleLike(currentSong);
            result = { success: true, message: `Unliked: ${currentSong.name}` };
          }
          break;

        case 'sleep':
          if (startSleep) startSleep(matched.data.minutes);
          result = { success: true, message: `Sleep timer: ${matched.data.minutes} minutes` };
          break;

        case 'sleep_cancel':
          if (startSleep) startSleep(0);
          result = { success: true, message: 'Sleep timer cancelled' };
          break;

        case 'sleep_song':
          if (startSleep) startSleep(-1);
          result = { success: true, message: 'Stopping after this song' };
          break;

        case 'show_queue':
          result = { success: false, message: 'Queue view removed' };
          break;

        case 'clear_queue':
          if (setQueue) setQueue([]);
          result = { success: true, message: 'Queue cleared' };
          break;

        case 'add_queue': {
          try {
            const res = await fetch(`${API_BASE}/song/?query=${encodeURIComponent(matched.data.query)}`);
            const data = await res.json();
            if (Array.isArray(data) && data.length > 0) {
              const song = normSong(data[0]);
              setQueue(prev => [...prev, song]);
              result = { success: true, message: `Added to queue: ${song.name}` };
            }
          } catch (e) {}
          break;
        }

        case 'play_playlist': {
          const pl = playlists?.find(p => p.name.toLowerCase().includes(matched.data.name.toLowerCase()));
          if (pl?.songs?.length) {
            setQueue(pl.songs);
            playSong(pl.songs[0], `playlist-${pl.id}`);
            result = { success: true, message: `Playing playlist: ${pl.name}` };
            setShowVoiceModal(false);
          } else result = { success: false, message: `Playlist "${matched.data.name}" not found` };
          break;
        }

        case 'play_downloads':
          if (downloadedSongs?.length) {
            setQueue(downloadedSongs);
            playSong(downloadedSongs[0], 'downloaded');
            result = { success: true, message: 'Playing downloads' };
            setShowVoiceModal(false);
          } else result = { success: false, message: 'No downloads' };
          break;

        case 'download':
          if (currentSong && handleDownload) {
            handleDownload(currentSong, setDlProgress, reloadDownloads);
            result = { success: true, message: `Downloading: ${currentSong.name}` };
          } else result = { success: false, message: 'No song playing' };
          break;

        case 'lyrics':
          result = { success: false, message: 'Lyrics feature removed' };
          break;

        case 'navigate':
          if (goTab) goTab(matched.data.tab);
          setShowVoiceModal(false);
          result = { success: true, message: `Going to ${matched.data.tab}` };
          break;

        case 'repeat':
          if (setRepeat) {
            const mode = matched.data.mode;
            if (mode === 'on') setRepeat('all');
            else if (mode === 'off') setRepeat('off');
            else setRepeat(mode);
            result = { success: true, message: `Repeat: ${mode}` };
          }
          break;

        case 'repeat_cycle':
          if (setRepeat) {
            const modes = ['off', 'all', 'one'];
            const next = modes[(modes.indexOf(repeat) + 1) % 3];
            setRepeat(next);
            result = { success: true, message: `Repeat: ${next}` };
          }
          break;

        case 'whats_playing':
          if (currentSong) {
            result = { success: true, message: `Now playing: ${currentSong.name} by ${currentSong.artist}` };
          } else result = { success: false, message: 'Nothing is playing' };
          break;

        case 'play_mood': {
          const moodQueries = {
            chill: 'chill vibes lofi', party: 'party dance hits', workout: 'workout energy pump',
            romance: 'romantic love songs', sad: 'sad heartbreak emotional', focus: 'focus study instrumental',
            devotional: 'devotional bhajan', retro: 'retro classic old hindi',
          };
          const q = moodQueries[matched.data.mood] || matched.data.mood;
          try {
            const res = await fetch(`${API_BASE}/song/?query=${encodeURIComponent(q)}&limit=20`);
            const data = await res.json();
            if (Array.isArray(data) && data.length > 0) {
              const songs = data.map(normSong);
              setQueue(songs);
              playSong(songs[0]);
              result = { success: true, message: `Playing ${matched.data.mood} music` };
              setShowVoiceModal(false);
            }
          } catch (e) {}
          break;
        }

        case 'play_genre': {
          try {
            const res = await fetch(`${API_BASE}/browse/top-songs?language=${matched.data.genre}&limit=30`);
            const data = await res.json();
            if (data.data?.length > 0) {
              const songs = data.data.map(normSong);
              setQueue(songs);
              playSong(songs[0]);
              result = { success: true, message: `Playing ${matched.data.genre} music` };
              setShowVoiceModal(false);
            }
          } catch (e) {}
          break;
        }

        case 'speed_up':
          if (changeSpeed) {
            const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
            const idx = speeds.indexOf(playbackSpeed);
            if (idx < speeds.length - 1) changeSpeed(speeds[idx + 1]);
            result = { success: true, message: `Speed: ${speeds[Math.min(idx + 1, speeds.length - 1)]}x` };
          }
          break;

        case 'speed_down':
          if (changeSpeed) {
            const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
            const idx = speeds.indexOf(playbackSpeed);
            if (idx > 0) changeSpeed(speeds[idx - 1]);
            result = { success: true, message: `Speed: ${speeds[Math.max(idx - 1, 0)]}x` };
          }
          break;

        case 'set_speed':
          if (changeSpeed && matched.data.speed >= 0.25 && matched.data.speed <= 3) {
            changeSpeed(matched.data.speed);
            result = { success: true, message: `Speed: ${matched.data.speed}x` };
          }
          break;

        case 'volume_up':
          if (soundRef?.current) {
            const st = await soundRef.current.getStatusAsync().catch(() => ({}));
            const vol = Math.min(1, (st.volume || 0.7) + 0.2);
            await soundRef.current.setVolumeAsync(vol).catch(() => {});
            result = { success: true, message: `Volume: ${Math.round(vol * 100)}%` };
          }
          break;

        case 'volume_down':
          if (soundRef?.current) {
            const st = await soundRef.current.getStatusAsync().catch(() => ({}));
            const vol = Math.max(0, (st.volume || 0.7) - 0.2);
            await soundRef.current.setVolumeAsync(vol).catch(() => {});
            result = { success: true, message: `Volume: ${Math.round(vol * 100)}%` };
          }
          break;

        case 'help':
          result = {
            success: true,
            message: 'Try: "play [song]", "pause", "next", "shuffle [query]", "search [query]", "sleep 30", "like", "repeat", "radio [song]"'
          };
          break;

        default:
          result = { success: false, message: `Unknown command: ${trimmed}` };
      }
    } catch (e) {
      result = { success: false, message: `Error: ${e.message}` };
    }

    setCommandHistory(prev => [
      { input: trimmed, result: result.message, success: result.success, time: Date.now() },
      ...prev.slice(0, 19),
    ]);
    setLastResult(result);
    setVoiceProcessing(false);

    ToastAndroid.show(result.message, ToastAndroid.SHORT);
    return result;
  }, [playSong, togglePlay, playNext, playPrev, setShuffle, shuffle, currentSong,
      doSearch, toggleLike, likedSongs, startSleep,
      queue, setQueue, playlists, downloadedSongs, goTab,
      setRepeat, repeat, handleDownload, changeSpeed, playbackSpeed, soundRef]);

  return {
    showVoiceModal, setShowVoiceModal,
    voiceQuery, setVoiceQuery,
    voiceProcessing, commandHistory, lastResult,
    executeCommand,
    // Voice Search
    searchResults, setSearchResults,
    searchLoading, searchError,
    voiceSearchSongs, debouncedSearch,
    playFromVoiceSearch,
  };
}

// ========== ANIMATED MIC ICON ==========
function PulsingMic({ searching }) {
  const pulseAnim = useRef(new Animated.Value(1)).current;
  const glowAnim = useRef(new Animated.Value(0.3)).current;

  useEffect(() => {
    if (searching) {
      Animated.loop(
        Animated.sequence([
          Animated.timing(pulseAnim, { toValue: 1.2, duration: 600, easing: Easing.inOut(Easing.ease), useNativeDriver: true }),
          Animated.timing(pulseAnim, { toValue: 1, duration: 600, easing: Easing.inOut(Easing.ease), useNativeDriver: true }),
        ])
      ).start();
      Animated.loop(
        Animated.sequence([
          Animated.timing(glowAnim, { toValue: 0.8, duration: 600, useNativeDriver: true }),
          Animated.timing(glowAnim, { toValue: 0.3, duration: 600, useNativeDriver: true }),
        ])
      ).start();
    } else {
      pulseAnim.stopAnimation();
      glowAnim.stopAnimation();
      pulseAnim.setValue(1);
      glowAnim.setValue(0.3);
    }
  }, [searching]);

  return (
    <View style={{ alignItems: 'center', marginVertical: 16 }}>
      <Animated.View style={{
        width: 72, height: 72, borderRadius: 36,
        backgroundColor: 'rgba(29,185,84,0.15)',
        justifyContent: 'center', alignItems: 'center',
        transform: [{ scale: pulseAnim }],
        opacity: glowAnim,
        position: 'absolute',
      }} />
      <View style={{
        width: 56, height: 56, borderRadius: 28,
        backgroundColor: '#8B5CF6',
        justifyContent: 'center', alignItems: 'center',
        elevation: 6,
      }}>
        <Ionicons name="mic" size={28} color="#FFF" />
      </View>
    </View>
  );
}

// ========== VOICE SEARCH MODAL ==========
export function VoiceCommandModal({
  visible, onClose, voiceQuery, setVoiceQuery, executeCommand,
  voiceProcessing, commandHistory, lastResult,
  // Voice Search props
  searchResults = [], searchLoading = false, searchError = '',
  debouncedSearch, playFromVoiceSearch,
}) {
  const inputRef = useRef(null);

  useEffect(() => {
    if (visible) {
      setTimeout(() => inputRef.current?.focus(), 300);
    } else {
      if (setVoiceQuery) setVoiceQuery('');
    }
  }, [visible]);

  const handleTextChange = (text) => {
    setVoiceQuery(text);
    if (debouncedSearch && text.trim().length >= 2) {
      debouncedSearch(text);
    }
  };

  const handleSubmit = () => {
    const q = (voiceQuery || '').trim();
    if (!q) return;
    Keyboard.dismiss();

    // Check if it's a playback command (not search)
    const isCommand = /^(pause|stop|resume|skip|next|previous|prev|back|like|unlike|help|repeat|sleep|volume|speed|slow|shuffle$|show|open|clear|go\s+to)/i.test(q);
    if (isCommand) {
      executeCommand(q);
    } else {
      // Search for songs
      if (debouncedSearch) debouncedSearch(q);
    }
  };

  const SEARCH_SUGGESTIONS = [
    { label: 'Kannada songs', icon: 'musical-notes' },
    { label: 'Arijit Singh', icon: 'person' },
    { label: 'Hindi romantic', icon: 'heart' },
    { label: 'English party', icon: 'happy' },
    { label: 'Devotional', icon: 'flower' },
    { label: 'SPB hits', icon: 'star' },
    { label: 'AR Rahman', icon: 'person' },
    { label: 'Retro classics', icon: 'time' },
  ];

  const formatDuration = (d) => {
    const sec = parseInt(d) || 0;
    return `${Math.floor(sec / 60)}:${(sec % 60).toString().padStart(2, '0')}`;
  };

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <View style={VS.backdrop}>
        <View style={VS.modal}>
          {/* Header */}
          <View style={VS.header}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10, flex: 1 }}>
              <View style={{ width: 32, height: 32, borderRadius: 16, backgroundColor: 'rgba(29,185,84,0.2)', justifyContent: 'center', alignItems: 'center' }}>
                <Ionicons name="mic" size={18} color="#8B5CF6" />
              </View>
              <View>
                <Text style={VS.title}>Voice Search</Text>
                <Text style={{ color: '#666', fontSize: 11 }}>Search songs, artists, or type a command</Text>
              </View>
            </View>
            <TouchableOpacity onPress={onClose} style={{ padding: 4 }}>
              <MaterialIcons name="close" size={24} color="#888" />
            </TouchableOpacity>
          </View>

          {/* Search Input */}
          <View style={VS.inputRow}>
            <View style={VS.inputWrapper}>
              <Ionicons name="search" size={18} color="#666" style={{ marginLeft: 14 }} />
              <TextInput
                ref={inputRef}
                style={VS.input}
                placeholder='Try "play kannada songs" or "Arijit Singh"'
                placeholderTextColor="#555"
                value={voiceQuery}
                onChangeText={handleTextChange}
                onSubmitEditing={handleSubmit}
                returnKeyType="search"
                autoFocus
                editable={!voiceProcessing}
              />
              {voiceQuery ? (
                <TouchableOpacity onPress={() => { setVoiceQuery(''); }} style={{ padding: 8 }}>
                  <Ionicons name="close-circle" size={18} color="#666" />
                </TouchableOpacity>
              ) : null}
            </View>
            <TouchableOpacity
              style={[VS.searchBtn, (!voiceQuery?.trim() || searchLoading) && { opacity: 0.5 }]}
              onPress={handleSubmit}
              disabled={!voiceQuery?.trim() || searchLoading}
            >
              {searchLoading || voiceProcessing ? (
                <ActivityIndicator size="small" color="#FFF" />
              ) : (
                <Ionicons name="arrow-forward" size={20} color="#FFF" />
              )}
            </TouchableOpacity>
          </View>

          {/* Animated mic when searching */}
          {searchLoading && <PulsingMic searching={true} />}

          {/* Error message */}
          {searchError ? (
            <View style={VS.errorBanner}>
              <Ionicons name="alert-circle" size={16} color="#FF5252" />
              <Text style={VS.errorText}>{searchError}</Text>
            </View>
          ) : null}

          {/* Last command result */}
          {lastResult && !searchResults.length && !searchLoading && voiceProcessing === false && (
            <View style={[VS.resultBanner, { borderColor: lastResult.success ? '#8B5CF633' : '#FF525233' }]}>
              <Ionicons name={lastResult.success ? 'checkmark-circle' : 'information-circle'} size={16}
                color={lastResult.success ? '#8B5CF6' : '#FF9800'} />
              <Text style={[VS.resultText, { color: lastResult.success ? '#8B5CF6' : '#FF9800' }]}
                numberOfLines={2}>{lastResult.message}</Text>
            </View>
          )}

          {/* Search Results */}
          {searchResults.length > 0 ? (
            <View style={{ flex: 1 }}>
              <Text style={VS.sectionLabel}>
                {searchResults.length} song{searchResults.length !== 1 ? 's' : ''} found
              </Text>
              <FlatList
                data={searchResults}
                keyExtractor={(item, i) => `vs-${item.id || i}`}
                style={{ maxHeight: 400 }}
                showsVerticalScrollIndicator={false}
                keyboardShouldPersistTaps="handled"
                renderItem={({ item }) => (
                  <TouchableOpacity
                    style={VS.songRow}
                    onPress={() => playFromVoiceSearch(item, searchResults)}
                    activeOpacity={0.6}
                  >
                    <Image
                      source={{ uri: item.image || 'https://via.placeholder.com/50' }}
                      style={VS.songImg}
                    />
                    <View style={{ flex: 1, marginLeft: 12 }}>
                      <Text style={VS.songName} numberOfLines={1}>{item.name || 'Unknown'}</Text>
                      <Text style={VS.songArtist} numberOfLines={1}>{item.artist || 'Unknown Artist'}</Text>
                    </View>
                    <View style={{ alignItems: 'flex-end', gap: 2 }}>
                      {item.duration ? (
                        <Text style={VS.songDuration}>{formatDuration(item.duration)}</Text>
                      ) : null}
                      <View style={VS.playIconSmall}>
                        <Ionicons name="play" size={12} color="#8B5CF6" />
                      </View>
                    </View>
                  </TouchableOpacity>
                )}
                ItemSeparatorComponent={() => <View style={{ height: 1, backgroundColor: '#141424' }} />}
              />
            </View>
          ) : !searchLoading && !voiceQuery?.trim() ? (
            /* Suggestions when empty */
            <ScrollView showsVerticalScrollIndicator={false} keyboardShouldPersistTaps="handled">
              <Text style={VS.sectionLabel}>Try searching for</Text>
              <View style={VS.suggestionsGrid}>
                {SEARCH_SUGGESTIONS.map((s, i) => (
                  <TouchableOpacity
                    key={i}
                    style={VS.suggestionChip}
                    onPress={() => { setVoiceQuery(s.label); if (debouncedSearch) debouncedSearch(s.label); }}
                  >
                    <Ionicons name={s.icon} size={14} color="#8B5CF6" />
                    <Text style={VS.suggestionText}>{s.label}</Text>
                  </TouchableOpacity>
                ))}
              </View>

              {/* Command tips */}
              <Text style={[VS.sectionLabel, { marginTop: 16 }]}>Voice Commands</Text>
              <View style={VS.tipsContainer}>
                {[
                  { cmd: '"play kannada songs"', desc: 'Search & play songs' },
                  { cmd: '"shuffle hindi songs"', desc: 'Shuffle search results' },
                  { cmd: '"pause" / "next"', desc: 'Control playback' },
                  { cmd: '"sleep 30"', desc: 'Sleep timer in minutes' },
                ].map((tip, i) => (
                  <View key={i} style={VS.tipRow}>
                    <Text style={VS.tipCmd}>{tip.cmd}</Text>
                    <Text style={VS.tipDesc}>{tip.desc}</Text>
                  </View>
                ))}
              </View>

              {/* Recent searches */}
              {commandHistory.length > 0 && (
                <>
                  <Text style={[VS.sectionLabel, { marginTop: 16 }]}>Recent</Text>
                  <ScrollView horizontal showsHorizontalScrollIndicator={false}>
                    {commandHistory.filter(h => h.success).slice(0, 6).map((h, i) => (
                      <TouchableOpacity key={i} style={VS.recentChip}
                        onPress={() => { setVoiceQuery(h.input); if (debouncedSearch) debouncedSearch(h.input); }}>
                        <Ionicons name="time-outline" size={12} color="#888" />
                        <Text style={VS.recentText} numberOfLines={1}>{h.input}</Text>
                      </TouchableOpacity>
                    ))}
                  </ScrollView>
                </>
              )}
            </ScrollView>
          ) : null}

          {/* Help hint */}
          <View style={VS.helpHint}>
            <Ionicons name="information-circle-outline" size={14} color="#444" />
            <Text style={VS.helpText}>
              {searchResults.length > 0 ? 'Tap any song to play' : 'Type naturally \u2014 "play chill music", "Arijit Singh latest", etc.'}
            </Text>
          </View>
        </View>
      </View>
    </Modal>
  );
}

// ========== VOICE BUTTON ==========
export function VoiceButton({ onPress, size = 22, color = '#8B5CF6', style }) {
  return (
    <TouchableOpacity onPress={onPress} style={[VS.voiceBtn, style]} hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}>
      <Ionicons name="mic" size={size} color={color} />
    </TouchableOpacity>
  );
}

// ========== STYLES ==========
const VS = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.9)', justifyContent: 'flex-end' },
  modal: { backgroundColor: '#111118', borderTopLeftRadius: 24, borderTopRightRadius: 24, paddingHorizontal: 16, paddingBottom: 24, maxHeight: '90%' },
  header: { flexDirection: 'row', alignItems: 'center', paddingTop: 16, paddingBottom: 12, borderBottomWidth: 1, borderBottomColor: '#141424' },
  title: { color: '#FFF', fontSize: 16, fontWeight: '700' },
  // Input
  inputRow: { flexDirection: 'row', gap: 8, marginVertical: 12 },
  inputWrapper: { flex: 1, flexDirection: 'row', alignItems: 'center', backgroundColor: '#141424', borderRadius: 24, borderWidth: 1, borderColor: '#1e1e38' },
  input: { flex: 1, height: 48, paddingHorizontal: 10, color: '#FFF', fontSize: 14 },
  searchBtn: { width: 48, height: 48, borderRadius: 24, backgroundColor: '#8B5CF6', justifyContent: 'center', alignItems: 'center', elevation: 3 },
  // Error
  errorBanner: { flexDirection: 'row', alignItems: 'center', gap: 8, padding: 10, borderRadius: 10, borderWidth: 1, borderColor: '#FF525233', marginBottom: 8, backgroundColor: 'rgba(255,82,82,0.08)' },
  errorText: { color: '#FF5252', fontSize: 12, flex: 1 },
  // Result banner
  resultBanner: { flexDirection: 'row', alignItems: 'center', gap: 8, padding: 10, borderRadius: 10, borderWidth: 1, marginBottom: 8, backgroundColor: 'rgba(0,0,0,0.3)' },
  resultText: { fontSize: 13, fontWeight: '500', flex: 1 },
  // Section
  sectionLabel: { color: '#888', fontSize: 11, fontWeight: '600', textTransform: 'uppercase', letterSpacing: 0.8, marginBottom: 8, marginTop: 4 },
  // Song results
  songRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 10, paddingHorizontal: 4 },
  songImg: { width: 48, height: 48, borderRadius: 8, backgroundColor: '#222' },
  songName: { color: '#FFF', fontSize: 14, fontWeight: '600' },
  songArtist: { color: '#888', fontSize: 12, marginTop: 2 },
  songDuration: { color: '#666', fontSize: 10 },
  playIconSmall: { width: 24, height: 24, borderRadius: 12, backgroundColor: 'rgba(29,185,84,0.15)', justifyContent: 'center', alignItems: 'center' },
  // Suggestions grid
  suggestionsGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  suggestionChip: { flexDirection: 'row', alignItems: 'center', gap: 6, paddingHorizontal: 14, paddingVertical: 10, borderRadius: 20, backgroundColor: '#141424', borderWidth: 1, borderColor: '#1e1e38' },
  suggestionText: { color: '#CCC', fontSize: 12 },
  // Tips
  tipsContainer: { backgroundColor: '#0d0d18', borderRadius: 12, padding: 12 },
  tipRow: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 6 },
  tipCmd: { color: '#8B5CF6', fontSize: 12, fontWeight: '500', flex: 1 },
  tipDesc: { color: '#666', fontSize: 11, textAlign: 'right' },
  // Recent
  recentChip: { flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 12, paddingVertical: 8, borderRadius: 16, backgroundColor: '#141424', marginRight: 8 },
  recentText: { color: '#AAA', fontSize: 11, maxWidth: 120 },
  // Help
  helpHint: { flexDirection: 'row', alignItems: 'center', gap: 6, justifyContent: 'center', paddingTop: 12 },
  helpText: { color: '#444', fontSize: 11 },
  // Voice button
  voiceBtn: { padding: 4 },
});
