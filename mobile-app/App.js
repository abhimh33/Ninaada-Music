import React, { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import {
  View, Text, TextInput, FlatList, TouchableOpacity, Image, ScrollView,
  StyleSheet, ActivityIndicator, Modal, Alert, BackHandler, Dimensions,
  Pressable, Share, AppState, Animated, Linking, ToastAndroid, StatusBar,
  Platform, Easing, SectionList, InteractionManager
} from 'react-native';
import { MaterialIcons, FontAwesome, Ionicons, Feather, MaterialCommunityIcons } from '@expo/vector-icons';
import AsyncStorage from '@react-native-async-storage/async-storage';
import {
  setupTrackPlayer, playTrack, togglePlayback as tpToggle,
  seekTo as tpSeekTo, setRate as tpSetRate,
  stopPlayback, TrackPlayer, State, Event,
  useProgress, usePlaybackState,
} from './services/audioService';
import { File, Directory, Paths } from 'expo-file-system';
import { LinearGradient } from 'expo-linear-gradient';

// ========== FEATURE IMPORTS ==========
import { useOfflineMode } from './features/offlineMode';
import { useRecommendations, MadeForYouSection, TopPicksSection } from './features/recommendations';
import { useSleepAlarm, EnhancedSleepTimerModal, AmbientDimOverlay } from './features/sleepAlarm';
import { useLibraryManager } from './features/libraryManager';
import { useRadioStations, RadioTabContent } from './features/radioStations';

// ========== CONFIG ==========
const API_BASE = "http://10.20.3.243:8000";
const { width: SW, height: SH } = Dimensions.get('window');

// ========== HELPERS ==========
const dedupe = (arr) => {
  const s = new Set();
  return (arr || []).filter(i => { if (!i?.id || s.has(i.id)) return false; s.add(i.id); return true; });
};
let _uc = 0;
const uid = (s) => ({ ...s, _uid: s._uid || `${s.id}-${++_uc}` });
const fmt = (sec) => { const m = Math.floor(sec / 60), s = Math.floor(sec % 60); return `${m}:${s < 10 ? '0' : ''}${s}`; };
const norm = (s) => ({
  id: s.id, name: s.song || s.name || s.title || 'Unknown',
  artist: s.primary_artists || s.artist || s.subtitle || 'Unknown Artist',
  image: s.image || 'https://via.placeholder.com/150',
  duration: s.duration || 240, media_url: s.media_url || '',
  album: s.album || '', year: s.year || '', language: s.language || '',
  label: s.label || '', explicit: s.explicit_content === 1, ...s,
});

// ========== DOWNLOAD HANDLER ==========
const handleDownload = async (song, setProgress, onDone, setActiveDownloads) => {
  try {
    if (!song?.media_url) { Alert.alert('Error', 'No media URL'); return; }
    // Check internet connectivity with timeout
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 5000);
      await fetch('https://clients3.google.com/generate_204', { method: 'HEAD', signal: controller.signal });
      clearTimeout(timer);
    } catch (netErr) {
      if (setActiveDownloads) setActiveDownloads(prev => ({ ...prev, [song.id]: { song, status: 'failed', error: 'No internet connection. Connect to internet and retry.' } }));
      else ToastAndroid.show('No internet connection', ToastAndroid.LONG);
      return;
    }
    ToastAndroid.show(`Download started: ${song.name}`, ToastAndroid.SHORT);
    if (setActiveDownloads) setActiveDownloads(prev => ({ ...prev, [song.id]: { song, status: 'downloading', error: null } }));
    const safe = (song.name || 'song').replace(/[^a-z0-9.\-_]/gi, '_');
    const dir = new Directory(Paths.document, 'NinaadaDownloads');
    if (!dir.exists) dir.create();
    if (setProgress) setProgress({ song: song.name, pct: 0 });
    const dl = await File.downloadFileAsync(song.media_url, new File(dir, `${safe}.mp3`));
    if (dl?.exists) {
      const stored = JSON.parse(await AsyncStorage.getItem('downloadedSongs') || '[]');
      const upd = [...stored.filter(s => s.id !== song.id), { ...song, localUri: dl.uri, downloadedAt: new Date().toISOString() }];
      await AsyncStorage.setItem('downloadedSongs', JSON.stringify(upd));
      if (setProgress) setProgress(null);
      if (setActiveDownloads) setActiveDownloads(prev => { const n = { ...prev }; delete n[song.id]; return n; });
      if (onDone) onDone();
      ToastAndroid.show(`Download completed: ${song.name}`, ToastAndroid.SHORT);
    } else {
      if (setProgress) setProgress(null);
      if (setActiveDownloads) setActiveDownloads(prev => ({ ...prev, [song.id]: { song, status: 'failed', error: 'Download failed. Tap retry.' } }));
      else ToastAndroid.show(`Download failed: ${song.name}`, ToastAndroid.LONG);
    }
  } catch (e) {
    if (setProgress) setProgress(null);
    if (setActiveDownloads) setActiveDownloads(prev => ({ ...prev, [song.id]: { song, status: 'failed', error: e.message || 'Download failed. Tap retry.' } }));
    else ToastAndroid.show(`Download failed: ${e.message}`, ToastAndroid.LONG);
  }
};

// ========== GRADIENT COLORS FROM IMAGE (simulated) ==========
const PALETTES = [
  ['#141424', '#16213e', '#0f3460'],
  ['#2d132c', '#141424', '#0a0a14'],
  ['#0f4c75', '#1b262c', '#0a0a14'],
  ['#3c1642', '#086375', '#0a0a14'],
  ['#1e3a5f', '#0a0a14', '#141424'],
  ['#2c3e50', '#141424', '#0a0a14'],
  ['#4a0e4e', '#141424', '#0a0a14'],
];
const getGradient = (id) => PALETTES[(id || '').split('').reduce((a, c) => a + c.charCodeAt(0), 0) % PALETTES.length];

// ========== DYNAMIC COLOR EXTRACTION FROM IMAGE ==========
const COLOR_CACHE = {};
const extractDominantColor = async (imageUrl) => {
  if (!imageUrl) return { bg: ['#1a1a2e', '#0a0a14', '#12121f'], accent: '#8B5CF6' };
  if (COLOR_CACHE[imageUrl]) return COLOR_CACHE[imageUrl];
  
  // Generate visually rich colors from image URL hash  
  const hash = imageUrl.split('').reduce((a, c, i) => {
    const ch = c.charCodeAt(0);
    return ((a << 5) - a + ch * (i + 1)) | 0;
  }, 0);
  const abs = Math.abs(hash);
  
  // Create HSL-based colors for rich cinematic gradients
  const hue1 = abs % 360;
  const hue2 = (hue1 + 30 + (abs % 40)) % 360;
  const sat = 40 + (abs % 30);  // 40-70% saturation
  const light1 = 12 + (abs % 10); // dark: 12-22%
  const light2 = 6 + (abs % 6);   // darker: 6-12%
  
  const hslToHex = (h, s, l) => {
    s /= 100; l /= 100;
    const f = (n) => { const k = (n + h / 30) % 12; return l - s * Math.min(l, 1 - l) * Math.max(-1, Math.min(k - 3, 9 - k, 1)); };
    const toHex = (x) => Math.round(x * 255).toString(16).padStart(2, '0');
    return `#${toHex(f(0))}${toHex(f(8))}${toHex(f(4))}`;
  };
  
  const c1 = hslToHex(hue1, sat, light1);
  const c2 = hslToHex(hue2, sat - 10, light2);
  const c3 = '#0a0a14';
  const accent = hslToHex(hue1, Math.min(sat + 20, 80), 55);
  
  const result = { bg: [c1, c2, c3], accent };
  COLOR_CACHE[imageUrl] = result;
  return result;
};

// ========== CONSTANTS (module-level for stable references) ==========
const GENRES = [
  { id: 'hindi', name: 'Bollywood', icon: 'music-note', color: '#FF6B35' },
  { id: 'english', name: 'English Pop', icon: 'headset', color: '#8B5CF6' },
  { id: 'punjabi', name: 'Punjabi', icon: 'queue-music', color: '#7B2FBE' },
  { id: 'tamil', name: 'Tamil', icon: 'library-music', color: '#FF4D6D' },
  { id: 'telugu', name: 'Telugu', icon: 'album', color: '#00B4D8' },
  { id: 'kannada', name: 'Kannada', icon: 'audiotrack', color: '#FFD700' },
  { id: 'marathi', name: 'Marathi', icon: 'music-note', color: '#E63946' },
  { id: 'bengali', name: 'Bengali', icon: 'queue-music', color: '#2A9D8F' },
];

const MOODS = [
  { id: 'chill', name: 'Chill', icon: 'spa', q: 'chill vibes lofi', color: '#2A9D8F' },
  { id: 'workout', name: 'Workout', icon: 'fitness-center', q: 'workout energy pump', color: '#FF4D6D' },
  { id: 'party', name: 'Party', icon: 'celebration', q: 'party dance hits', color: '#FFD700' },
  { id: 'romance', name: 'Romance', icon: 'favorite', q: 'romantic love songs', color: '#FF6B9D' },
  { id: 'focus', name: 'Focus', icon: 'psychology', q: 'focus study instrumental', color: '#8B5CF6' },
  { id: 'sad', name: 'Sad', icon: 'water-drop', q: 'sad heartbreak emotional', color: '#00B4D8' },
  { id: 'devotional', name: 'Devotional', icon: 'self-improvement', q: 'devotional bhajan', color: '#FF6B35' },
  { id: 'retro', name: 'Retro', icon: 'radio', q: 'retro classic old hindi', color: '#E63946' },
];

// ========== MEMOIZED COMPONENTS (outside App for React.memo to work) ==========
const SongRow = React.memo(({ song, ctx, showIdx, idx, onPlay, onMenu }) => (
  <TouchableOpacity style={S.songRow} onPress={() => onPlay(song, ctx)} onLongPress={() => onMenu(song)}>
    {showIdx && <Text style={S.songIdx}>{idx}</Text>}
    <Image source={{ uri: song.image }} style={S.songRowImg} fadeDuration={0} />
    <View style={{ flex: 1 }}>
      <Text style={S.songRowName} numberOfLines={1}>{song.name}</Text>
      <Text style={S.songRowArtist} numberOfLines={1}>{song.artist}</Text>
    </View>
    {song.explicit && <View style={S.explicitBadge}><Text style={S.explicitText}>E</Text></View>}
    <Text style={S.songRowDur}>{fmt(parseInt(song.duration || 0))}</Text>
    <TouchableOpacity onPress={() => onMenu(song)} hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}>
      <MaterialIcons name="more-vert" size={20} color="#666" />
    </TouchableOpacity>
  </TouchableOpacity>
));

const Carousel = React.memo(({ data, renderItem, title, action, onAction }) => (
  <View style={{ marginBottom: 20 }}>
    {title && (
      <View style={[S.secHeader, { paddingHorizontal: 16 }]}>
        <Text style={S.secTitle}>{title}</Text>
        {action && <TouchableOpacity onPress={onAction}><Text style={S.secAction}>{action}</Text></TouchableOpacity>}
      </View>
    )}
    <FlatList data={data} horizontal showsHorizontalScrollIndicator={false}
      renderItem={renderItem} keyExtractor={(i, idx) => `${i.id || idx}-${idx}`}
      contentContainerStyle={{ paddingHorizontal: 16 }}
      removeClippedSubviews initialNumToRender={4} maxToRenderPerBatch={3} windowSize={5} />
  </View>
));

// ======================== MAIN APP ========================
export default function App() {
  // === NAV STATE ===
  const [tab, setTab] = useState('home');
  const [navStack, setNavStack] = useState(['home']);
  const [subView, setSubView] = useState(null); // { type: 'artist'|'album'|'radio'|'credits', data }

  // === SEARCH ===
  const [searchQ, setSearchQ] = useState('');
  const [searchFilter, setSearchFilter] = useState('songs'); // songs|albums|artists
  const [searchResults, setSearchResults] = useState({ songs: [], albums: [], artists: [] });
  const [searching, setSearching] = useState(false);
  const [recentSearches, setRecentSearches] = useState([]);
  const [showSearch, setShowSearch] = useState(false);

  // === BROWSE/HOME ===
  const [trending, setTrending] = useState([]);
  const [featured, setFeatured] = useState([]);
  const [newReleases, setNewReleases] = useState([]);
  const [topSongs, setTopSongs] = useState([]);
  const [quickPicks, setQuickPicks] = useState([]);
  const [homeLoading, setHomeLoading] = useState(true);

  // === EXPLORE ===
  const [selectedGenre, setSelectedGenre] = useState(null);
  const [genreSongs, setGenreSongs] = useState([]);
  const [genreLoading, setGenreLoading] = useState(false);

  // === PLAYER ===
  const [currentSong, setCurrentSong] = useState(null);
  const [isPlaying, setIsPlaying] = useState(false);
  // sound state removed — TrackPlayer manages audio natively
  const [progress, setProgress] = useState(0);
  const [duration, setDuration] = useState(0);
  const [curTime, setCurTime] = useState('0:00');
  const [dynamicColors, setDynamicColors] = useState({ bg: ['#1a1a2e', '#0a0a14', '#12121f'], accent: '#8B5CF6' });
  const bgFadeAnim = useRef(new Animated.Value(1)).current;
  const [durTime, setDurTime] = useState('0:00');
  const [shuffle, setShuffle] = useState(false);
  const [repeat, setRepeat] = useState('off'); // off|all|one
  const [autoPlay, setAutoPlay] = useState(true);
  const [playbackSpeed, setPlaybackSpeed] = useState(1.0);
  const [showSpeedModal, setShowSpeedModal] = useState(false);
  const [miniPlayerVisible, setMiniPlayerVisible] = useState(false);

  // === QUEUE ===
  const [queue, setQueue] = useState([]);
  const [queueCtx, setQueueCtx] = useState(null);

  // === LIBRARY ===
  const [likedSongs, setLikedSongs] = useState([]);
  const [playlists, setPlaylists] = useState([]);
  const [downloadedSongs, setDownloadedSongs] = useState([]);
  const [recentlyPlayed, setRecentlyPlayed] = useState([]);
  const [playCounts, setPlayCounts] = useState({});
  const [libraryTab, setLibraryTab] = useState('playlists'); // playlists|downloads|liked
  const [selectedPlaylist, setSelectedPlaylist] = useState(null);
  const [newPlaylistName, setNewPlaylistName] = useState('');
  const playlistInputRef = useRef(null);

  // === SLEEP TIMER (managed by useSleepAlarm hook) ===

  // === DOWNLOAD ===
  const [dlProgress, setDlProgress] = useState(null);
  const [activeDownloads, setActiveDownloads] = useState({}); // { [songId]: { song, status, error } }

  // === MENUS ===
  const [menuSong, setMenuSong] = useState(null);
  const [showMenu, setShowMenu] = useState(false);
  const [showPlaylistPicker, setShowPlaylistPicker] = useState(false);

  // === CREDITS ===
  const [showCredits, setShowCredits] = useState(false);

  // === REFS ===
  const soundRef = useRef(null);
  const curSongRef = useRef(null);
  const queueRef = useRef([]);
  const repeatRef = useRef('off');
  const shuffleRef = useRef(false);
  const autoPlayRef = useRef(true);
  const queueCtxRef = useRef(null);
  const isPlayingRef = useRef(false);
  const lockRef = useRef(false);
  const autoAdvRef = useRef(false);
  const intervalRef = useRef(null);
  const appState = useRef(AppState.currentState);
  const quickPicksDone = useRef(false);
  const playSongRef = useRef(null); // Will be synced after playSong is defined

  // === TRACKPLAYER HOOKS ===
  const trackProgress = useProgress(750);
  const playbackState = usePlaybackState();

  // === SYNC REFS ===
  useEffect(() => { curSongRef.current = currentSong; }, [currentSong]);
  
  // === DYNAMIC COLOR EXTRACTION ON SONG CHANGE ===
  useEffect(() => {
    if (currentSong?.image) {
      // Fade out, extract colors, fade in
      Animated.timing(bgFadeAnim, { toValue: 0, duration: 150, useNativeDriver: true }).start(async () => {
        const colors = await extractDominantColor(currentSong.image);
        setDynamicColors(colors);
        Animated.timing(bgFadeAnim, { toValue: 1, duration: 350, easing: Easing.out(Easing.cubic), useNativeDriver: true }).start();
      });
    }
  }, [currentSong?.id]);
  useEffect(() => { queueRef.current = queue; }, [queue]);
  useEffect(() => { repeatRef.current = repeat; }, [repeat]);
  useEffect(() => { shuffleRef.current = shuffle; }, [shuffle]);
  useEffect(() => { autoPlayRef.current = autoPlay; }, [autoPlay]);
  useEffect(() => { queueCtxRef.current = queueCtx; }, [queueCtx]);
  useEffect(() => { isPlayingRef.current = isPlaying; }, [isPlaying]);

  // ===================== FEATURE HOOKS =====================

  // 1. Offline Mode & Smart Downloads
  const offline = useOfflineMode({
    likedSongs, downloadedSongs, setDownloadedSongs, setDlProgress,
    reloadDownloads: async () => { const d = await AsyncStorage.getItem('downloadedSongs'); if (d) setDownloadedSongs(JSON.parse(d)); },
    soundRef,
  });

  // 2. AI Recommendations
  const reco = useRecommendations({ recentlyPlayed, likedSongs, playCounts, playlists });

  // 3. Enhanced Sleep Timer & Alarm
  const sleep = useSleepAlarm({ soundRef, isPlaying, setIsPlaying, currentSong, playlists, playSongRef });
  const sleepActive = sleep.sleepActive;
  const sleepRemaining = sleep.sleepRemaining;
  const sleepEndOfSong = sleep.sleepEndOfSong;
  const sleepEndRef = sleep.sleepEndRef;
  const showSleepModal = sleep.showSleepModal;
  const setShowSleepModal = sleep.setShowSleepModal;

  // 4. Radio Stations
  const radio = useRadioStations({ isPlaying, setIsPlaying, setCurrentSong });

  const libMgr = useLibraryManager({
    playlists, setPlaylists, downloadedSongs, setDownloadedSongs,
    likedSongs, setLikedSongs, playCounts,
  });

  // ===================== INIT =====================
  useEffect(() => {
    initAudio();
    InteractionManager.runAfterInteractions(() => {
      loadAll();
    });
  }, []);

  const loadAll = async () => {
    try {
      const [ls, pl, dl, rp, pc, rs] = await Promise.all([
        AsyncStorage.getItem('likedSongs'),
        AsyncStorage.getItem('playlists'),
        AsyncStorage.getItem('downloadedSongs'),
        AsyncStorage.getItem('recentlyPlayed'),
        AsyncStorage.getItem('playCounts'),
        AsyncStorage.getItem('recentSearches'),
      ]);
      if (ls) setLikedSongs(JSON.parse(ls));
      if (pl) setPlaylists(JSON.parse(pl));
      if (dl) setDownloadedSongs(JSON.parse(dl));
      if (rp) setRecentlyPlayed(JSON.parse(rp));
      if (pc) setPlayCounts(JSON.parse(pc));
      if (rs) setRecentSearches(JSON.parse(rs));
      // Restore playback speed
      const savedSpeed = await AsyncStorage.getItem('playbackSpeed');
      if (savedSpeed) setPlaybackSpeed(parseFloat(savedSpeed));
    } catch (e) { console.log('Load error:', e); }
    fetchHome();
  };

  const initAudio = async () => {
    try {
      await setupTrackPlayer();
      // Bridge object: lets hooks (sleepAlarm, voiceCommands) use soundRef seamlessly
      soundRef.current = {
        pauseAsync: () => TrackPlayer.pause(),
        playAsync: () => TrackPlayer.play(),
        setVolumeAsync: (vol) => TrackPlayer.setVolume(vol),
        stopAsync: () => TrackPlayer.pause(),
        unloadAsync: () => TrackPlayer.reset(),
        getStatusAsync: async () => {
          const st = await TrackPlayer.getPlaybackState();
          const prog = await TrackPlayer.getProgress();
          return {
            isLoaded: st.state !== State.None && st.state !== State.Error,
            isPlaying: st.state === State.Playing,
            positionMillis: prog.position * 1000,
            durationMillis: prog.duration * 1000,
          };
        },
        setRateAsync: (rate) => TrackPlayer.setRate(rate),
        setPositionAsync: (ms) => TrackPlayer.seekTo(ms / 1000),
      };
    } catch (e) { console.log('Audio init error:', e); }
  };

  // ===================== BACK HANDLER =====================
  useEffect(() => {
    const handler = BackHandler.addEventListener('hardwareBackPress', () => {
      if (libMgr?.showSortModal) { libMgr.setShowSortModal(false); return true; }
      if (showMenu) { setShowMenu(false); return true; }
      if (libMgr?.multiSelectMode) { libMgr.setMultiSelectMode(false); libMgr.clearSelection(); return true; }
      if (selectedGenre) { setSelectedGenre(null); setGenreSongs([]); return true; }
      if (subView) { setSubView(null); return true; }
      if (showSearch) { setShowSearch(false); return true; }
      if (selectedPlaylist) { setSelectedPlaylist(null); return true; }
      if (navStack.length > 1) {
        const ns = navStack.slice(0, -1);
        setNavStack(ns); setTab(ns[ns.length - 1]); return true;
      }
      return false;
    });
    return () => handler.remove();
  }, [navStack, subView, showSearch, selectedPlaylist, showMenu, selectedGenre, libMgr?.showSortModal, libMgr?.multiSelectMode]);

  // ===================== APP STATE =====================
  useEffect(() => {
    const sub = AppState.addEventListener('change', async (s) => {
      if (s === 'active' && soundRef.current && isPlayingRef.current) {
        soundRef.current.playAsync().catch(() => {});
      }
      // Save playback position when going to background
      if (s === 'background' && curSongRef.current && soundRef.current) {
        try {
          const st = await soundRef.current.getStatusAsync();
          if (st.isLoaded) {
            const saved = JSON.parse(await AsyncStorage.getItem('savedPositions') || '{}');
            saved[curSongRef.current.id] = st.positionMillis;
            await AsyncStorage.setItem('savedPositions', JSON.stringify(saved));
          }
        } catch {}
      }
    });
    return () => sub.remove();
  }, []);

  // ===================== HOME DATA =====================
  const fetchHome = async () => {
    setHomeLoading(true);
    try {
      // Load cached data first for instant display
      const [cTrend, cFeat, cNew, cTop] = await Promise.all([
        AsyncStorage.getItem('cache_trending'),
        AsyncStorage.getItem('cache_featured'),
        AsyncStorage.getItem('cache_newReleases'),
        AsyncStorage.getItem('cache_topSongs'),
      ]);
      if (cTrend) setTrending(JSON.parse(cTrend));
      if (cFeat) setFeatured(JSON.parse(cFeat));
      if (cNew) setNewReleases(JSON.parse(cNew));
      if (cTop) setTopSongs(JSON.parse(cTop));
      if (cTrend || cFeat || cNew || cTop) setHomeLoading(false);

      // Fetch fresh data in background
      const [tRes, fRes, nRes, tsRes] = await Promise.all([
        fetch(`${API_BASE}/browse/trending`).then(r => r.json()).catch(() => ({})),
        fetch(`${API_BASE}/browse/featured`).then(r => r.json()).catch(() => ({})),
        fetch(`${API_BASE}/browse/new-releases`).then(r => r.json()).catch(() => ({})),
        fetch(`${API_BASE}/browse/top-songs?language=hindi&limit=20`).then(r => r.json()).catch(() => ({})),
      ]);
      const tData = tRes.data && Array.isArray(tRes.data) ? tRes.data : [];
      const fData = fRes.data && Array.isArray(fRes.data) ? fRes.data : [];
      const nData = nRes.data && Array.isArray(nRes.data) ? nRes.data : [];
      const tsData = (tsRes.data && Array.isArray(tsRes.data) ? tsRes.data : []).map(norm);
      if (tData.length) { setTrending(tData); AsyncStorage.setItem('cache_trending', JSON.stringify(tData)).catch(() => {}); }
      if (fData.length) { setFeatured(fData); AsyncStorage.setItem('cache_featured', JSON.stringify(fData)).catch(() => {}); }
      if (nData.length) { setNewReleases(nData); AsyncStorage.setItem('cache_newReleases', JSON.stringify(nData)).catch(() => {}); }
      if (tsData.length) { setTopSongs(tsData); AsyncStorage.setItem('cache_topSongs', JSON.stringify(tsData)).catch(() => {}); }
    } catch (e) { console.log('Home fetch error:', e); }
    setHomeLoading(false);
  };

  // ===================== SEARCH =====================
  const doSearch = async (q) => {
    if (!q?.trim()) return;
    setSearching(true);
    try {
      // Parallel fetch: general search + song-specific + fuzzy variations for more results
      const fuzzyQ = q.trim().split(/\s+/).map(w => w.length > 3 ? w.slice(0, -1) : w).join(' ');
      const [searchRes, songRes, fuzzyRes] = await Promise.all([
        fetch(`${API_BASE}/search/?query=${encodeURIComponent(q)}`).then(r => r.json()).catch(() => ({})),
        fetch(`${API_BASE}/song/?query=${encodeURIComponent(q)}&limit=30`).then(r => r.json()).catch(() => []),
        q !== fuzzyQ ? fetch(`${API_BASE}/song/?query=${encodeURIComponent(fuzzyQ)}&limit=15`).then(r => r.json()).catch(() => []) : Promise.resolve([]),
      ]);
      const data = searchRes;
      if (data.data) {
        // Merge song-specific results for more results
        const searchSongs = (data.data.songs || []).map(norm);
        const extraSongs = (Array.isArray(songRes) ? songRes : []).map(norm);
        const fuzzySongs = (Array.isArray(fuzzyRes) ? fuzzyRes : []).map(norm);
        const allSongs = [...searchSongs];
        const seenIds = new Set(allSongs.map(s => s.id));
        extraSongs.forEach(s => { if (!seenIds.has(s.id)) { allSongs.push(s); seenIds.add(s.id); } });
        fuzzySongs.forEach(s => { if (!seenIds.has(s.id)) { allSongs.push(s); seenIds.add(s.id); } });
        setSearchResults({
          songs: allSongs,
          albums: data.data.albums || [],
          artists: data.data.artists || [],
        });
      } else if (Array.isArray(data)) {
        setSearchResults({ songs: data.map(norm), albums: [], artists: [] });
      } else {
        // Use song-specific results + fuzzy as fallback
        const fallback = [...(Array.isArray(songRes) ? songRes : []).map(norm)];
        const seenFb = new Set(fallback.map(s => s.id));
        (Array.isArray(fuzzyRes) ? fuzzyRes : []).map(norm).forEach(s => { if (!seenFb.has(s.id)) { fallback.push(s); seenFb.add(s.id); } });
        setSearchResults({ songs: fallback, albums: [], artists: [] });
      }
      // Save recent search
      const updated = [q, ...recentSearches.filter(s => s !== q)].slice(0, 10);
      setRecentSearches(updated);
      await AsyncStorage.setItem('recentSearches', JSON.stringify(updated));
    } catch (e) {
      // Fallback to song search
      try {
        const res = await fetch(`${API_BASE}/song/?query=${encodeURIComponent(q)}`);
        const data = await res.json();
        setSearchResults({ songs: (Array.isArray(data) ? data : []).map(norm), albums: [], artists: [] });
      } catch (e2) { console.log('Search error:', e2); }
    }
    setSearching(false);
  };

  const searchByFilter = async (q, filter) => {
    if (!q?.trim()) return;
    setSearching(true);
    try {
      let url = `${API_BASE}/search/?query=${encodeURIComponent(q)}`;
      if (filter === 'albums') url = `${API_BASE}/search/albums?query=${encodeURIComponent(q)}`;
      if (filter === 'artists') url = `${API_BASE}/search/artists?query=${encodeURIComponent(q)}`;
      const res = await fetch(url);
      const data = await res.json();
      if (filter === 'songs') {
        const songs = data.data?.songs || (Array.isArray(data) ? data : []);
        setSearchResults(p => ({ ...p, songs: songs.map(norm) }));
      } else if (filter === 'albums') {
        setSearchResults(p => ({ ...p, albums: data.data || (Array.isArray(data) ? data : []) }));
      } else if (filter === 'artists') {
        setSearchResults(p => ({ ...p, artists: data.data || (Array.isArray(data) ? data : []) }));
      }
    } catch (e) { console.log('Filter search error:', e); }
    setSearching(false);
  };

  // ===================== PLAYBACK =====================
  const playSong = async (song, ctx = null, autoAdv = false) => {
    if (!song || lockRef.current) return;
    lockRef.current = true;
    try {
      // === KILL ALL AUDIO FIRST (radio + song) ===
      await radio.killAllAudio();
      await radio.stopStation();
      setIsPlaying(false);

      const uri = song.localUri || song.media_url;
      if (!uri) { Alert.alert('Error', 'No media URL'); return; }

      addRecent(song);
      incPlayCount(song);

      const s = uid({ ...song });
      setCurrentSong(s);
      setIsPlaying(false);
      setProgress(0); setCurTime('0:00');

      if (ctx) {
        setQueueCtx(ctx);
        if (ctx === 'liked') setQueue(likedSongs);
        else if (ctx === 'downloaded') setQueue(downloadedSongs);
        else if (ctx?.startsWith('playlist-')) {
          const pl = playlists.find(p => p.id === ctx.replace('playlist-', ''));
          if (pl?.songs) setQueue(pl.songs);
        }
      } else if (!queue.find(q => q.id === s.id)) {
        setQueue(prev => {
          if (prev.find(q => q.id === s.id)) return prev;
          return [...prev, s];
        });
      }

      if (!autoAdv) {
        if (!navStack.includes('player')) setNavStack([...navStack, 'player']);
        setTab('player');
      }

      // Always start fresh — only resume if it's the same song that was just paused
      // (handled by TrackPlayer internally when toggling play/pause)
      await playTrack(song, 0);

      // Apply current playback speed
      if (playbackSpeed !== 1.0) {
        try { await tpSetRate(playbackSpeed); } catch (e) {}
      }

      setIsPlaying(true);
      setMiniPlayerVisible(true);

      // Set duration from metadata (useProgress hook will refine it)
      setDuration(parseInt(song.duration || 240));
      setDurTime(fmt(parseInt(song.duration || 240)));

    } catch (e) {
      console.log('Play error:', e);
      Alert.alert('Error', 'Could not play song');
    } finally { lockRef.current = false; }
  };

  // Sync playSongRef for alarm feature
  playSongRef.current = playSong;

  // === STABLE CALLBACKS FOR MEMOIZED COMPONENTS ===
  const stablePlaySong = useCallback((song, ctx) => playSongRef.current?.(song, ctx), []);

  // === AUTO-ADVANCE (TrackPlayer event) ===
  useEffect(() => {
    const sub = TrackPlayer.addEventListener(Event.PlaybackQueueEnded, async () => {
      if (!curSongRef.current || autoAdvRef.current) return;
      if (radio.activeStation) return; // Don't auto-advance for radio
      autoAdvRef.current = true;
      try {
        if (sleepEndRef.current) {
          sleep.startSleep(0);
          await TrackPlayer.pause();
          setIsPlaying(false);
          ToastAndroid.show('Sleep timer: stopped', ToastAndroid.LONG); return;
        }
        if (repeatRef.current === 'one') { playSong(curSongRef.current, queueCtxRef.current, true); return; }
        advanceQueue();
      } catch (e) {}
    });
    autoAdvRef.current = false;
    return () => sub.remove();
  }, [currentSong]);

  // === PROGRESS SYNC (TrackPlayer → state, optimized) ===
  const lastFmtPos = useRef('0:00');
  const lastDurVal = useRef(0);
  useEffect(() => {
    if (!currentSong || radio.activeStation) return;
    if (trackProgress.position >= 0) {
      setProgress(trackProgress.position);
      const newFmt = fmt(Math.floor(trackProgress.position));
      if (newFmt !== lastFmtPos.current) {
        lastFmtPos.current = newFmt;
        setCurTime(newFmt);
      }
    }
    if (trackProgress.duration > 0 && Math.abs(trackProgress.duration - lastDurVal.current) > 0.5) {
      lastDurVal.current = trackProgress.duration;
      setDuration(trackProgress.duration);
      setDurTime(fmt(Math.floor(trackProgress.duration)));
    }
  }, [trackProgress.position, trackProgress.duration]);

  const advanceQueue = async () => {
    const q = queueRef.current;
    const song = curSongRef.current;
    if (!q.length) {
      if (song) fetchSimilarAndPlay(song);
      return;
    }
    const idx = q.findIndex(s => s.id === song?.id);
    let next;
    if (shuffleRef.current) next = Math.floor(Math.random() * q.length);
    else next = idx + 1;
    if (next >= q.length) {
      if (song) { fetchSimilarAndPlay(song); return; }
      if (repeatRef.current === 'all' && q.length > 0) { playSong(q[0], queueCtxRef.current, true); return; }
      return;
    }
    playSong(q[next], queueCtxRef.current, true);
  };

  const fetchSimilarAndPlay = async (song) => {
    try {
      const res = await fetch(`${API_BASE}/song/similar/?id=${song.id}`);
      const data = await res.json();
      if (data?.length > 0) {
        const similar = dedupe(data.slice(0, 15).map(norm)).filter(s => s.id !== song.id);
        if (similar.length > 0) {
          setQueue(prev => dedupe([...prev, ...similar]));
          playSong(similar[0], null, true);
        }
      }
    } catch (e) { console.log('Similar error:', e); }
  };

  // === PLAYBACK CONTROLS ===
  const togglePlay = async () => {
    try {
      const state = await TrackPlayer.getPlaybackState();
      if (state.state === State.None) return;
      if (state.state === State.Playing) {
        await TrackPlayer.pause();
        setIsPlaying(false);
      } else {
        // Kill any active radio before resuming song
        if (radio.activeStation) {
          await radio.stopStation();
        }
        await TrackPlayer.play();
        setIsPlaying(true);
      }
    } catch (e) {
      console.log('Toggle play error:', e);
    }
  };

  const playNext = () => {
    const q = queue;
    const idx = q.findIndex(s => s.id === currentSong?.id);
    // Track skip (AI reco analysis happens in hooks)
    if (shuffle) { playSong(q[Math.floor(Math.random() * q.length)], queueCtx); return; }
    if (idx + 1 < q.length) playSong(q[idx + 1], queueCtx);
    else if (autoPlay && currentSong) fetchSimilarAndPlay(currentSong);
  };

  const playPrev = () => {
    const q = queue;
    const idx = q.findIndex(s => s.id === currentSong?.id);
    if (idx > 0) playSong(q[idx - 1], queueCtx);
    else if (q.length > 0) playSong(q[q.length - 1], queueCtx);
  };

  const seekTo = async (pct) => {
    if (!duration) return;
    const posSec = pct * duration;
    try { await tpSeekTo(posSec); } catch (e) {}
    setProgress(posSec);
    setCurTime(fmt(Math.floor(posSec)));
  };

  const changeSpeed = async (spd) => {
    const rounded = Math.round(spd * 100) / 100;
    setPlaybackSpeed(rounded);
    try { await tpSetRate(rounded); } catch (e) {}
    await AsyncStorage.setItem('playbackSpeed', String(rounded));
    ToastAndroid.show(`Speed: ${rounded}x`, ToastAndroid.SHORT);
  };



  // === SLEEP TIMER (ENHANCED - managed by useSleepAlarm hook) ===
  const startSleep = sleep.startSleep;

  // === LIBRARY HELPERS ===
  const addRecent = async (song) => {
    const upd = [song, ...recentlyPlayed.filter(s => s.id !== song.id)].slice(0, 20);
    setRecentlyPlayed(upd);
    await AsyncStorage.setItem('recentlyPlayed', JSON.stringify(upd)).catch(() => {});
  };

  const incPlayCount = async (song) => {
    const upd = { ...playCounts };
    upd[song.id] = { count: (upd[song.id]?.count || 0) + 1, song: { id: song.id, name: song.name, artist: song.artist, image: song.image, duration: song.duration, media_url: song.media_url } };
    setPlayCounts(upd);
    await AsyncStorage.setItem('playCounts', JSON.stringify(upd)).catch(() => {});
  };

  const getMostPlayed = () => Object.values(playCounts).sort((a, b) => b.count - a.count).slice(0, 10).map(i => ({ ...i.song, playCount: i.count }));

  const toggleLike = async (song) => {
    const exists = likedSongs.find(s => s.id === song.id);
    const upd = exists ? likedSongs.filter(s => s.id !== song.id) : [...likedSongs, uid(song)];
    setLikedSongs(upd);
    await AsyncStorage.setItem('likedSongs', JSON.stringify(upd));
    // Auto-download on like if enabled (via offline hook)
    if (!exists && offline.autoDownloadEnabled && song.media_url) {
      handleDownload(song, null, reloadDownloads, setActiveDownloads);
    }
  };

  const createPlaylist = async () => {
    if (!newPlaylistName.trim()) return;
    const pl = { id: Date.now().toString(), name: newPlaylistName, songs: [] };
    const upd = [...playlists, pl];
    setPlaylists(upd); setNewPlaylistName('');
    await AsyncStorage.setItem('playlists', JSON.stringify(upd));
    ToastAndroid.show('Playlist created!', ToastAndroid.SHORT);
  };

  const addToPlaylist = async (song, plId) => {
    const upd = playlists.map(p => p.id === plId ? { ...p, songs: [...(p.songs || []), uid(song)] } : p);
    setPlaylists(upd);
    await AsyncStorage.setItem('playlists', JSON.stringify(upd));
    ToastAndroid.show('Added to playlist', ToastAndroid.SHORT);
  };

  const removeFromPlaylist = async (songId, plId) => {
    const upd = playlists.map(p => p.id === plId ? { ...p, songs: (p.songs || []).filter(s => s.id !== songId) } : p);
    setPlaylists(upd);
    if (selectedPlaylist?.id === plId) setSelectedPlaylist(upd.find(p => p.id === plId));
    await AsyncStorage.setItem('playlists', JSON.stringify(upd));
  };

  const deletePlaylist = (plId) => {
    Alert.alert('Delete?', 'Remove this playlist?', [
      { text: 'Cancel' },
      { text: 'Delete', style: 'destructive', onPress: async () => {
        const upd = playlists.filter(p => p.id !== plId);
        setPlaylists(upd); setSelectedPlaylist(null);
        await AsyncStorage.setItem('playlists', JSON.stringify(upd));
      }}
    ]);
  };

  const deleteDownload = async (id) => {
    const song = downloadedSongs.find(s => s.id === id);
    if (song?.localUri) {
      try {
        const f = new File(song.localUri);
        if (f.exists) f.delete();
      } catch (e) { console.log('File delete error:', e); }
    }
    const upd = downloadedSongs.filter(s => s.id !== id);
    setDownloadedSongs(upd);
    await AsyncStorage.setItem('downloadedSongs', JSON.stringify(upd));
    ToastAndroid.show(`${song?.name || 'Song'} removed & storage freed`, ToastAndroid.SHORT);
  };

  const reloadDownloads = async () => {
    const d = await AsyncStorage.getItem('downloadedSongs');
    if (d) setDownloadedSongs(JSON.parse(d));
  };



  // === QUICK PICKS ===
  useEffect(() => {
    if (recentlyPlayed.length > 0 && !quickPicksDone.current) {
      quickPicksDone.current = true;
      (async () => {
        let picks = [];
        for (const s of recentlyPlayed.slice(0, 3)) {
          try {
            const r = await fetch(`${API_BASE}/song/similar/?id=${s.id}`);
            const d = await r.json();
            if (d?.length) picks.push(...d.slice(0, 4).map(norm));
          } catch (e) {}
        }
        const ids = new Set(recentlyPlayed.map(s => s.id));
        setQuickPicks(dedupe(picks).filter(s => !ids.has(s.id)).slice(0, 12));
      })();
    }
  }, [recentlyPlayed]);

  // === AI RECOMMENDATIONS EFFECT ===
  useEffect(() => {
    if (recentlyPlayed.length >= 3 || likedSongs.length >= 3) {
      reco.generateRecommendations();
    }
  }, [recentlyPlayed.length, likedSongs.length]);

  // === SMART FOLDERS EFFECT ===
  useEffect(() => {
    libMgr.generateSmartFolders();
  }, [likedSongs.length, downloadedSongs.length, Object.keys(playCounts).length]);

  // === STORAGE CALC EFFECT ===
  useEffect(() => {
    offline.calculateStorage();
  }, [downloadedSongs.length]);

  // === ARTIST DETAILS ===
  const openArtist = async (artist) => {
    const id = artist.id || artist.artistId;
    if (!id) { ToastAndroid.show('No artist ID', ToastAndroid.SHORT); return; }
    try {
      const res = await fetch(`${API_BASE}/artist/?id=${id}`);
      const data = await res.json();
      if (data.data) setSubView({ type: 'artist', data: data.data });
      else ToastAndroid.show('Artist not found', ToastAndroid.SHORT);
    } catch (e) { ToastAndroid.show('Error loading artist', ToastAndroid.SHORT); }
  };

  // === ALBUM/PLAYLIST DETAILS (auto-detect type) ===
  const openAlbum = async (item) => {
    const id = item.id || item.albumid;
    if (!id) return;
    try {
      const isPlaylist = item.type === 'playlist' || item.count != null;
      const endpoint = isPlaylist ? 'playlist' : 'album';
      const res = await fetch(`${API_BASE}/${endpoint}/?query=${id}`);
      const data = await res.json();
      if (data && !data.detail) {
        // Normalize playlist format to album-like structure
        if (isPlaylist && data.listname) {
          data.name = data.listname || data.name || item.name;
          data.subtitle = data.firstname || '';
          data.image = data.image || item.image;
          data.songs = (data.songs || []);
        }
        setSubView({ type: 'album', data });
      } else {
        // Fallback: try the other endpoint
        const fallbackEndpoint = isPlaylist ? 'album' : 'playlist';
        const res2 = await fetch(`${API_BASE}/${fallbackEndpoint}/?query=${id}`);
        const data2 = await res2.json();
        if (data2 && !data2.detail) {
          if (!isPlaylist && data2.listname) {
            data2.name = data2.listname || item.name;
            data2.subtitle = data2.firstname || '';
            data2.image = data2.image || item.image;
            data2.songs = (data2.songs || []);
          }
          setSubView({ type: 'album', data: data2 });
        } else {
          ToastAndroid.show('Could not load content', ToastAndroid.SHORT);
        }
      }
    } catch (e) { ToastAndroid.show('Error loading content', ToastAndroid.SHORT); }
  };

  // GENRES and MOODS moved to module scope for stable references

  const [genreColor, setGenreColor] = useState('#8B5CF6');

  const loadGenre = async (lang) => {
    setGenreLoading(true); setSelectedGenre(lang);
    const g = GENRES.find(g => g.id === lang);
    if (g) setGenreColor(g.color);
    try {
      // Parallel fetch for speed: top-songs + song query
      const [topRes, queryRes] = await Promise.all([
        fetch(`${API_BASE}/browse/top-songs?language=${lang}&limit=30`).then(r => r.json()).catch(() => ({})),
        fetch(`${API_BASE}/song/?query=${encodeURIComponent(lang + ' songs')}&limit=30`).then(r => r.json()).catch(() => []),
      ]);
      const topSongs = (topRes.data || []).map(norm);
      const querySongs = (Array.isArray(queryRes) ? queryRes : []).map(norm);
      const seen = new Set(topSongs.map(s => s.id));
      querySongs.forEach(s => { if (!seen.has(s.id)) { topSongs.push(s); seen.add(s.id); } });
      setGenreSongs(topSongs.slice(0, 50));
    } catch (e) { setGenreSongs([]); }
    setGenreLoading(false);
  };

  const loadMood = async (mood) => {
    setGenreLoading(true); setSelectedGenre(mood.name);
    setGenreColor(mood.color);
    try {
      // Parallel fetch for speed
      const [res1, res2] = await Promise.all([
        fetch(`${API_BASE}/song/?query=${encodeURIComponent(mood.q)}&limit=30`).then(r => r.json()).catch(() => []),
        fetch(`${API_BASE}/song/?query=${encodeURIComponent(mood.name + ' songs')}&limit=20`).then(r => r.json()).catch(() => []),
      ]);
      const s1 = (Array.isArray(res1) ? res1 : []).map(norm);
      const s2 = (Array.isArray(res2) ? res2 : []).map(norm);
      const seen = new Set(s1.map(s => s.id));
      s2.forEach(s => { if (!seen.has(s.id)) { s1.push(s); seen.add(s.id); } });
      setGenreSongs(s1.slice(0, 50));
    } catch (e) { setGenreSongs([]); }
    setGenreLoading(false);
  };

  // === NAV HELPER ===
  const goTab = (t) => {
    if (t === tab) return;
    setNavStack(t === 'home' ? ['home'] : ['home', t]);
    setTab(t); setSubView(null); setSelectedPlaylist(null);
  };

  // ======================== COMPONENTS ========================

  // --- BOTTOM NAV ---
  const BottomNav = () => (
    <View style={S.bottomNav}>
      {[
        { k: 'home', icon: 'home', label: 'Home' },
        { k: 'explore', icon: 'compass', label: 'Explore', lib: 'Ionicons' },
        { k: 'player', icon: 'musical-notes', label: 'Player', lib: 'Ionicons' },
        { k: 'library', icon: 'library', label: 'Library', lib: 'Ionicons' },
        { k: 'radio', icon: 'radio', label: 'Radio', lib: 'Ionicons' },
      ].map(n => (
        <TouchableOpacity key={n.k} style={S.navItem} onPress={() => goTab(n.k)}>
          {n.lib === 'Ionicons'
            ? <Ionicons name={tab === n.k ? n.icon : `${n.icon}-outline`} size={22} color={tab === n.k ? '#8B5CF6' : '#666'} />
            : <MaterialIcons name={n.icon} size={22} color={tab === n.k ? '#8B5CF6' : '#666'} />
          }
          <Text style={[S.navLabel, tab === n.k && { color: '#8B5CF6', fontWeight: '700' }]}>{n.label}</Text>
        </TouchableOpacity>
      ))}
    </View>
  );

  // --- MINI PLAYER ---
  const miniTapRef = useRef(false);
  const MiniPlayer = () => {
    if (!currentSong || tab === 'player' || !miniPlayerVisible) return null;
    const handleMiniTap = () => {
      if (miniTapRef.current) return;
      miniTapRef.current = true;
      goTab('player');
      setTimeout(() => { miniTapRef.current = false; }, 400);
    };
    const btnGuard = (fn) => (e) => { e.stopPropagation(); fn(); };
    return (
      <TouchableOpacity style={S.mini} onPress={handleMiniTap} activeOpacity={0.85}>
        <LinearGradient colors={['rgba(139,92,246,0.92)', 'rgba(109,40,217,0.95)']} style={S.miniGrad} start={{ x: 0, y: 0 }} end={{ x: 1, y: 0 }}>
          <View style={S.miniProg}><View style={[S.miniProgFill, { width: `${duration > 0 ? (progress / duration) * 100 : 0}%` }]} /></View>
          <View style={S.miniContent}>
            <Image source={{ uri: currentSong.image }} style={S.miniImg} />
            <View style={{ flex: 1 }}>
              <Text style={S.miniName} numberOfLines={1}>{currentSong.name}</Text>
              <Text style={S.miniArtist} numberOfLines={1}>{currentSong.artist}</Text>
            </View>
            <TouchableOpacity onPress={btnGuard(playPrev)} style={S.miniBtn} hitSlop={{ top: 8, bottom: 8, left: 6, right: 6 }}>
              <Ionicons name="play-skip-back" size={16} color="rgba(255,255,255,0.6)" />
            </TouchableOpacity>
            <TouchableOpacity onPress={btnGuard(togglePlay)} style={S.miniBtn} hitSlop={{ top: 8, bottom: 8, left: 6, right: 6 }}>
              <Ionicons name={isPlaying ? 'pause' : 'play'} size={20} color="rgba(255,255,255,0.6)" />
            </TouchableOpacity>
            <TouchableOpacity onPress={btnGuard(playNext)} style={S.miniBtn} hitSlop={{ top: 8, bottom: 8, left: 6, right: 6 }}>
              <Ionicons name="play-skip-forward" size={16} color="rgba(255,255,255,0.6)" />
            </TouchableOpacity>
            <TouchableOpacity onPress={btnGuard(() => { setCurrentSong(null); setMiniPlayerVisible(false); stopPlayback(); })} style={S.miniBtn} hitSlop={{ top: 8, bottom: 8, left: 6, right: 6 }}>
              <Ionicons name="close" size={16} color="rgba(255,255,255,0.4)" />
            </TouchableOpacity>
          </View>
        </LinearGradient>
      </TouchableOpacity>
    );
  };

  // SongRow extracted to module scope with React.memo

  // --- SONG CARD (grid) ---
  const SongCard = ({ song, ctx }) => (
    <Pressable style={S.card} onPress={() => playSong(song, ctx)} onLongPress={() => openMenu(song)}>
      <View style={S.cardImgWrap}>
        <Image source={{ uri: song.image }} style={S.cardImg} />
        <View style={S.cardPlayBtn}><Ionicons name="play" size={20} color="#FFF" /></View>
        {currentSong?.id === song.id && (
          <View style={S.nowPlaying}><View style={[S.npBar, { height: 8 }]} /><View style={[S.npBar, { height: 14 }]} /><View style={[S.npBar, { height: 10 }]} /></View>
        )}
      </View>
      <Text style={S.cardName} numberOfLines={1}>{song.name}</Text>
      <Text style={S.cardArtist} numberOfLines={1}>{song.artist}</Text>
    </Pressable>
  );

  // Carousel extracted to module scope with React.memo

  // --- OPEN MENU HELPER (prevents glitch by deferring modal open) ---
  const openMenu = useCallback((song) => {
    setMenuSong(song);
    requestAnimationFrame(() => setShowMenu(true));
  }, []);

  // --- CONTEXT MENU (absolute overlay, no Modal = no glitch) ---
  const ContextMenu = () => {
    if (!showMenu || !menuSong) return null;
    return (
      <View style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, zIndex: 9999, elevation: 9999 }}>
        <StatusBar barStyle="light-content" backgroundColor="rgba(0,0,0,0.6)" />
        <Pressable style={S.overlay} onPress={() => setShowMenu(false)}>
          <Pressable style={S.ctxMenu} onPress={(e) => e.stopPropagation()}>
            <Text style={S.ctxTitle} numberOfLines={1}>{menuSong.name}</Text>
            <Text style={{ color: '#888', textAlign: 'center', fontSize: 12, marginBottom: 12 }}>{menuSong.artist}</Text>

            {[
              { icon: 'playlist-add', label: 'Add to Playlist', action: () => { setShowPlaylistPicker(true); setShowMenu(false); } },
              { icon: 'speed', label: 'Speed', action: () => { setShowSpeedModal(true); setShowMenu(false); } },
              { icon: 'share', label: 'Share', action: () => { Share.share({ message: `${menuSong.name} by ${menuSong.artist} — Ninaada Music` }); setShowMenu(false); } },
              { icon: 'file-download', label: 'Download', action: () => { handleDownload(menuSong, setDlProgress, reloadDownloads, setActiveDownloads); setShowMenu(false); } },
              { icon: 'info-outline', label: 'Song Credits', action: () => { setSubView({ type: 'credits', data: menuSong }); setShowMenu(false); } },
            ].map((o, i) => (
              <TouchableOpacity key={i} style={S.ctxOpt} onPress={o.action}>
                <MaterialIcons name={o.icon} size={20} color="#888" />
                <Text style={S.ctxOptText}>{o.label}</Text>
              </TouchableOpacity>
            ))}

            <TouchableOpacity style={S.ctxCancel} onPress={() => setShowMenu(false)}>
              <Text style={S.ctxCancelText}>Cancel</Text>
            </TouchableOpacity>
          </Pressable>
        </Pressable>
      </View>
    );
  };

  // --- PLAYLIST PICKER ---
  const PlaylistPicker = () => (
    <Modal visible={showPlaylistPicker} transparent animationType="slide" onRequestClose={() => setShowPlaylistPicker(false)}>
      <View style={S.modalWrap}>
        <View style={S.modalContent}>
          <View style={S.modalHeader}>
            <Text style={S.modalTitle}>Add to Playlist</Text>
            <TouchableOpacity onPress={() => setShowPlaylistPicker(false)}><MaterialIcons name="close" size={24} color="#8B5CF6" /></TouchableOpacity>
          </View>
          <View style={{ flexDirection: 'row', marginBottom: 12, gap: 8 }}>
            <TextInput style={[S.input, { flex: 1 }]} placeholder="New playlist..." placeholderTextColor="#666" value={newPlaylistName} onChangeText={setNewPlaylistName} />
            <TouchableOpacity style={S.btnGreen} onPress={async () => {
              if (!newPlaylistName.trim() || !menuSong) return;
              const pl = { id: Date.now().toString(), name: newPlaylistName, songs: [uid(menuSong)] };
              const upd = [...playlists, pl]; setPlaylists(upd); setNewPlaylistName('');
              await AsyncStorage.setItem('playlists', JSON.stringify(upd));
              setShowPlaylistPicker(false);
              ToastAndroid.show('Created & added!', ToastAndroid.SHORT);
            }}><Text style={{ color: '#FFF', fontWeight: '600' }}>Create</Text></TouchableOpacity>
          </View>
          <FlatList data={playlists} keyExtractor={i => i.id} renderItem={({ item }) => (
            <TouchableOpacity style={S.plPickItem} onPress={() => { if (menuSong) addToPlaylist(menuSong, item.id); setShowPlaylistPicker(false); }}>
              <MaterialIcons name="library-music" size={22} color="#8B5CF6" />
              <Text style={S.plPickName}>{item.name}</Text>
              <Text style={S.plPickCount}>{(item.songs || []).length}</Text>
            </TouchableOpacity>
          )} />
        </View>
      </View>
    </Modal>
  );

  // ======================== SCREENS ========================

  // --- SUB VIEWS (Artist, Album, Credits) ---
  if (subView) {
    if (subView.type === 'artist') {
      const a = subView.data;
      const songs = (a.topSongs || a.songs || []).map(norm);
      const albums = a.topAlbums || a.albums || [];
      const similar = a.similarArtists || [];
      return (
        <View style={S.container}>
          <StatusBar barStyle="light-content" backgroundColor="#0a0a14" />
          <ScrollView contentContainerStyle={{ paddingBottom: 140 }}>
            <LinearGradient colors={['#6D28D9', '#0a0a14']} style={{ paddingTop: 40, paddingBottom: 24, alignItems: 'center' }}>
              <TouchableOpacity style={{ position: 'absolute', left: 16, top: 40 }} onPress={() => setSubView(null)}>
                <Ionicons name="arrow-back" size={24} color="#FFF" />
              </TouchableOpacity>
              <Image source={{ uri: a.image || 'https://via.placeholder.com/120' }} style={{ width: 120, height: 120, borderRadius: 60, marginBottom: 12 }} />
              <Text style={{ color: '#FFF', fontSize: 24, fontWeight: '800' }}>{a.name || 'Artist'}</Text>
              {a.follower_count && <Text style={{ color: '#aaa', fontSize: 13 }}>{a.follower_count} followers</Text>}
            </LinearGradient>
            <View style={{ flexDirection: 'row', justifyContent: 'center', gap: 12, marginVertical: 16 }}>
              <TouchableOpacity style={S.btnGreen} onPress={() => songs.length > 0 && playSong(songs[0])}>
                <Ionicons name="play" size={18} color="#FFF" /><Text style={{ color: '#FFF', fontWeight: '700', marginLeft: 6 }}>Play</Text>
              </TouchableOpacity>
              <TouchableOpacity style={[S.btnGreen, { backgroundColor: '#333' }]} onPress={() => {
                if (songs.length > 0) { setQueue(songs); setShuffle(true); playSong(songs[Math.floor(Math.random() * songs.length)]); }
              }}>
                <Ionicons name="shuffle" size={18} color="#FFF" /><Text style={{ color: '#FFF', fontWeight: '700', marginLeft: 6 }}>Shuffle</Text>
              </TouchableOpacity>

            </View>
            {a.bio && <Text style={{ color: '#888', fontSize: 13, marginHorizontal: 16, marginBottom: 16, lineHeight: 20 }} numberOfLines={4}>{typeof a.bio === 'string' ? a.bio.replace(/<[^>]+>/g, '') : ''}</Text>}
            {songs.length > 0 && (
              <><Text style={[S.secTitle, { marginHorizontal: 16 }]}>Top Songs</Text>
              {songs.slice(0, 10).map((s, i) => <SongRow key={s.id} song={s} idx={i + 1} showIdx onPlay={stablePlaySong} onMenu={openMenu} />)}</>
            )}
            {albums.length > 0 && (
              <Carousel title="Albums" data={albums} renderItem={({ item }) => (
                <TouchableOpacity style={S.carouselCard} onPress={() => openAlbum(item)}>
                  <Image source={{ uri: item.image || 'https://via.placeholder.com/100' }} style={S.carouselImg} />
                  <Text style={S.carouselName} numberOfLines={1}>{item.name || item.title}</Text>
                </TouchableOpacity>
              )} />
            )}
            {similar.length > 0 && (
              <Carousel title="Similar Artists" data={similar} renderItem={({ item }) => (
                <TouchableOpacity style={S.carouselCard} onPress={() => openArtist(item)}>
                  <Image source={{ uri: item.image || 'https://via.placeholder.com/100' }} style={[S.carouselImg, { borderRadius: 50 }]} />
                  <Text style={S.carouselName} numberOfLines={1}>{item.name}</Text>
                </TouchableOpacity>
              )} />
            )}
          </ScrollView>
          <MiniPlayer /><BottomNav />
        </View>
      );
    }

    if (subView.type === 'album') {
      const a = subView.data;
      const songs = (a.songs || []).map(norm);
      return (
        <View style={S.container}>
          <StatusBar barStyle="light-content" backgroundColor="#0a0a14" />
          <ScrollView contentContainerStyle={{ paddingBottom: 140 }}>
            <LinearGradient colors={getGradient(a.id || '')} style={{ paddingTop: 40, paddingBottom: 24, alignItems: 'center' }}>
              <TouchableOpacity style={{ position: 'absolute', left: 16, top: 40 }} onPress={() => setSubView(null)}>
                <Ionicons name="arrow-back" size={24} color="#FFF" />
              </TouchableOpacity>
              <Image source={{ uri: a.image || 'https://via.placeholder.com/150' }} style={{ width: 180, height: 180, borderRadius: 12, marginBottom: 12 }} />
              <Text style={{ color: '#FFF', fontSize: 22, fontWeight: '800' }}>{a.name || a.title || 'Album'}</Text>
              <Text style={{ color: '#aaa', fontSize: 13 }}>{a.primary_artists || a.subtitle || ''}</Text>
              {a.year && <Text style={{ color: '#666', fontSize: 12, marginTop: 4 }}>{a.year} · {songs.length} songs</Text>}
            </LinearGradient>
            <View style={{ flexDirection: 'row', justifyContent: 'center', gap: 12, marginVertical: 16 }}>
              <TouchableOpacity style={S.btnGreen} onPress={() => { if (songs.length) { setQueue(songs); playSong(songs[0]); } }}>
                <Ionicons name="play" size={18} color="#FFF" /><Text style={{ color: '#FFF', fontWeight: '700', marginLeft: 6 }}>Play All</Text>
              </TouchableOpacity>
              <TouchableOpacity style={[S.btnGreen, { backgroundColor: '#333' }]} onPress={() => {
                if (songs.length) { setQueue(songs); setShuffle(true); playSong(songs[Math.floor(Math.random() * songs.length)]); }
              }}>
                <Ionicons name="shuffle" size={18} color="#FFF" /><Text style={{ color: '#FFF', fontWeight: '700', marginLeft: 6 }}>Shuffle</Text>
              </TouchableOpacity>
            </View>
            {songs.map((s, i) => <SongRow key={`${s.id}-${i}`} song={s} idx={i + 1} showIdx onPlay={stablePlaySong} onMenu={openMenu} />)}
          </ScrollView>
          <MiniPlayer /><BottomNav />
        </View>
      );
    }

    if (subView.type === 'credits') {
      const s = subView.data;
      return (
        <View style={S.container}>
          <StatusBar barStyle="light-content" backgroundColor="#0a0a14" />
          <ScrollView contentContainerStyle={{ paddingBottom: 140, paddingHorizontal: 16 }}>
            <View style={{ paddingTop: 40, marginBottom: 24 }}>
              <TouchableOpacity onPress={() => setSubView(null)}><Ionicons name="arrow-back" size={24} color="#FFF" /></TouchableOpacity>
            </View>
            <View style={{ alignItems: 'center', marginBottom: 24 }}>
              <Image source={{ uri: s?.image || 'https://via.placeholder.com/150' }} style={{ width: 140, height: 140, borderRadius: 12 }} />
              <Text style={{ color: '#FFF', fontSize: 20, fontWeight: '800', marginTop: 12 }}>{s?.name}</Text>
              <Text style={{ color: '#888', fontSize: 14 }}>{s?.artist}</Text>
            </View>
            <Text style={[S.secTitle, { marginBottom: 12 }]}>Song Credits</Text>
            {[
              { label: 'Album', value: s?.album },
              { label: 'Artists', value: s?.primary_artists || s?.artist },
              { label: 'Label', value: s?.label },
              { label: 'Year', value: s?.year },
              { label: 'Language', value: s?.language },
              { label: 'Duration', value: s?.duration ? fmt(parseInt(s.duration)) : null },
              { label: 'Explicit', value: s?.explicit ? 'Yes' : 'No' },
              { label: 'Song ID', value: s?.id },
            ].filter(c => c.value).map((c, i) => (
              <View key={i} style={S.creditRow}>
                <Text style={S.creditLabel}>{c.label}</Text>
                <Text style={S.creditValue}>{c.value}</Text>
              </View>
            ))}
          </ScrollView>
          <MiniPlayer /><BottomNav />
        </View>
      );
    }

    if (subView.type === 'viewAll') {
      const items = subView.items || [];
      return (
        <View style={S.container}>
          <StatusBar barStyle="light-content" backgroundColor="#0a0a14" />
          <LinearGradient colors={['#4c1d95', '#1e1b4b', '#0a0a14']} style={{ paddingTop: 44, paddingBottom: 18, paddingHorizontal: 16 }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
              <TouchableOpacity onPress={() => setSubView(null)}><Ionicons name="arrow-back" size={24} color="#FFF" /></TouchableOpacity>
              <Text style={{ color: '#FFF', fontSize: 22, fontWeight: '800', flex: 1 }}>{subView.title}</Text>
            </View>
            <Text style={{ color: 'rgba(255,255,255,0.5)', fontSize: 12, marginTop: 4, marginLeft: 36 }}>{items.length} items</Text>
          </LinearGradient>
          <FlatList data={items} numColumns={2} columnWrapperStyle={{ gap: 12, paddingHorizontal: 16, marginBottom: 12 }}
            contentContainerStyle={{ paddingBottom: 140, paddingTop: 12 }}
            keyExtractor={(item, idx) => `va-${item.id || idx}-${idx}`}
            renderItem={({ item }) => (
              <TouchableOpacity style={{ width: (SW - 44) / 2, marginBottom: 4 }} onPress={() => openAlbum(item)} activeOpacity={0.7}>
                <Image source={{ uri: item.image || 'https://via.placeholder.com/130' }} style={{ width: 130, height: 130, borderRadius: 12, backgroundColor: '#141424', marginBottom: 6, alignSelf: 'center' }} />
                <Text style={{ color: '#FFF', fontSize: 12, fontWeight: '600', textAlign: 'center' }} numberOfLines={2}>{item.name || item.title}</Text>
                <Text style={{ color: '#888', fontSize: 10, textAlign: 'center' }} numberOfLines={1}>{item.subtitle || item.primary_artists || (subView.kind === 'playlist' ? 'Playlist' : 'Album')}</Text>
              </TouchableOpacity>
            )} />
          <MiniPlayer /><BottomNav /><ContextMenu />
        </View>
      );
    }
  }

  // === SEARCH OVERLAY ===
  if (showSearch) {
    return (
      <View style={S.container}>
        <StatusBar barStyle="light-content" backgroundColor="#0a0a14" />
        <View style={{ paddingTop: Platform.OS === 'android' ? 36 : 50, paddingHorizontal: 16 }}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10, marginBottom: 12 }}>
            <View style={S.searchBarWrap}>
              <MaterialIcons name="search" size={20} color="#888" />
              <TextInput style={S.searchInput} placeholder="Songs, artists, albums..." placeholderTextColor="#666" value={searchQ} onChangeText={setSearchQ}
                onSubmitEditing={() => { doSearch(searchQ); searchByFilter(searchQ, searchFilter); }} returnKeyType="search" autoFocus />
              {searchQ.length > 0 && <TouchableOpacity onPress={() => { setSearchQ(''); setSearchResults({ songs: [], albums: [], artists: [] }); }}><MaterialIcons name="close" size={20} color="#888" /></TouchableOpacity>}
            </View>
          </View>

          {/* Filter tabs */}
          <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginBottom: 12 }}>
            {['songs', 'albums', 'artists'].map(f => (
              <TouchableOpacity key={f} style={[S.filterTab, searchFilter === f && S.filterTabActive]}
                onPress={() => { setSearchFilter(f); if (searchQ) searchByFilter(searchQ, f); }}>
                <Text style={[S.filterTabText, searchFilter === f && S.filterTabTextActive]}>{f.charAt(0).toUpperCase() + f.slice(1)}</Text>
              </TouchableOpacity>
            ))}
          </ScrollView>
        </View>

        {searching && <ActivityIndicator size="large" color="#8B5CF6" style={{ marginTop: 30 }} />}

        {/* Recent searches */}
        {!searching && searchQ.length === 0 && recentSearches.length > 0 && (
          <View style={{ paddingHorizontal: 16 }}>
            <View style={S.secHeader}><Text style={S.secTitle}>Recent Searches</Text>
              <TouchableOpacity onPress={async () => { setRecentSearches([]); await AsyncStorage.removeItem('recentSearches'); }}><Text style={S.secAction}>Clear</Text></TouchableOpacity>
            </View>
            {recentSearches.map((q, i) => (
              <TouchableOpacity key={i} style={S.recentItem} onPress={() => { setSearchQ(q); doSearch(q); }}>
                <MaterialIcons name="history" size={18} color="#666" /><Text style={S.recentText}>{q}</Text>
              </TouchableOpacity>
            ))}
          </View>
        )}

        {/* Search Suggestions */}
        {!searching && searchQ.length === 0 && (
          <View style={{ paddingHorizontal: 16, marginTop: 8 }}>
            <Text style={[S.secTitle, { marginBottom: 12 }]}>Try Searching For</Text>
            <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
              {['Kannada songs', 'Arijit Singh', 'Hindi romantic', 'English party', 'Devotional', 'SPB hits', 'AR Rahman', 'Retro classics', 'Lo-fi chill', 'Trending hits'].map(sug => (
                <TouchableOpacity key={sug} style={{ paddingHorizontal: 14, paddingVertical: 8, borderRadius: 20, backgroundColor: 'rgba(139,92,246,0.1)', borderWidth: 1, borderColor: 'rgba(139,92,246,0.2)' }}
                  onPress={() => { setSearchQ(sug); doSearch(sug); searchByFilter(sug, searchFilter); }}>
                  <Text style={{ color: '#A78BFA', fontSize: 13, fontWeight: '500' }}>{sug}</Text>
                </TouchableOpacity>
              ))}
            </View>
          </View>
        )}

        {/* Results */}
        {!searching && searchFilter === 'songs' && searchResults.songs.length > 0 && (
          <FlatList data={searchResults.songs.slice(0, 20)} renderItem={({ item }) => <SongRow song={item} onPlay={stablePlaySong} onMenu={openMenu} />}
            keyExtractor={(i, idx) => `${i.id}-${idx}`}
            removeClippedSubviews initialNumToRender={10} maxToRenderPerBatch={5} windowSize={7} />
        )}
        {!searching && searchFilter === 'albums' && searchResults.albums.length > 0 && (
          <FlatList data={searchResults.albums} numColumns={2} columnWrapperStyle={{ gap: 10, paddingHorizontal: 16, marginBottom: 10 }}
            renderItem={({ item }) => (
              <TouchableOpacity style={[S.card, { flex: 1 }]} onPress={() => { openAlbum(item); setShowSearch(false); }}>
                <Image source={{ uri: item.image || 'https://via.placeholder.com/150' }} style={S.cardImg} />
                <Text style={S.cardName} numberOfLines={1}>{item.name || item.title}</Text>
                <Text style={S.cardArtist} numberOfLines={1}>{item.subtitle || item.primary_artists || ''}</Text>
              </TouchableOpacity>
            )} keyExtractor={(i, idx) => `${i.id}-${idx}`} />
        )}
        {!searching && searchFilter === 'artists' && searchResults.artists.length > 0 && (
          <FlatList data={searchResults.artists} renderItem={({ item }) => (
            <TouchableOpacity style={S.songRow} onPress={() => { openArtist(item); setShowSearch(false); }}>
              <Image source={{ uri: item.image || 'https://via.placeholder.com/50' }} style={[S.songRowImg, { borderRadius: 25 }]} />
              <View style={{ flex: 1 }}><Text style={S.songRowName}>{item.name}</Text>
                <Text style={S.songRowArtist}>Artist</Text></View>
              <Ionicons name="chevron-forward" size={18} color="#666" />
            </TouchableOpacity>
          )} keyExtractor={(i, idx) => `${i.id}-${idx}`} />
        )}

        <ContextMenu /><PlaylistPicker />
      </View>
    );
  }

  // ======================== HOME ========================
  if (tab === 'home') {
    const greeting = (() => { const h = new Date().getHours(); return h < 12 ? 'Good Morning' : h < 17 ? 'Good Afternoon' : h < 21 ? 'Good Evening' : 'Good Night'; })();
    const mostPlayed = getMostPlayed();

    return (
      <View style={S.container}>
        <StatusBar barStyle="light-content" backgroundColor="#0a0a14" />
        <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={{ paddingBottom: 150 }}>
          {/* Header */}
          <LinearGradient colors={['#4c1d95', '#1e1b4b', '#0a0a14']} style={S.headerGrad} locations={[0, 0.6, 1]}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
              <View style={{ flex: 1 }}>
                <Text style={S.greeting}>{greeting}</Text>
                <Text style={S.headerTitle}>Ninaada Music</Text>
                <Text style={S.headerSub}>Resonating Beyond Listening</Text>
              </View>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
                <TouchableOpacity style={S.searchIconBtn} onPress={() => setShowSearch(true)}>
                  <Ionicons name="search" size={20} color="rgba(255,255,255,0.85)" />
                </TouchableOpacity>
              </View>
            </View>
            {/* Mood Pills */}
            <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: 14 }} contentContainerStyle={{ gap: 8 }}>
              {MOODS.map(m => (
                <TouchableOpacity key={m.id} style={[S.moodPill, { borderColor: m.color + '44' }]} onPress={() => { goTab('explore'); loadMood(m); }}>
                  <MaterialIcons name={m.icon} size={14} color={m.color} />
                  <Text style={S.moodPillText}>{m.name}</Text>
                </TouchableOpacity>
              ))}
            </ScrollView>
          </LinearGradient>

          {/* Sleep/download banners */}
          {sleepActive && (
            <View style={S.banner}><Ionicons name="moon" size={14} color="#A78BFA" />
              <Text style={S.bannerText}>{sleepEndOfSong ? 'Stopping after song' : `Sleep: ${fmt(sleepRemaining)}`}</Text>
              <TouchableOpacity onPress={() => startSleep(0)}><Text style={{ color: '#FF5252', fontSize: 12 }}>Cancel</Text></TouchableOpacity></View>
          )}
          {dlProgress && (
            <View style={[S.banner, { borderColor: 'rgba(139,92,246,0.3)' }]}><ActivityIndicator size="small" color="#8B5CF6" />
              <Text style={[S.bannerText, { color: '#8B5CF6' }]}>Downloading: {dlProgress.song}</Text></View>
          )}

          {homeLoading && <ActivityIndicator size="large" color="#8B5CF6" style={{ marginTop: 40 }} />}

          {/* Recently Played */}
          {recentlyPlayed.length > 0 && (
            <Carousel title="Recently Played" action="Clear" onAction={async () => { setRecentlyPlayed([]); await AsyncStorage.removeItem('recentlyPlayed'); }}
              data={recentlyPlayed.slice(0, 10)} renderItem={({ item }) => (
                <TouchableOpacity style={S.carouselCard} onPress={() => playSong(item)}>
                  <Image source={{ uri: item.image }} style={S.carouselImg} />
                  <Text style={S.carouselName} numberOfLines={1}>{item.name}</Text>
                  <Text style={S.carouselSub} numberOfLines={1}>{item.artist}</Text>
                </TouchableOpacity>
              )} />
          )}

          {/* Quick Picks */}
          {quickPicks.length > 0 && (
            <View style={{ marginBottom: 20 }}>
              <View style={[S.secHeader, { paddingHorizontal: 16 }]}>
                <Text style={S.secTitle}>Quick Picks</Text>
                <TouchableOpacity onPress={() => { setQueue(quickPicks); playSong(quickPicks[0]); }}>
                  <Text style={S.secAction}>Play all</Text>
                </TouchableOpacity>
              </View>
              {quickPicks.slice(0, 6).map((item, i) => (
                <TouchableOpacity key={`qp-${item.id}-${i}`} style={{ flexDirection: 'row', alignItems: 'center', paddingVertical: 8, paddingHorizontal: 16, gap: 10 }}
                  onPress={() => playSong(item)} onLongPress={() => openMenu(item)}>
                  <Image source={{ uri: item.image }} style={{ width: 50, height: 50, borderRadius: 8, backgroundColor: '#141424' }} />
                  <View style={{ flex: 1 }}>
                    <Text style={{ color: '#FFF', fontWeight: '600', fontSize: 14 }} numberOfLines={1}>{item.name}</Text>
                    <Text style={{ color: '#888', fontSize: 12 }} numberOfLines={1}>{item.artist}{item.play_count ? ` \u00B7 ${item.play_count} plays` : ''}</Text>
                  </View>
                  <TouchableOpacity onPress={() => openMenu(item)} hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}>
                    <MaterialIcons name="more-vert" size={20} color="#666" />
                  </TouchableOpacity>
                </TouchableOpacity>
              ))}
            </View>
          )}

          {/* AI Recommendations (Hook-based) */}
          <MadeForYouSection
            madeForYou={reco.madeForYou}
            dailyMix={reco.dailyMix}
            recoCards={reco.recoCards}
            moodCollections={reco.moodCollections}
            recoLoading={reco.recoLoading}
            onPlaySong={(song) => playSong(song)}
            onPlayAll={(songs) => { setQueue(songs); playSong(songs[0]); }}
            fetchMoodSongs={reco.fetchMoodSongs}
            fetchCardSongs={reco.fetchCardSongs}
          />

          {/* Top Picks (7x7 grid) */}
          <TopPicksSection
            songs={reco.topPicksSongs}
            onPlaySong={(song) => playSong(song)}
            onPlayAll={(songs) => { setQueue(songs); playSong(songs[0]); }}
          />

          {/* India's Biggest Hits */}
          {trending.length > 0 && (
            <View style={{ marginBottom: 20 }}>
              <View style={[S.secHeader, { paddingHorizontal: 16 }]}>
                <Text style={S.secTitle}>India's Biggest Hits</Text>
                <TouchableOpacity onPress={() => setSubView({ type: 'viewAll', title: "India's Biggest Hits", items: trending, kind: 'playlist' })}><Text style={S.secAction}>View all</Text></TouchableOpacity>
              </View>
              <FlatList data={trending.slice(0, 8)} horizontal showsHorizontalScrollIndicator={false}
                keyExtractor={(item, idx) => `ibh-${item.id || idx}-${idx}`}
                contentContainerStyle={{ paddingHorizontal: 16 }}
                renderItem={({ item }) => (
                  <TouchableOpacity style={S.carouselCard} onPress={() => { if (item.id) openAlbum(item); }}>
                    <Image source={{ uri: item.image || 'https://via.placeholder.com/130' }} style={S.carouselImg} />
                    <Text style={S.carouselName} numberOfLines={1}>{item.name || item.title}</Text>
                    <Text style={S.carouselSub} numberOfLines={1}>{item.subtitle || 'Playlist'}</Text>
                  </TouchableOpacity>
                )} />
            </View>
          )}

          {/* Most Played */}
          {mostPlayed.length > 0 && (
            <Carousel title="Most Played" data={mostPlayed.slice(0, 8)} renderItem={({ item }) => (
              <TouchableOpacity style={S.carouselCard} onPress={() => playSong(item)}>
                <Image source={{ uri: item.image }} style={S.carouselImg} />
                <Text style={S.carouselName} numberOfLines={1}>{item.name}</Text>
                <Text style={S.carouselSub} numberOfLines={1}>{item.artist}</Text>
              </TouchableOpacity>
            )} />
          )}

          {/* Albums For You */}
          {newReleases.length > 0 && (
            <View style={{ marginBottom: 20 }}>
              <View style={[S.secHeader, { paddingHorizontal: 16 }]}>
                <Text style={S.secTitle}>Albums For You</Text>
                <TouchableOpacity onPress={() => setSubView({ type: 'viewAll', title: 'Albums For You', items: newReleases, kind: 'album' })}><Text style={S.secAction}>View all</Text></TouchableOpacity>
              </View>
              <FlatList data={newReleases.slice(0, 10)} horizontal showsHorizontalScrollIndicator={false}
                keyExtractor={(item, idx) => `afy-${item.id || idx}-${idx}`}
                contentContainerStyle={{ paddingHorizontal: 16 }}
                renderItem={({ item }) => (
                  <TouchableOpacity style={S.carouselCard} onPress={() => openAlbum(item)}>
                    <Image source={{ uri: item.image || 'https://via.placeholder.com/130' }} style={S.carouselImg} />
                    <Text style={S.carouselName} numberOfLines={1}>{item.name || item.title}</Text>
                    <Text style={S.carouselSub} numberOfLines={1}>{item.subtitle || item.primary_artists || ''}</Text>
                  </TouchableOpacity>
                )} />
            </View>
          )}

          {/* Top Songs */}
          {topSongs.length > 0 && (
            <><View style={[S.secHeader, { paddingHorizontal: 16 }]}>
              <Text style={S.secTitle}>Top Songs</Text>
            </View>
            {topSongs.slice(0, 8).map((s, i) => <SongRow key={`ts-${s.id}-${i}`} song={s} onPlay={stablePlaySong} onMenu={openMenu} />)}</>
          )}

          {/* New Releases */}
          {newReleases.length > 0 && (
            <Carousel title="New Releases" data={newReleases.slice(0, 10)} renderItem={({ item }) => (
              <TouchableOpacity style={S.carouselCard} onPress={() => openAlbum(item)}>
                <Image source={{ uri: item.image || 'https://via.placeholder.com/100' }} style={S.carouselImg} />
                <Text style={S.carouselName} numberOfLines={1}>{item.name || item.title}</Text>
                <Text style={S.carouselSub} numberOfLines={1}>{item.subtitle || ''}</Text>
              </TouchableOpacity>
            )} />
          )}

          {/* Featured */}
          {featured.length > 0 && (
            <Carousel title="Featured Playlists" data={featured.slice(0, 10)} renderItem={({ item }) => (
              <TouchableOpacity style={S.carouselCard} onPress={() => openAlbum(item)}>
                <Image source={{ uri: item.image || 'https://via.placeholder.com/100' }} style={[S.carouselImg, { borderRadius: 10 }]} />
                <Text style={S.carouselName} numberOfLines={1}>{item.name || item.title}</Text>
                <Text style={S.carouselSub} numberOfLines={1}>{item.subtitle || ''}</Text>
              </TouchableOpacity>
            )} />
          )}

          {/* Downloads shortcut */}
          {downloadedSongs.length > 0 && (
            <Carousel title="Downloaded" action="View All" onAction={() => { goTab('library'); setLibraryTab('downloads'); }}
              data={downloadedSongs.slice(0, 6)} renderItem={({ item }) => (
                <TouchableOpacity style={S.carouselCard} onPress={() => playSong(item, 'downloaded')}>
                  <Image source={{ uri: item.image }} style={S.carouselImg} />
                  <Ionicons name="cloud-done" size={12} color="#8B5CF6" style={{ position: 'absolute', top: 6, right: 6 }} />
                  <Text style={S.carouselName} numberOfLines={1}>{item.name}</Text>
                </TouchableOpacity>
              )} />
          )}

          {/* Empty state */}
          {!homeLoading && recentlyPlayed.length === 0 && topSongs.length === 0 && (
            <View style={{ alignItems: 'center', paddingTop: 60 }}>
              <MaterialIcons name="music-note" size={80} color="#8B5CF6" />
              <Text style={{ color: '#FFF', fontSize: 22, fontWeight: '700', marginTop: 16 }}>Your Music Awaits</Text>
              <Text style={{ color: '#888', fontSize: 14, marginTop: 8, textAlign: 'center', paddingHorizontal: 40 }}>Tap the search icon to find songs, artists, or albums</Text>
            </View>
          )}
        </ScrollView>

        <MiniPlayer /><BottomNav /><ContextMenu /><PlaylistPicker />
      </View>
    );
  }

  // ======================== EXPLORE ========================
  if (tab === 'explore') {
    if (selectedGenre) {
      const genreQuotes = {
        hindi: 'The soul of Bollywood beats', english: 'Global vibes, timeless hits',
        punjabi: 'Feel the Punjabi energy', tamil: 'Melodies from the south',
        telugu: 'Tollywood magic', kannada: 'Sandalwood serenades',
        marathi: 'Rhythms of Maharashtra', bengali: 'Poetry in every note',
        Chill: 'Unwind and let the music flow', Workout: 'Push harder, play louder',
        Party: 'Turn up the night', Romance: 'Love is in the air',
        Focus: 'Deep focus, zero distractions', Sad: 'Feel every emotion',
        Devotional: 'Spiritual harmony', Retro: 'Golden era classics',
      };
      const titleCase = (s) => s.charAt(0).toUpperCase() + s.slice(1).toLowerCase();
      const displayName = titleCase(selectedGenre);
      const quote = genreQuotes[selectedGenre] || 'Curated just for you';
      return (
        <View style={S.container}>
          <StatusBar barStyle="light-content" backgroundColor="#0a0a14" />
          <LinearGradient colors={[genreColor + '40', genreColor + '15', 'transparent']} style={{ paddingTop: 44, paddingBottom: 22, paddingHorizontal: 16 }}>
            <TouchableOpacity onPress={() => { setSelectedGenre(null); setGenreSongs([]); }} style={{ marginBottom: 10 }}>
              <Ionicons name="arrow-back" size={24} color="rgba(255,255,255,0.6)" />
            </TouchableOpacity>
            <Text style={{ color: '#FFF', fontSize: 26, fontWeight: '800', letterSpacing: -0.5 }}>{displayName}</Text>
            <Text style={{ color: genreColor + 'CC', fontSize: 13, marginTop: 4, fontStyle: 'italic' }}>{quote}</Text>
            <Text style={{ color: '#888', fontSize: 12, marginTop: 6 }}>{genreSongs.length} songs</Text>
          </LinearGradient>
          {genreLoading ? <ActivityIndicator size="large" color={genreColor} style={{ marginTop: 40 }} /> : (
            <FlatList data={genreSongs} renderItem={({ item }) => <SongRow song={item} onPlay={stablePlaySong} onMenu={openMenu} />}
              keyExtractor={(i, idx) => `${i.id}-${idx}`} contentContainerStyle={{ paddingBottom: 140 }}
              removeClippedSubviews initialNumToRender={12} maxToRenderPerBatch={8} windowSize={9} />
          )}
          <MiniPlayer /><BottomNav /><ContextMenu />
        </View>
      );
    }
    return (
      <View style={S.container}>
        <StatusBar barStyle="light-content" backgroundColor="#0a0a14" />
        <ScrollView contentContainerStyle={{ paddingBottom: 140 }}>
          <LinearGradient colors={['#1e3a5f', '#0f172a', '#0a0a14']} style={S.headerGrad} locations={[0, 0.6, 1]}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
              <View>
                <Text style={S.headerTitle}>Explore</Text>
                <Text style={S.headerSub}>Discover new music</Text>
              </View>
              <TouchableOpacity style={S.searchIconBtn} onPress={() => setShowSearch(true)}>
                <Ionicons name="search" size={20} color="rgba(255,255,255,0.85)" />
              </TouchableOpacity>
            </View>
          </LinearGradient>

          <Text style={[S.secTitle, { marginHorizontal: 16, marginBottom: 12 }]}>Genres</Text>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', paddingHorizontal: 16, gap: 12, marginBottom: 20 }}>
            {GENRES.map(g => (
              <TouchableOpacity key={g.id} style={[S.genreCard, { backgroundColor: g.color + '15', borderColor: g.color + '33' }]}
                onPress={() => loadGenre(g.id)}>
                <MaterialIcons name={g.icon} size={24} color={g.color} />
                <Text style={[S.genreText, { color: g.color }]}>{g.name}</Text>
              </TouchableOpacity>
            ))}
          </View>

          <Text style={[S.secTitle, { marginHorizontal: 16, marginBottom: 12 }]}>Moods & Activities</Text>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', paddingHorizontal: 16, gap: 12, marginBottom: 20 }}>
            {MOODS.map(m => (
              <TouchableOpacity key={m.id} style={[S.moodCard, { backgroundColor: m.color + '12', borderColor: m.color + '33' }]} onPress={() => loadMood(m)}>
                <MaterialIcons name={m.icon} size={26} color={m.color} />
                <Text style={[S.moodText, { color: m.color }]}>{m.name}</Text>
              </TouchableOpacity>
            ))}
          </View>
        </ScrollView>
        <MiniPlayer /><BottomNav /><ContextMenu />
      </View>
    );
  }

  // ======================== PLAYER ========================
  if (tab === 'player') {
    const isLiked = likedSongs.find(s => s.id === currentSong?.id);
    const isDled = downloadedSongs.find(s => s.id === currentSong?.id);

    return (
      <View style={S.container}>
        <StatusBar barStyle="light-content" backgroundColor="#0a0a14" />
        {currentSong ? (
          <View style={{ flex: 1 }}>
            {/* Blurred album art background */}
            <Image source={{ uri: currentSong.image }} style={{ position: 'absolute', width: SW, height: SH, opacity: 0.35 }} blurRadius={60} resizeMode="cover" />
            {/* Dark cinematic overlay */}
            <LinearGradient colors={['rgba(0,0,0,0.5)', 'rgba(0,0,0,0.7)', 'rgba(10,10,20,0.95)']} style={{ position: 'absolute', width: SW, height: SH }} locations={[0, 0.4, 1]} />
            {/* Dynamic color tint */}
            <Animated.View style={{ position: 'absolute', width: SW, height: SH, opacity: bgFadeAnim }}>
              <LinearGradient colors={[dynamicColors.bg[0] + 'CC', dynamicColors.bg[1] + 'AA', dynamicColors.bg[2]]} style={{ flex: 1 }} locations={[0, 0.5, 1]} />
            </Animated.View>
            <View style={{ flex: 1, paddingHorizontal: 20, justifyContent: 'space-between', paddingBottom: 24 }}>
              {/* Top bar */}
              <View style={S.playerTopBar}>
                <TouchableOpacity onPress={() => goTab('home')}><Ionicons name="chevron-down" size={26} color="rgba(255,255,255,0.7)" /></TouchableOpacity>
                <Text style={{ color: 'rgba(255,255,255,0.7)', fontSize: 11, textTransform: 'uppercase', letterSpacing: 1.5, fontWeight: '600' }}>Now Playing</Text>
                <TouchableOpacity onPress={() => openMenu(currentSong)}><Ionicons name="ellipsis-horizontal" size={22} color="rgba(255,255,255,0.7)" /></TouchableOpacity>
              </View>

              {/* Album Art */}
              <View style={S.artWrap}>
                <Image source={{ uri: currentSong.image }} style={S.art} />
              </View>

              {/* Song Info */}
              <View style={S.playerInfo}>
                <View style={{ flex: 1 }}>
                  <Text style={S.playerName} numberOfLines={1}>{currentSong.name}</Text>
                  <Text style={S.playerArtist} numberOfLines={1}>{currentSong.artist}</Text>
                </View>
                <TouchableOpacity onPress={() => toggleLike(currentSong)}>
                  {isLiked ? (
                    <View style={{ shadowColor: '#FF4D6D', shadowOffset: { width: 0, height: 0 }, shadowOpacity: 0.8, shadowRadius: 10, elevation: 8 }}>
                      <LinearGradient colors={['#FF4D6D', '#FF1744']} style={{ width: 32, height: 32, borderRadius: 16, justifyContent: 'center', alignItems: 'center' }}>
                        <Ionicons name="heart" size={18} color="#FFF" />
                      </LinearGradient>
                    </View>
                  ) : (
                    <Ionicons name="heart-outline" size={26} color="rgba(255,255,255,0.5)" />
                  )}
                </TouchableOpacity>
              </View>

              {/* Auto-play similar */}
              <View style={S.autoRow}>
                <Ionicons name="radio-outline" size={14} color={autoPlay ? '#A78BFA' : '#555'} />
                <Text style={{ color: '#666', fontSize: 11, flex: 1 }}>Auto-play similar</Text>
                <TouchableOpacity style={[S.toggle, autoPlay && S.toggleOn, autoPlay && { shadowColor: '#8B5CF6', shadowOffset: { width: 0, height: 0 }, shadowOpacity: 0.7, shadowRadius: 8, elevation: 6 }]} onPress={() => setAutoPlay(!autoPlay)}>
                  <View style={[S.toggleThumb, autoPlay && S.toggleThumbOn]} />
                </TouchableOpacity>
              </View>

              {/* Seek bar */}
              <View style={S.seekWrap}>
                <Pressable style={S.seekArea} onPress={(e) => {
                  const pct = e.nativeEvent.locationX / (SW - 40);
                  seekTo(Math.max(0, Math.min(1, pct)));
                }}>
                  <View style={S.seekBg} />
                  <View style={[S.seekFill, { width: `${duration > 0 ? (progress / duration) * 100 : 0}%` }]} />
                  <View style={[S.seekThumb, { left: `${duration > 0 ? (progress / duration) * 100 : 0}%` }]} />
                </Pressable>
                <View style={S.timeRow}>
                  <Text style={S.timeText}>{curTime}</Text>
                  <Text style={S.timeText}>{durTime}</Text>
                </View>
              </View>

              {/* Controls */}
              <View style={S.controls}>
                <TouchableOpacity onPress={() => setShuffle(!shuffle)}><Ionicons name="shuffle" size={22} color={shuffle ? '#8B5CF6' : '#888'} /></TouchableOpacity>
                <TouchableOpacity onPress={playPrev}><MaterialIcons name="skip-previous" size={32} color="rgba(255,255,255,0.7)" /></TouchableOpacity>
                <TouchableOpacity onPress={togglePlay} style={S.playBtn}>
                  <LinearGradient colors={['#8B5CF6', '#A78BFA']} style={S.playBtnGrad}>
                    <Ionicons name={isPlaying ? 'pause' : 'play'} size={28} color="#FFF" />
                  </LinearGradient>
                </TouchableOpacity>
                <TouchableOpacity onPress={playNext}><MaterialIcons name="skip-next" size={32} color="rgba(255,255,255,0.7)" /></TouchableOpacity>
                <TouchableOpacity onPress={() => { const modes = ['off', 'all', 'one']; setRepeat(modes[(modes.indexOf(repeat) + 1) % 3]); }}>
                  <View style={{ alignItems: 'center', justifyContent: 'center' }}>
                    <MaterialIcons name={repeat === 'one' ? 'repeat-one' : 'repeat'} size={22} color={repeat === 'off' ? '#888' : '#8B5CF6'} />
                    {repeat === 'all' && <View style={{ width: 4, height: 4, borderRadius: 2, backgroundColor: '#8B5CF6', marginTop: 2 }} />}
                  </View>
                </TouchableOpacity>
              </View>

              {/* Action row: Add to Playlist, Download, Speed, Share, Timer */}
              <View style={S.actionRow}>
                <TouchableOpacity style={S.actBtn} onPress={() => { setMenuSong(currentSong); setShowPlaylistPicker(true); }}>
                  <MaterialIcons name="playlist-add" size={22} color="#8B5CF6" /><Text style={S.actBtnText}>Playlist</Text>
                </TouchableOpacity>
                <TouchableOpacity style={S.actBtn} onPress={() => handleDownload(currentSong, setDlProgress, reloadDownloads, setActiveDownloads)}>
                  <Ionicons name={isDled ? 'checkmark-circle' : 'arrow-down-circle-outline'} size={20} color={isDled ? '#A78BFA' : '#8B5CF6'} />
                  <Text style={S.actBtnText}>{isDled ? 'Saved' : 'Download'}</Text>
                </TouchableOpacity>
                <TouchableOpacity style={S.actBtn} onPress={() => setShowSpeedModal(true)}>
                  <Ionicons name="speedometer-outline" size={20} color={playbackSpeed !== 1 ? '#A78BFA' : '#8B5CF6'} />
                  <Text style={S.actBtnText}>{playbackSpeed !== 1 ? `${playbackSpeed}x` : 'Speed'}</Text>
                </TouchableOpacity>
                <TouchableOpacity style={S.actBtn} onPress={() => Share.share({ message: `${currentSong.name} by ${currentSong.artist} — Ninaada Music` })}>
                  <Ionicons name="share-social-outline" size={20} color="#8B5CF6" /><Text style={S.actBtnText}>Share</Text>
                </TouchableOpacity>
                <TouchableOpacity style={S.actBtn} onPress={() => setShowSleepModal(true)}>
                  <Ionicons name="timer-outline" size={20} color={sleepActive ? '#A78BFA' : '#8B5CF6'} />
                  <Text style={S.actBtnText}>{sleepActive ? fmt(sleepRemaining) : 'Timer'}</Text>
                </TouchableOpacity>
              </View>

            </View>
          </View>
        ) : (
          <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center' }}>
            <Ionicons name="musical-notes" size={80} color="#333" />
            <Text style={{ color: '#FFF', fontSize: 20, fontWeight: '700', marginTop: 16 }}>Nothing Playing</Text>
            <Text style={{ color: '#888', marginTop: 8 }}>Search and play a song</Text>
          </View>
        )}

        {/* Enhanced Sleep Timer Modal */}
        <EnhancedSleepTimerModal
          visible={showSleepModal}
          onClose={() => setShowSleepModal(false)}
          startSleep={sleep.startSleep}
          sleepActive={sleepActive}
          sleepRemaining={sleepRemaining}
          sleepEndOfSong={sleepEndOfSong}
          customSleepMin={sleep.customSleepMin}
          setCustomSleepMin={sleep.setCustomSleepMin}
          fadeOutEnabled={sleep.fadeOutEnabled}
          setFadeOutEnabled={sleep.setFadeOutEnabled}
          fadeOutDuration={sleep.fadeOutDuration}
          setFadeOutDuration={sleep.setFadeOutDuration}
          ambientDimEnabled={sleep.ambientDimEnabled}
          setAmbientDimEnabled={sleep.setAmbientDimEnabled}
        />

        {/* Ambient Dim Overlay */}
        <AmbientDimOverlay animValue={sleep.ambientDimAnim} />

        {/* Premium Speed Control */}
        <Modal visible={showSpeedModal} transparent animationType="slide" onRequestClose={() => setShowSpeedModal(false)}>
          <Pressable style={{ flex: 1, backgroundColor: 'rgba(0,0,0,0.6)' }} onPress={() => setShowSpeedModal(false)}>
            <View style={{ flex: 1 }} />
            <Pressable style={{ backgroundColor: '#1a1a2e', borderTopLeftRadius: 20, borderTopRightRadius: 20, paddingBottom: 20, paddingTop: 12, borderWidth: 1, borderColor: 'rgba(139,92,246,0.1)', borderBottomWidth: 0 }}>
              {/* Handle bar */}
              <View style={{ width: 32, height: 3, borderRadius: 2, backgroundColor: 'rgba(255,255,255,0.2)', alignSelf: 'center', marginBottom: 10 }} />
              {/* Current speed display */}
              <Text style={{ color: '#FFF', fontSize: 28, fontWeight: '300', textAlign: 'center', letterSpacing: -1 }}>{playbackSpeed.toFixed(2)}x</Text>
              <Text style={{ color: 'rgba(255,255,255,0.4)', fontSize: 10, textAlign: 'center', marginBottom: 14 }}>Playback Speed</Text>
              {/* Slider */}
              <View style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, marginBottom: 14 }}>
                <TouchableOpacity style={{ width: 30, height: 30, borderRadius: 15, backgroundColor: 'rgba(255,255,255,0.08)', justifyContent: 'center', alignItems: 'center', borderWidth: 1, borderColor: 'rgba(255,255,255,0.1)' }}
                  onPress={() => { const ns = Math.max(0.5, Math.round((playbackSpeed - 0.05) * 20) / 20); changeSpeed(ns); }}>
                  <Ionicons name="remove" size={16} color="rgba(255,255,255,0.7)" />
                </TouchableOpacity>
                <View style={{ flex: 1, marginHorizontal: 10 }}>
                  <Pressable style={{ height: 32, justifyContent: 'center' }}
                    onPress={(e) => {
                      const pct = e.nativeEvent.locationX / (SW - 92);
                      const spd = Math.round((0.5 + pct * 1.5) * 20) / 20;
                      changeSpeed(Math.max(0.5, Math.min(2.0, spd)));
                    }}>
                    <View style={{ height: 3, backgroundColor: 'rgba(255,255,255,0.1)', borderRadius: 2 }} />
                    <View style={{ height: 3, backgroundColor: '#8B5CF6', borderRadius: 2, position: 'absolute', width: `${((playbackSpeed - 0.5) / 1.5) * 100}%` }} />
                    <View style={{ width: 14, height: 14, borderRadius: 7, backgroundColor: '#FFF', position: 'absolute', left: `${((playbackSpeed - 0.5) / 1.5) * 100}%`, marginLeft: -7, top: 9, elevation: 4 }} />
                  </Pressable>
                </View>
                <TouchableOpacity style={{ width: 30, height: 30, borderRadius: 15, backgroundColor: 'rgba(255,255,255,0.08)', justifyContent: 'center', alignItems: 'center', borderWidth: 1, borderColor: 'rgba(255,255,255,0.1)' }}
                  onPress={() => { const ns = Math.min(2.0, Math.round((playbackSpeed + 0.05) * 20) / 20); changeSpeed(ns); }}>
                  <Ionicons name="add" size={16} color="rgba(255,255,255,0.7)" />
                </TouchableOpacity>
              </View>
              {/* Quick select pills */}
              <View style={{ flexDirection: 'row', justifyContent: 'center', gap: 8, paddingHorizontal: 16 }}>
                {[{ v: 0.75, l: '0.75x' }, { v: 1.0, l: 'Normal' }, { v: 1.25, l: '1.25x' }, { v: 1.5, l: '1.5x' }, { v: 2.0, l: '2x' }].map(s => (
                  <TouchableOpacity key={s.v} style={{
                    flex: 1, paddingVertical: 8, borderRadius: 16, alignItems: 'center',
                    backgroundColor: playbackSpeed === s.v ? 'rgba(139,92,246,0.15)' : 'rgba(255,255,255,0.05)',
                    borderWidth: 1, borderColor: playbackSpeed === s.v ? 'rgba(139,92,246,0.4)' : 'rgba(255,255,255,0.08)',
                    ...(playbackSpeed === s.v ? { elevation: 2 } : {}),
                  }} onPress={() => changeSpeed(s.v)}>
                    <Text style={{ color: playbackSpeed === s.v ? '#A78BFA' : 'rgba(255,255,255,0.6)', fontSize: 11, fontWeight: '600' }}>{s.l}</Text>
                  </TouchableOpacity>
                ))}
              </View>
            </Pressable>
          </Pressable>
        </Modal>

        <ContextMenu /><PlaylistPicker />
      </View>
    );
  }

  // ======================== RADIO STATIONS ========================
  if (tab === 'radio') {
    return (
      <View style={S.container}>
        <StatusBar barStyle="light-content" backgroundColor="#0a0a14" />
        <LinearGradient colors={['#7c2d12', '#1c1917', '#0a0a14']} style={S.headerGrad} locations={[0, 0.5, 1]}>
          <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
            <View style={{ flex: 1 }}>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
                <MaterialCommunityIcons name="radio-tower" size={22} color="#FFF" />
                <Text style={S.headerTitle}>Radio Stations</Text>
              </View>
              <Text style={S.headerSub}>Live streaming · {radio.categories.length} categories</Text>
            </View>
            {radio.activeStation && (
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
                <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: '#FF4D6D' }} />
                <Text style={{ color: '#FFF', fontSize: 11, fontWeight: '600' }}>LIVE</Text>
              </View>
            )}
          </View>
        </LinearGradient>
        <RadioTabContent radio={radio} />
        <MiniPlayer /><BottomNav /><ContextMenu />
      </View>
    );
  }

  // ======================== LIBRARY ========================
  if (tab === 'library') {
    return (
      <View style={S.container}>
        <StatusBar barStyle="light-content" backgroundColor="#0a0a14" />
        <LinearGradient colors={['#3b0764', '#1e1b4b', '#0a0a14']} style={S.headerGrad} locations={[0, 0.5, 1]}>
          <Text style={S.headerTitle}>Your Library</Text>
          <Text style={S.headerSub}>{playlists.length} playlists · {downloadedSongs.length} downloads · {likedSongs.length} liked</Text>
        </LinearGradient>

        {/* Library tabs */}
        <View style={S.libTabs}>
          {[
            { k: 'playlists', icon: 'musical-notes', label: 'Playlists' },
            { k: 'downloads', icon: 'arrow-down-circle-outline', label: 'Downloads' },
            { k: 'liked', icon: 'heart', label: 'Liked' },
            { k: 'smart', icon: 'flash', label: 'Smart' },
          ].map(t => (
            <TouchableOpacity key={t.k} style={[S.libTab, libraryTab === t.k && S.libTabOn]} onPress={() => { setLibraryTab(t.k); setSelectedPlaylist(null); }}>
              <Ionicons name={t.icon} size={14} color={libraryTab === t.k ? '#FFF' : '#888'} />
              <Text style={[S.libTabText, libraryTab === t.k && { color: '#FFF' }]}>{t.label}</Text>
            </TouchableOpacity>
          ))}
        </View>

        {/* LIKED TAB */}
        {libraryTab === 'liked' && (
          <>
            {likedSongs.length > 0 && (
              <TouchableOpacity style={S.playAllBtn} onPress={() => { const sorted = [...likedSongs].reverse(); setQueue(sorted); playSong(sorted[0], 'liked'); }}>
                <LinearGradient colors={['#8B5CF6', '#A78BFA']} style={S.playAllGrad}>
                  <Ionicons name="play" size={18} color="#FFF" /><Text style={S.playAllText}>Play All Liked</Text>
                </LinearGradient>
              </TouchableOpacity>
            )}
            <FlatList data={[...likedSongs].reverse()} renderItem={({ item, index }) => (
              <TouchableOpacity style={[S.songRow, libMgr.selectedItems.has(item.id) && { backgroundColor: 'rgba(139,92,246,0.1)' }]}
                onPress={() => libMgr.multiSelectMode ? libMgr.toggleSelect(item.id) : playSong(item, 'liked')}
                onLongPress={() => { if (!libMgr.multiSelectMode) { libMgr.setMultiSelectMode(true); libMgr.toggleSelect(item.id); } else { openMenu(item); } }}>
                {libMgr.multiSelectMode && (
                  <Ionicons name={libMgr.selectedItems.has(item.id) ? 'checkbox' : 'square-outline'} size={20}
                    color={libMgr.selectedItems.has(item.id) ? '#8B5CF6' : '#666'} style={{ marginRight: 4 }} />
                )}
                <Text style={S.songIdx}>{index + 1}</Text>
                <Image source={{ uri: item.image }} style={S.songRowImg} />
                <View style={{ flex: 1 }}>
                  <Text style={S.songRowName} numberOfLines={1}>{item.name}</Text>
                  <Text style={S.songRowArtist} numberOfLines={1}>{item.artist}</Text>
                </View>
                {!libMgr.multiSelectMode && <TouchableOpacity onPress={() => openMenu(item)} hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}>
                  <MaterialIcons name="more-vert" size={20} color="#666" />
                </TouchableOpacity>}
              </TouchableOpacity>
            )}
              keyExtractor={(i, idx) => `lk-${i.id}-${idx}`} contentContainerStyle={{ paddingBottom: 140 }}
              removeClippedSubviews initialNumToRender={10} maxToRenderPerBatch={5} windowSize={7}
              ListEmptyComponent={<View style={{ alignItems: 'center', paddingTop: 60 }}><Ionicons name="heart-outline" size={60} color="#333" />
                <Text style={{ color: '#FFF', fontSize: 18, fontWeight: '700', marginTop: 12 }}>No Liked Songs</Text></View>} />
          </>
        )}

        {/* DOWNLOADS TAB */}
        {libraryTab === 'downloads' && (
          <>
            {downloadedSongs.length > 0 && (
              <TouchableOpacity style={S.playAllBtn} onPress={() => { setQueue(downloadedSongs); playSong(downloadedSongs[0], 'downloaded'); }}>
                <LinearGradient colors={['#8B5CF6', '#A78BFA']} style={S.playAllGrad}>
                  <Ionicons name="play" size={18} color="#FFF" /><Text style={S.playAllText}>Play All Downloads</Text>
                </LinearGradient>
              </TouchableOpacity>
            )}
            {/* Storage info */}
            <View style={{ marginHorizontal: 16, marginBottom: 10, padding: 12, backgroundColor: '#12121f', borderRadius: 10, borderWidth: 1, borderColor: '#1e1e38' }}>
              <Text style={{ color: '#FFF', fontWeight: '600', marginBottom: 4 }}>Storage</Text>
              <Text style={{ color: '#888', fontSize: 12 }}>{offline.storageInfo.count} songs downloaded · ~{(offline.storageInfo.used / (1024 * 1024)).toFixed(0)} MB estimated</Text>
              <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 8, gap: 8 }}>
                <Text style={{ color: '#666', fontSize: 11 }}>Quality:</Text>
                {['low', 'medium', 'high'].map(q => (
                  <TouchableOpacity key={q} style={[S.sortBtn, offline.downloadQuality === q && S.sortBtnOn]}
                    onPress={() => offline.setQuality(q)}>
                    <Text style={[S.sortBtnText, offline.downloadQuality === q && { color: '#8B5CF6' }]}>{q.charAt(0).toUpperCase() + q.slice(1)}</Text>
                  </TouchableOpacity>
                ))}
              </View>
            </View>
            {/* Active downloads status */}
            {Object.keys(activeDownloads).length > 0 && (
              <View style={{ marginHorizontal: 16, marginBottom: 8 }}>
                {Object.values(activeDownloads).map(dl => (
                  <View key={dl.song.id} style={{ flexDirection: 'row', alignItems: 'center', backgroundColor: '#141424', borderRadius: 10, padding: 10, marginBottom: 6, borderWidth: 1, borderColor: '#1e1e38' }}>
                    <Image source={{ uri: dl.song.image }} style={{ width: 36, height: 36, borderRadius: 6, marginRight: 10 }} />
                    <View style={{ flex: 1 }}>
                      <Text style={{ color: '#FFF', fontSize: 13, fontWeight: '600' }} numberOfLines={1}>{dl.song.name}</Text>
                      {dl.status === 'downloading' && (
                        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, marginTop: 3 }}>
                          <ActivityIndicator size="small" color="#8B5CF6" />
                          <Text style={{ color: '#8B5CF6', fontSize: 11 }}>Downloading...</Text>
                        </View>
                      )}
                      {dl.status === 'failed' && (
                        <Text style={{ color: '#FF6B6B', fontSize: 11, marginTop: 2 }} numberOfLines={2}>{dl.error}</Text>
                      )}
                    </View>
                    {dl.status === 'failed' && (
                      <TouchableOpacity onPress={() => handleDownload(dl.song, setDlProgress, reloadDownloads, setActiveDownloads)} style={{ paddingHorizontal: 10, paddingVertical: 5, borderRadius: 8, backgroundColor: 'rgba(139,92,246,0.15)', borderWidth: 1, borderColor: 'rgba(139,92,246,0.3)' }}>
                        <Text style={{ color: '#8B5CF6', fontSize: 11, fontWeight: '600' }}>Retry</Text>
                      </TouchableOpacity>
                    )}
                    {dl.status === 'failed' && (
                      <TouchableOpacity onPress={() => setActiveDownloads(prev => { const n = { ...prev }; delete n[dl.song.id]; return n; })} style={{ marginLeft: 6 }}>
                        <Ionicons name="close" size={16} color="rgba(255,255,255,0.3)" />
                      </TouchableOpacity>
                    )}
                  </View>
                ))}
              </View>
            )}
            <FlatList data={downloadedSongs} keyExtractor={(i, idx) => `dl-${i.id}-${idx}`} contentContainerStyle={{ paddingBottom: 140 }}
              removeClippedSubviews initialNumToRender={10} maxToRenderPerBatch={5} windowSize={7}
              renderItem={({ item, index }) => (
                <View style={S.songRow}>
                  <TouchableOpacity style={{ flex: 1, flexDirection: 'row', alignItems: 'center' }} onPress={() => { setQueue(downloadedSongs); playSong(item, 'downloaded'); }}>
                    <Text style={S.songIdx}>{index + 1}</Text>
                    <Image source={{ uri: item.image }} style={S.songRowImg} />
                    <View style={{ flex: 1 }}>
                      <Text style={S.songRowName} numberOfLines={1}>{item.name}</Text>
                      <Text style={S.songRowArtist} numberOfLines={1}>{item.artist}</Text>
                      <Text style={{ color: '#555', fontSize: 10 }}>{item.downloadedAt ? new Date(item.downloadedAt).toLocaleDateString() : ''}</Text>
                    </View>
                  </TouchableOpacity>
                  <TouchableOpacity onPress={() => Alert.alert('Remove?', `Delete "${item.name}"?`, [{ text: 'Cancel' }, { text: 'Delete', onPress: () => deleteDownload(item.id) }])}>
                    <Ionicons name="trash-outline" size={18} color="#8B5CF6" />
                  </TouchableOpacity>
                </View>
              )}
              ListEmptyComponent={<View style={{ alignItems: 'center', paddingTop: 60 }}><Ionicons name="download-outline" size={60} color="#333" />
                <Text style={{ color: '#FFF', fontSize: 18, fontWeight: '700', marginTop: 12 }}>No Downloads</Text></View>} />
          </>
        )}

        {/* PLAYLISTS TAB */}
        {libraryTab === 'playlists' && !selectedPlaylist && (
          <>
            <View style={{ flexDirection: 'row', alignItems: 'center', marginHorizontal: 16, marginBottom: 12, gap: 8 }}>
              <TextInput ref={playlistInputRef} style={[S.input, { flex: 1 }]} placeholder="New playlist..." placeholderTextColor="#666" value={newPlaylistName} onChangeText={setNewPlaylistName} onSubmitEditing={createPlaylist} />
              <TouchableOpacity style={{ width: 36, height: 36, borderRadius: 10, backgroundColor: '#141424', borderWidth: 1, borderColor: '#1e1e38', alignItems: 'center', justifyContent: 'center' }} onPress={() => { if (!newPlaylistName.trim()) { playlistInputRef.current?.focus(); ToastAndroid.show('Enter a playlist name', ToastAndroid.SHORT); } else { createPlaylist(); } }}><Ionicons name="add" size={18} color="#888" /></TouchableOpacity>
            </View>
            <FlatList data={playlists} keyExtractor={i => i.id} contentContainerStyle={{ paddingBottom: 140 }}
              renderItem={({ item }) => (
                <TouchableOpacity style={S.plCard} onPress={() => setSelectedPlaylist(item)} activeOpacity={0.7}>
                  <LinearGradient colors={['#8B5CF6', '#6D28D9']} style={S.plIcon}><Ionicons name="musical-notes" size={22} color="#FFF" /></LinearGradient>
                  <View style={{ flex: 1, marginHorizontal: 12 }}><Text style={{ color: '#FFF', fontWeight: '600', fontSize: 15 }}>{item.name}</Text>
                    <Text style={{ color: '#888', fontSize: 12 }}>{(item.songs || []).length} songs</Text></View>
                  <Ionicons name="chevron-forward" size={20} color="#666" />
                </TouchableOpacity>
              )}
              ListEmptyComponent={<View style={{ alignItems: 'center', paddingTop: 60 }}><Ionicons name="library-outline" size={60} color="#333" />
                <Text style={{ color: '#FFF', fontSize: 18, fontWeight: '700', marginTop: 12 }}>No Playlists</Text></View>} />
          </>
        )}

        {/* PLAYLIST DETAIL */}
        {libraryTab === 'playlists' && selectedPlaylist && (
          <>
            <View style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, marginBottom: 12 }}>
              <TouchableOpacity onPress={() => setSelectedPlaylist(null)}><Ionicons name="chevron-back" size={20} color="rgba(255,255,255,0.5)" /></TouchableOpacity>
              <Text style={{ color: '#FFF', fontSize: 16, fontWeight: '700', flex: 1, textAlign: 'center' }}>{selectedPlaylist.name}</Text>
              <TouchableOpacity onPress={() => deletePlaylist(selectedPlaylist.id)}><Ionicons name="trash-outline" size={18} color="#8B5CF6" /></TouchableOpacity>
            </View>
            {(selectedPlaylist.songs || []).length > 0 && (
              <View style={{ flexDirection: 'row', justifyContent: 'center', gap: 10, marginBottom: 12 }}>
                <TouchableOpacity style={{ flexDirection: 'row', alignItems: 'center', paddingVertical: 8, paddingHorizontal: 16, borderRadius: 18, backgroundColor: 'rgba(139,92,246,0.15)', borderWidth: 1, borderColor: 'rgba(139,92,246,0.3)', gap: 4 }} onPress={() => { const s = selectedPlaylist.songs; setQueue(s); playSong(s[0], `playlist-${selectedPlaylist.id}`); }}>
                  <Ionicons name="play" size={14} color="rgba(255,255,255,0.6)" /><Text style={{ color: 'rgba(255,255,255,0.6)', fontWeight: '600', fontSize: 13 }}>Play All</Text>
                </TouchableOpacity>
                <TouchableOpacity style={{ flexDirection: 'row', alignItems: 'center', paddingVertical: 8, paddingHorizontal: 16, borderRadius: 18, backgroundColor: 'rgba(255,255,255,0.06)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.1)', gap: 4 }} onPress={() => {
                  const s = selectedPlaylist.songs; if (s.length) { const shuffled = [...s].sort(() => Math.random() - 0.5); setQueue(shuffled); setShuffle(true); playSong(shuffled[0], `playlist-${selectedPlaylist.id}`); }
                }}><Ionicons name="shuffle" size={14} color="rgba(255,255,255,0.6)" /><Text style={{ color: 'rgba(255,255,255,0.6)', fontWeight: '600', fontSize: 13 }}>Shuffle</Text></TouchableOpacity>
              </View>
            )}
            <FlatList data={selectedPlaylist.songs || []} keyExtractor={(i, idx) => `pl-${i.id}-${idx}`} contentContainerStyle={{ paddingBottom: 140 }}
              renderItem={({ item, index }) => (
                <View style={S.songRow}>
                  <TouchableOpacity style={{ flex: 1, flexDirection: 'row', alignItems: 'center' }} onPress={() => playSong(item, `playlist-${selectedPlaylist.id}`)}>
                    <Text style={S.songIdx}>{index + 1}</Text>
                    <Image source={{ uri: item.image }} style={S.songRowImg} />
                    <View style={{ flex: 1 }}><Text style={S.songRowName} numberOfLines={1}>{item.name}</Text>
                      <Text style={S.songRowArtist} numberOfLines={1}>{item.artist}</Text></View>
                  </TouchableOpacity>
                  <TouchableOpacity onPress={() => {
                    Alert.alert('Remove Song?', `Remove "${item.name}" from this playlist?`, [
                      { text: 'Cancel' },
                      { text: 'Remove', onPress: () => removeFromPlaylist(item.id, selectedPlaylist.id) }
                    ]);
                  }}><MaterialIcons name="close" size={18} color="#8B5CF6" /></TouchableOpacity>
                </View>
              )}
              ListEmptyComponent={<View style={{ alignItems: 'center', paddingTop: 40 }}><Text style={{ color: '#888' }}>Empty playlist</Text></View>} />
          </>
        )}

        {/* SMART FOLDERS TAB */}
        {libraryTab === 'smart' && (
          <ScrollView contentContainerStyle={{ paddingBottom: 140 }}>


            {/* Smart Folders */}
            {libMgr.smartFolders.length > 0 ? libMgr.smartFolders.map(folder => (
              <View key={folder.id} style={{ marginBottom: 16 }}>
                <TouchableOpacity style={S.smartFolderHeader} onPress={() => { setQueue(folder.songs); playSong(folder.songs[0]); }}>
                  <Ionicons name={folder.icon} size={20} color="#8B5CF6" />
                  <Text style={{ color: '#FFF', fontWeight: '600', fontSize: 15, flex: 1, marginLeft: 10 }}>{folder.name}</Text>
                  <Text style={{ color: '#888', fontSize: 12 }}>{folder.songs.length} songs</Text>
                  <Ionicons name="play" size={16} color="#8B5CF6" style={{ marginLeft: 8 }} />
                </TouchableOpacity>
                {libMgr.sortSongs(folder.songs).slice(0, 4).map((s, i) => (
                  <SongRow key={`sf-${folder.id}-${s.id}-${i}`} song={s} idx={i + 1} showIdx onPlay={stablePlaySong} onMenu={openMenu} />
                ))}
              </View>
            )) : (
              <View style={{ alignItems: 'center', paddingTop: 60 }}>
                <Ionicons name="flash-outline" size={60} color="#333" />
                <Text style={{ color: '#FFF', fontSize: 18, fontWeight: '700', marginTop: 12 }}>Smart Folders</Text>
                <Text style={{ color: '#888', fontSize: 13, marginTop: 4, textAlign: 'center', paddingHorizontal: 40 }}>Like or download songs to auto-organize by language, artist & more</Text>
              </View>
            )}
          </ScrollView>
        )}

        {/* Multi-select toolbar */}
        {libMgr.multiSelectMode && libMgr.selectedItems.size > 0 && (
          <View style={S.multiBar}>
            <Text style={{ color: 'rgba(255,255,255,0.5)', fontWeight: '600', fontSize: 12 }}>{libMgr.selectedItems.size} selected</Text>
            <TouchableOpacity onPress={() => libMgr.bulkDelete()} style={S.multiBarBtn}>
              <Ionicons name="trash-outline" size={16} color="rgba(255,255,255,0.5)" /><Text style={{ color: 'rgba(255,255,255,0.5)', fontSize: 10 }}>Delete</Text>
            </TouchableOpacity>
            <TouchableOpacity onPress={() => { const firstId = [...libMgr.selectedItems][0]; setMenuSong(likedSongs.find(s => s.id === firstId)); setShowPlaylistPicker(true); }} style={S.multiBarBtn}>
              <Ionicons name="add" size={16} color="rgba(255,255,255,0.5)" /><Text style={{ color: 'rgba(255,255,255,0.5)', fontSize: 10 }}>Playlist</Text>
            </TouchableOpacity>
            <TouchableOpacity onPress={() => { libMgr.setMultiSelectMode(false); libMgr.clearSelection(); }} style={S.multiBarBtn}>
              <Ionicons name="close" size={16} color="rgba(255,255,255,0.5)" /><Text style={{ color: 'rgba(255,255,255,0.5)', fontSize: 10 }}>Cancel</Text>
            </TouchableOpacity>
          </View>
        )}

        <MiniPlayer /><BottomNav /><ContextMenu /><PlaylistPicker />
      </View>
    );
  }

  return null;
}

// ======================== STYLES ========================
const S = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0a0a14' },
  // Nav
  bottomNav: { position: 'absolute', bottom: 0, left: 0, right: 0, height: 70, flexDirection: 'row', backgroundColor: 'rgba(10,10,20,0.92)', borderTopWidth: 1, borderTopColor: 'rgba(139,92,246,0.12)', paddingBottom: Platform.OS === 'ios' ? 16 : 0, zIndex: 50 },
  navItem: { flex: 1, justifyContent: 'center', alignItems: 'center', paddingVertical: 6 },
  navLabel: { color: '#666', fontSize: 9, marginTop: 2 },
  // Header
  headerGrad: { paddingTop: Platform.OS === 'android' ? 44 : 54, paddingBottom: 18, paddingHorizontal: 16 },
  greeting: { fontSize: 13, color: 'rgba(255,255,255,0.7)', marginBottom: 2 },
  headerTitle: { fontSize: 22, fontWeight: '800', color: '#FFF', letterSpacing: -0.5 },
  headerSub: { fontSize: 12, color: 'rgba(255,255,255,0.5)', marginTop: 2 },
  searchIconBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: 'rgba(255,255,255,0.1)', justifyContent: 'center', alignItems: 'center', borderWidth: 1, borderColor: 'rgba(255,255,255,0.08)' },
  // Mood Pills
  moodPill: { flexDirection: 'row', alignItems: 'center', gap: 6, paddingHorizontal: 14, paddingVertical: 8, borderRadius: 20, backgroundColor: 'rgba(255,255,255,0.06)', borderWidth: 1 },
  moodPillText: { color: 'rgba(255,255,255,0.9)', fontSize: 13, fontWeight: '600' },
  // Search
  searchBarWrap: { flex: 1, height: 44, backgroundColor: '#141424', borderRadius: 22, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 14, gap: 8, borderWidth: 1, borderColor: '#1e1e38' },
  searchInput: { flex: 1, color: '#FFF', fontSize: 15, height: 44 },
  filterTab: { paddingHorizontal: 18, paddingVertical: 8, borderRadius: 20, backgroundColor: '#141424', marginRight: 8, borderWidth: 1, borderColor: '#1e1e38' },
  filterTabActive: { backgroundColor: '#8B5CF6', borderColor: '#8B5CF6' },
  filterTabText: { color: '#888', fontSize: 13, fontWeight: '600' },
  filterTabTextActive: { color: '#FFF' },
  recentItem: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: '#141424' },
  recentText: { color: '#CCC', fontSize: 14 },
  // Section
  secHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 },
  secTitle: { fontSize: 18, fontWeight: '700', color: '#FFF' },
  secAction: { color: '#8B5CF6', fontSize: 13, fontWeight: '600' },
  // Carousel
  carouselCard: { width: 130, marginRight: 12 },
  carouselImg: { width: 130, height: 130, borderRadius: 10, backgroundColor: '#141424', marginBottom: 6 },
  carouselName: { color: '#FFF', fontSize: 12, fontWeight: '600' },
  carouselSub: { color: '#888', fontSize: 10 },
  // Song row
  songRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 10, paddingHorizontal: 16, gap: 10 },
  songIdx: { color: '#666', fontWeight: '600', width: 24, fontSize: 13, textAlign: 'center' },
  songRowImg: { width: 46, height: 46, borderRadius: 8, backgroundColor: '#141424' },
  songRowName: { color: '#FFF', fontWeight: '600', fontSize: 14, marginBottom: 2 },
  songRowArtist: { color: '#888', fontSize: 12 },
  songRowDur: { color: '#666', fontSize: 11 },
  explicitBadge: { backgroundColor: '#666', borderRadius: 3, paddingHorizontal: 4, paddingVertical: 1, marginRight: 4 },
  explicitText: { color: '#FFF', fontSize: 8, fontWeight: '800' },
  // Card grid
  card: { flex: 1, backgroundColor: 'rgba(255,255,255,0.04)', borderRadius: 12, overflow: 'hidden', maxWidth: (SW - 48) / 2, borderWidth: 1, borderColor: 'rgba(255,255,255,0.06)' },
  cardImgWrap: { position: 'relative' },
  cardImg: { width: '100%', height: 140, borderTopLeftRadius: 12, borderTopRightRadius: 12 },
  cardPlayBtn: { position: 'absolute', bottom: 8, right: 8, width: 32, height: 32, borderRadius: 16, backgroundColor: '#8B5CF6', justifyContent: 'center', alignItems: 'center' },
  cardName: { color: '#FFF', fontWeight: '600', fontSize: 13, paddingHorizontal: 8, paddingTop: 6 },
  cardArtist: { color: '#888', fontSize: 11, paddingHorizontal: 8, paddingBottom: 8 },
  nowPlaying: { position: 'absolute', bottom: 8, left: 8, flexDirection: 'row', alignItems: 'flex-end', gap: 2 },
  npBar: { width: 3, backgroundColor: '#8B5CF6', borderRadius: 2 },
  // Mini player
  mini: { position: 'absolute', bottom: 70, left: 8, right: 8, zIndex: 100, elevation: 10, borderRadius: 14, overflow: 'hidden' },
  miniGrad: { overflow: 'hidden', borderRadius: 14 },
  miniProg: { height: 2, backgroundColor: 'rgba(0,0,0,0.3)' },
  miniProgFill: { height: 2, backgroundColor: '#FFF' },
  miniContent: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12, paddingVertical: 10, gap: 8 },
  miniImg: { width: 42, height: 42, borderRadius: 8 },
  miniName: { color: '#FFF', fontWeight: '700', fontSize: 14 },
  miniArtist: { color: 'rgba(255,255,255,0.7)', fontSize: 11 },
  miniBtn: { padding: 8 },
  // Player
  playerScroll: { paddingHorizontal: 20, paddingBottom: 100 },
  playerTopBar: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingTop: Platform.OS === 'android' ? 40 : 50, paddingBottom: 16 },
  artWrap: { alignItems: 'center', marginBottom: 14, elevation: 10 },
  art: { width: SW - 56, height: SW - 56, borderRadius: 18, elevation: 12 },
  playerInfo: { flexDirection: 'row', alignItems: 'center', marginBottom: 4 },
  playerName: { color: '#FFF', fontSize: 22, fontWeight: '800', letterSpacing: -0.5 },
  playerArtist: { color: '#aaa', fontSize: 15, marginTop: 2 },
  autoRow: { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 12 },
  toggle: { width: 34, height: 18, borderRadius: 9, backgroundColor: '#333', justifyContent: 'center', padding: 2 },
  toggleOn: { backgroundColor: '#8B5CF6' },
  toggleThumb: { width: 14, height: 14, borderRadius: 7, backgroundColor: '#fff', alignSelf: 'flex-start' },
  toggleThumbOn: { alignSelf: 'flex-end' },
  seekWrap: { paddingVertical: 6 },
  seekArea: { height: 36, justifyContent: 'center' },
  seekBg: { width: '100%', height: 4, backgroundColor: '#333', borderRadius: 2, position: 'absolute' },
  seekFill: { height: 4, backgroundColor: '#8B5CF6', borderRadius: 2, position: 'absolute' },
  seekThumb: { width: 14, height: 14, borderRadius: 7, backgroundColor: '#FFF', position: 'absolute', marginLeft: -7, top: 11, elevation: 3 },
  timeRow: { flexDirection: 'row', justifyContent: 'space-between', marginTop: 6 },
  timeText: { color: '#888', fontSize: 12 },
  controls: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 12, marginVertical: 4 },
  playBtn: { marginHorizontal: 12 },
  playBtnGrad: { width: 56, height: 56, borderRadius: 28, justifyContent: 'center', alignItems: 'center', elevation: 8 },
  repeatDot: { position: 'absolute', bottom: -4, right: -2, width: 5, height: 5, borderRadius: 3, backgroundColor: '#8B5CF6' },
  actionRow: { flexDirection: 'row', justifyContent: 'space-between', paddingHorizontal: 12, marginTop: 4 },
  actBtn: { alignItems: 'center', gap: 3 },
  actBtnText: { color: '#888', fontSize: 10, fontWeight: '500' },
  // Modals
  overlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.6)', justifyContent: 'center', alignItems: 'center' },
  modalWrap: { flex: 1, backgroundColor: 'rgba(0,0,0,0.85)', justifyContent: 'flex-end' },
  modalContent: { backgroundColor: '#12121f', borderTopLeftRadius: 24, borderTopRightRadius: 24, maxHeight: '85%', paddingBottom: 16, borderWidth: 1, borderColor: 'rgba(139,92,246,0.1)', borderBottomWidth: 0 },
  modalHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', padding: 16, borderBottomWidth: 1, borderBottomColor: '#1e1e38' },
  modalTitle: { color: '#FFF', fontSize: 18, fontWeight: '700' },
  // Context menu
  ctxMenu: { backgroundColor: '#141428', borderRadius: 20, width: '82%', paddingVertical: 16, paddingHorizontal: 16, elevation: 10, borderWidth: 1, borderColor: 'rgba(139,92,246,0.12)' },
  ctxTitle: { color: '#FFF', fontWeight: '700', fontSize: 16, textAlign: 'center', marginBottom: 6 },
  ctxOpt: { flexDirection: 'row', alignItems: 'center', paddingVertical: 12, paddingHorizontal: 8, borderBottomWidth: 1, borderBottomColor: '#141424', gap: 12 },
  ctxOptText: { color: '#FFF', fontSize: 14 },
  ctxCancel: { backgroundColor: '#1e1e38', borderRadius: 10, marginTop: 10, paddingVertical: 12, alignItems: 'center' },
  ctxCancelText: { color: '#FFF', fontWeight: '600', fontSize: 14 },
  // Buttons
  btnGreen: { backgroundColor: '#8B5CF6', flexDirection: 'row', alignItems: 'center', paddingVertical: 10, paddingHorizontal: 18, borderRadius: 20, gap: 4 },
  input: { height: 44, backgroundColor: '#141424', borderRadius: 10, paddingHorizontal: 14, color: '#FFF', fontSize: 14, borderWidth: 1, borderColor: '#1e1e38' },
  // Playlist picker
  plPickItem: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 14, paddingHorizontal: 16, borderBottomWidth: 1, borderBottomColor: '#141424' },
  plPickName: { color: '#FFF', fontSize: 15, fontWeight: '600', flex: 1 },
  plPickCount: { color: '#888', fontSize: 13 },
  // Playlist card
  plCard: { flexDirection: 'row', alignItems: 'center', backgroundColor: 'rgba(255,255,255,0.04)', marginHorizontal: 16, marginBottom: 6, padding: 10, borderRadius: 10, borderWidth: 1, borderColor: 'rgba(255,255,255,0.06)' },
  plIcon: { width: 38, height: 38, borderRadius: 8, justifyContent: 'center', alignItems: 'center' },
  // Library tabs
  libTabs: { flexDirection: 'row', marginHorizontal: 16, marginBottom: 12, gap: 8 },
  libTab: { flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', paddingVertical: 8, paddingHorizontal: 2, borderRadius: 20, backgroundColor: '#141424', gap: 4, borderWidth: 1, borderColor: '#1e1e38' },
  libTabOn: { backgroundColor: '#8B5CF6', borderColor: '#8B5CF6' },
  libTabText: { color: '#888', fontSize: 11, fontWeight: '600' },
  // Play all
  playAllBtn: { marginHorizontal: 16, marginBottom: 12 },
  playAllGrad: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', paddingVertical: 10, borderRadius: 20, gap: 6 },
  playAllText: { color: '#FFF', fontWeight: '700', fontSize: 14 },
  // Lyrics
  lyricsLine: { color: '#666', fontSize: 15, lineHeight: 26, marginVertical: 4, paddingHorizontal: 12 },
  lyricsActive: { color: '#A78BFA', fontSize: 17, fontWeight: '700', backgroundColor: 'rgba(139,92,246,0.12)', paddingVertical: 6, borderLeftWidth: 3, borderLeftColor: '#8B5CF6', paddingLeft: 9, borderRadius: 4 },
  // Genres
  genreCard: { width: (SW - 44) / 2, paddingVertical: 16, borderRadius: 14, alignItems: 'center', justifyContent: 'center', borderWidth: 1, gap: 6, backgroundColor: 'rgba(20,20,36,0.6)' },
  genreText: { fontSize: 14, fontWeight: '700' },
  moodCard: { width: (SW - 44) / 2, paddingVertical: 16, borderRadius: 14, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(20,20,36,0.6)', borderWidth: 1, borderColor: 'rgba(139,92,246,0.1)', gap: 6 },
  moodText: { color: '#FFF', fontSize: 13, fontWeight: '600' },
  // Speed
  speedBtn: { width: 64, height: 40, borderRadius: 10, backgroundColor: '#141424', justifyContent: 'center', alignItems: 'center', borderWidth: 1, borderColor: '#1e1e38' },
  speedBtnOn: { borderColor: '#FF6B35', backgroundColor: 'rgba(255,107,53,0.15)' },
  speedBtnText: { color: '#888', fontSize: 15, fontWeight: '700' },
  // Credits
  creditRow: { flexDirection: 'row', paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: '#141424' },
  creditLabel: { color: '#888', fontSize: 13, width: 100 },
  creditValue: { color: '#FFF', fontSize: 14, flex: 1, fontWeight: '500' },
  // Banner
  banner: { flexDirection: 'row', alignItems: 'center', marginHorizontal: 16, marginBottom: 8, paddingVertical: 8, paddingHorizontal: 14, borderRadius: 10, gap: 8, borderWidth: 1, borderColor: 'rgba(139,92,246,0.2)', backgroundColor: 'rgba(139,92,246,0.06)' },
  bannerText: { color: '#A78BFA', fontSize: 12, fontWeight: '500', flex: 1 },
  // Play count badge
  playCountBadge: { position: 'absolute', top: 6, right: 6, backgroundColor: 'rgba(0,0,0,0.7)', borderRadius: 8, paddingHorizontal: 6, paddingVertical: 2 },
  playCountText: { color: '#FFF', fontSize: 10, fontWeight: '700' },
  // === NEW FEATURE STYLES ===
  fab: { position: 'absolute', bottom: 150, right: 16, width: 52, height: 52, borderRadius: 26, backgroundColor: '#8B5CF6', justifyContent: 'center', alignItems: 'center', elevation: 8, zIndex: 200 },
  dailyMixCard: { width: 150, height: 90, marginRight: 12, borderRadius: 12, overflow: 'hidden' },
  dailyMixGrad: { flex: 1, justifyContent: 'center', alignItems: 'center', padding: 12 },
  dailyMixName: { color: '#FFF', fontWeight: '700', fontSize: 16 },
  dailyMixCount: { color: 'rgba(255,255,255,0.7)', fontSize: 11 },
  smartFolderHeader: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 12, backgroundColor: '#12121f', borderRadius: 10, marginHorizontal: 16, marginBottom: 4 },
  sortBtn: { paddingHorizontal: 12, paddingVertical: 6, borderRadius: 14, backgroundColor: '#141424', borderWidth: 1, borderColor: '#1e1e38' },
  sortBtnOn: { borderColor: '#8B5CF6', backgroundColor: 'rgba(139,92,246,0.15)' },
  sortBtnText: { color: '#888', fontSize: 11, fontWeight: '600' },
  settingBtn: { flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 4, paddingVertical: 8, borderRadius: 10, backgroundColor: '#141424', borderWidth: 1, borderColor: '#1e1e38' },
  settingBtnText: { color: '#888', fontSize: 11, fontWeight: '600' },
  multiBar: { position: 'absolute', bottom: 70, left: 0, right: 0, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-evenly', backgroundColor: '#141424', paddingVertical: 8, borderTopWidth: 1, borderTopColor: '#1e1e38', zIndex: 100 },
  multiBarBtn: { alignItems: 'center', gap: 1 },
  cmdChip: { paddingHorizontal: 12, paddingVertical: 6, borderRadius: 16, backgroundColor: '#141424', borderWidth: 1, borderColor: '#1e1e38' },
  cmdChipText: { color: '#888', fontSize: 11 },
});
