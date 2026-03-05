// ========== RADIO STATIONS FEATURE ==========
// Curated live radio stations organized by category

import React, { useState, useRef, useEffect, useCallback } from 'react';
import {
  View, Text, TouchableOpacity, FlatList, ScrollView, StyleSheet,
  ActivityIndicator, Animated, Dimensions, Image, Platform, ToastAndroid,
} from 'react-native';
import { Ionicons, MaterialCommunityIcons, MaterialIcons, FontAwesome5 } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { playRadioStream, stopPlayback, TrackPlayer } from '../services/audioService';

const { width: SW } = Dimensions.get('window');

// ======================== STATION DATA ========================

const RADIO_CATEGORIES = [
  {
    id: 'air_karnataka',
    title: 'AIR Karnataka',
    subtitle: 'All India Radio — Official Stations',
    icon: 'radio-tower',
    iconLib: 'MaterialCommunityIcons',
    color: '#FF6B35',
    emoji: '🇮🇳',
    stations: [
      { id: 'air_bengaluru', name: 'AIR Bengaluru', url: 'https://airhlspush.pc.cdn.bitgravity.com/httppush/hlspbaudio030/hlspbaudio03064kbps.m3u8', icon: '🏙️' },
      { id: 'air_dharwad', name: 'AIR Dharwad', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio150/chunklist.m3u8', icon: '🎵' },
      { id: 'air_mysuru', name: 'AIR Mysuru', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio177/chunklist.m3u8', icon: '🏰' },
      { id: 'air_mangalore', name: 'AIR Mangalore', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio073/chunklist.m3u8', icon: '🌊' },
      { id: 'air_kalaburagi', name: 'AIR Kalaburagi', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio015/chunklist.m3u8', icon: '�', iconName: 'radio-outline' },
      { id: 'air_raichur', name: 'AIR Raichur', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio198/chunklist.m3u8', icon: '🌾' },
      { id: 'air_hassan', name: 'AIR Hassan', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio172/chunklist.m3u8', icon: '⛰️' },
      { id: 'air_chitradurga', name: 'AIR Chitradurga', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio105/chunklist.m3u8', icon: '�️', iconName: 'shield-outline' },
      { id: 'air_ballari', name: 'AIR Ballari', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio142/chunklist.m3u8', icon: '🪨' },
      { id: 'air_bijapur', name: 'AIR Bijapur', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio145/chunklist.m3u8', icon: '🕍' },
      { id: 'air_madikeri', name: 'AIR Madikeri', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio068/chunklist.m3u8', icon: '🌿' },
      { id: 'air_karwar', name: 'AIR Karwar', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio123/chunklist.m3u8', icon: '🏖️' },
      { id: 'air_hospet', name: 'AIR Hospet', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio184/chunklist.m3u8', icon: '🛕' },
      { id: 'air_bhadravati', name: 'AIR Bhadravati', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio211/chunklist.m3u8', icon: '🏭' },
      { id: 'vividh_bharati', name: 'Vividh Bharati', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio001/chunklist.m3u8', icon: '🎙️' },
      { id: 'air_fm_gold', name: 'AIR FM Gold', url: 'https://airhlspush.pc.cdn.bitgravity.com/httppush/hlspbaudio005/hlspbaudio00532kbps.m3u8', icon: '🥇' },
      { id: 'air_ragam', name: 'AIR Ragam', url: 'https://airhlspush.pc.cdn.bitgravity.com/httppush/hlspbaudioragam/hlspbaudioragam64kbps115323444.aac', icon: '🎼' },
      { id: 'rainbow_kannada', name: 'Rainbow Kannada', url: 'https://airhlspush.pc.cdn.bitgravity.com/httppush/hlspbaudio027/hlspbaudio02764kbps.m3u8', icon: '🌈' },
      { id: 'vb_kannada', name: 'VB Kannada', url: 'https://airhlspush.pc.cdn.bitgravity.com/httppush/hlspbaudio026/hlspbaudio02664kbps.m3u8', icon: '📻' },
      { id: 'air_samachara', name: '24×7 Samachara', url: 'https://airhlspush.pc.cdn.bitgravity.com/httppush/hlspbaudio002/hlspbaudio00264kbps.m3u8', icon: '📰' },
    ],
  },
  {
    id: 'kannada_internet',
    title: 'Kannada Songs',
    subtitle: 'Kannada Internet Radio Stations',
    icon: 'music-circle',
    iconLib: 'MaterialCommunityIcons',
    color: '#8B5CF6',
    emoji: '🎵',
    stations: [
      { id: 'nudi_kannada', name: 'Nudi Kannada', url: 'https://stream.zeno.fm/en4wu0vg74zuv', icon: '📖' },
      { id: 'sakath_radio', name: 'Sakath Radio', url: 'https://stream.zeno.fm/fcsk9ryerd0uv', icon: '🔥' },
      { id: 'kannada_geete', name: 'Kannada Geete', url: 'https://server.geetradio.com:8040/radio.mp3', icon: '🎶' },
      { id: 'radio_city_kn', name: 'Radio City Kannada', url: 'https://server.geetradio.com:8040/radio.mp3', icon: '🏙️' },
      { id: 'vv_radio', name: 'VV Radio Kannada', url: 'https://eu1.fastcast4u.com/proxy/vvradio?mp=/;', icon: '📡' },
      { id: 'premaloka', name: 'Kannada City Premaloka', url: 'https://stream-157.zeno.fm/68snnbug8rhvv?zt=eyJhbGciOiJIUzI1NiJ9.eyJzdHJlYW0iOiI2OHNubmJ1ZzhyaHZ2IiwiaG9zdCI6InN0cmVhbS0xNTcuemVuby5mbSIsInJ0dGwiOjUsImp0aSI6IlZIcTRKS1h3U0Z1SzFNYWVsWkFHNmciLCJpYXQiOjE3NzE0NzA3NjUsImV4cCI6MTc3MTQ3MDgyNX0.W0Apx-l_9Gqf4VSgF5hAxgzBATXiHAiqD01co0Xg8Y4', icon: '💕' },
      { id: 'sarang', name: 'Sarang Kannada', url: 'https://cast1.asurahosting.com/proxy/deltaast/stream', icon: '🎻' },
      { id: 'madhura_taranga', name: 'Madhura Taranga', url: 'https://stream-166.zeno.fm/v0gde6udfg8uv?zt=eyJhbGciOiJIUzI1NiJ9.eyJzdHJlYW0iOiJ2MGdkZTZ1ZGZnOHV2IiwiaG9zdCI6InN0cmVhbS0xNjYuemVuby5mbSIsInJ0dGwiOjUsImp0aSI6IkJ1SFJNQThFUV9hbExfal9sTld1bEEiLCJpYXQiOjE3NzE0NzE4NzEsImV4cCI6MTc3MTQ3MTkzMX0.LPtM22QitwjBXimyD2NR7qs_LXbrfybl9FkB8URA3rU', icon: '🌊' },
      { id: 'shiva_lahari', name: 'Shiva Lahari', url: 'https://17653.live.streamtheworld.com/SP_R2925215_SC', icon: '🙏' },
      { id: 'nimma_dhwani', name: 'Nimma Dhwani', url: 'https://dx8jkkbno1vwo.cloudfront.net/nammadhwani.m3u8', icon: '🗣️' },
      { id: 'puneet_raj', name: 'Puneet Rajkumar', url: 'https://stream-174.zeno.fm/rketbsyc5uhvv?zt=eyJhbGciOiJIUzI1NiJ9.eyJzdHJlYW0iOiJya2V0YnN5YzV1aHZ2IiwiaG9zdCI6InN0cmVhbS0xNzQuemVuby5mbSIsInJ0dGwiOjUsImp0aSI6ImRZVHpLaGRsVGJteFhrbElHc2dUYXciLCJpYXQiOjE3MzIxMDM3MDQsImV4cCI6MTczMjEwMzc2NH0.-u6833-xBIfMwjXy4i', icon: '⭐' },
      { id: 'suno_kannada', name: 'Suno Kannada', url: 'https://17813.live.streamtheworld.com/RADIO_SUNO_MELODY_S06_SC', icon: '🎧', iconName: 'headset-outline' },
      { id: 'mirchi_kannada', name: 'Mirchi Kannada', url: 'https://stream.zeno.fm/68snnbug8rhvv', icon: '🌶️' },
      { id: 'gulf_kannada', name: 'Gulf Kannada', url: 'https://stream-164.zeno.fm/kgw2tp5p1y5tv?zt=eyJhbGciOiJIUzI1NiJ9.eyJzdHJlYW0iOiJrZ3cydHA1cDF5NXR2IiwiaG9zdCI6InN0cmVhbS0xNjQuemVuby5mbSIsInJ0dGwiOjUsImp0aSI6InhJWkpqRFJyVDZTNy1HdTNKMzljTmciLCJpYXQiOjE3NzE0NzI0OTEsImV4cCI6MTc3MTQ3MjU1MX0.9hssuGlU1Q7--GtASTnC7EzFQXV2x0ZwKseQQ5tH6LM', icon: '🌍' },
      { id: 'usa_kannada', name: 'USA Kannada', url: 'https://stream-164.zeno.fm/kc4wg3ent1duv?zt=eyJhbGciOiJIUzI1NiJ9.eyJzdHJlYW0iOiJrYzR3ZzNlbnQxZHV2IiwiaG9zdCI6InN0cmVhbS0xNjQuemVuby5mbSIsInJ0dGwiOjUsImp0aSI6IkUzQTMzenJCUy1tTVlDbmJNeTh5SkEiLCJpYXQiOjE3NzE0NzI1NDcsImV4cCI6MTc3MTQ3MjYwN30.IA85nZkTVZ9QMlEk_X5a3RCo3qulsdaE6ZIctKzfOGU', icon: '🇺🇸' },
      { id: 'fresh_kannada', name: 'Fresh Kannada', url: 'https://worldradio.online/proxy/?q=http://85.25.185.202:8625/stream', icon: '🍃' },
      { id: 'girmit_kannada', name: 'Girmit Kannada', url: 'https://stream.radiojar.com/g6dgm6m6p3hvv', icon: '🎭' },
      { id: 'shalom_kannada', name: 'Shalom Kannada', url: 'https://worldradio.online/proxy/?q=http://rd.shalombeatsradio.com:8090/stream', icon: '🕊️', iconName: 'leaf-outline' },
      { id: 'your_beloved', name: 'Your Beloved', url: 'https://player.vvradio.co.in/proxy/vvradio/stream', icon: '❤️' },
    ],
  },
  {
    id: 'hindi_stations',
    title: 'Hindi Stations',
    subtitle: 'Bollywood & Hindi Music',
    icon: 'music-box-multiple',
    iconLib: 'MaterialCommunityIcons',
    color: '#FF4D6D',
    emoji: '🇮🇳',
    stations: [
      { id: 'radio_mirchi', name: 'Radio Mirchi', url: 'https://eu8.fastcast4u.com/proxy/clyedupq?mp=%2F1?aw_0_req_lsid=2c0fae177108c9a42a7cf24878625444', icon: '🌶️' },
      { id: 'red_fm', name: 'Red FM', url: 'https://stream.zeno.fm/9phrkb1e3v8uv', icon: '🔴' },
      { id: 'big_fm_hindi', name: 'Big FM Hindi', url: 'https://stream.zeno.fm/dbstwo3dvhhtv', icon: '📻' },
      { id: '90s_bollywood', name: "90's Bollywood", url: 'https://stream.zeno.fm/u0hrd3xkzhhvv', icon: '🕺' },
      { id: 'lata_mangeshkar', name: 'Lata Mangeshkar', url: 'https://stream.zeno.fm/g95zm67prfhvv', icon: '👑' },
      { id: 'sonu_nigam', name: 'Sonu Nigam', url: 'https://3.mystreaming.net/uber/bollywoodsonunigam/icecast.audio', icon: '🎤' },
      { id: 'shreya_ghoshal', name: 'Shreya Ghoshal', url: 'https://nl4.mystreaming.net/uber/bollywoodshreyaghosal/icecast.audio', icon: '🎵' },
      { id: 'bollywood_love', name: 'Bollywood Love', url: 'https://3.mystreaming.net/uber/bollywoodlove/icecast.audio', icon: '💕' },
      { id: 'exclusive_bw', name: 'Exclusive Bollywood', url: 'https://nl4.mystreaming.net/er/bollywood/icecast.audio', icon: '💎' },
      { id: 'big_fm_retro', name: 'Big FM Retro', url: 'https://stream.zeno.fm/dbstwo3dvhhtv', icon: '🎞️' },
      { id: 'isqu_fm', name: 'Isqu FM', url: 'https://nl4.mystreaming.net/uber/bollywoodlove/icecast.audio', icon: '🎧' },
      { id: 'mirchi_tamil', name: 'Mirchi Tamil', url: 'https://free.rcast.net/72516', icon: '🌶️' },
      { id: 'top_tamil', name: 'Top Tamil', url: 'https://stream.zeno.fm/ex1yqu2gsh1tv', icon: '🎶' },
      { id: 'mirchi_malayalam', name: 'Mirchi Malayalam', url: 'https://stream.aiir.com/dbv0rxpwp6ytv', icon: '🌴' },
    ],
  },
  {
    id: 'english_intl',
    title: 'English / International',
    subtitle: 'International Radio Stations',
    icon: 'earth',
    iconLib: 'Ionicons',
    color: '#00B4D8',
    emoji: '🌍',
    stations: [
      { id: 'classic_rock', name: 'Classic Rock', url: 'https://streaming.shoutcast.com/classic-rock-vibes-aac', icon: '🎸' },
      { id: 'adult_hits', name: 'Adult Hits', url: 'https://beamadult.streeemer.com/listen/beamadult/radio.aac', icon: '🎵' },
      { id: 'reggaeton', name: '100% Reggaeton', url: 'https://stream.zeno.fm/8wup8yd9dm0uv', icon: '💃' },
      { id: 'heart_uk', name: 'UK Hearts', url: 'https://media-ssl.musicradio.com/HeartUK', icon: '❤️' },
      { id: 'uk_songs', name: 'UK Songs', url: 'https://virgin.live.stream.broadcasting.news/stream', icon: '🇬🇧' },
      { id: 'nethdima', name: 'Nethdima English', url: 'https://stream-160.zeno.fm/fgcaapesa78uv?zt=eyJhbGciOiJIUzI1NiJ9.eyJzdHJlYW0iOiJmZ2NhYXBlc2E3OHV2IiwiaG9zdCI6InN0cmVhbS0xNjAuemVuby5mbSIsInJ0dGwiOjUsImp0aSI6IjJfXzVlN1hiUUYyUDRnVXlvS3FJeEEiLCJpYXQiOjE3NzE0NzM0MTgsImV4cCI6MTc3MTQ3MzQ3OH0.8FgrmjmFEnPJx8DM7hxYY-D__f8VdlD9OD_RexalvS4', icon: '🌐' },
      { id: 'bitter_sweet', name: 'Bitter Sweet', url: 'https://beamfm.streeemer.com/listen/beam_fm/radio.aac', icon: '🍬' },
      { id: 'feba_online', name: 'FEBA Online', url: 'https://listen.radioking.com/radio/557210/stream/618317', icon: '📻' },
      { id: 'erre_jackson', name: 'Erre Jackson', url: 'https://stream.zeno.fm/rxx6d9fbvv8uv', icon: '🎤' },
    ],
  },
];

// ======================== HOOK ========================

export function useRadioStations({ isPlaying, setIsPlaying, setCurrentSong }) {
  const [activeStation, setActiveStation] = useState(null);
  const [radioLoading, setRadioLoading] = useState(false);
  const [expandedCategory, setExpandedCategory] = useState(null);
  const radioLockRef = useRef(false);

  // === CORE: Kill ALL audio (TrackPlayer handles both song + radio) ===
  const killAllAudio = useCallback(async () => {
    try { await stopPlayback(); } catch {}
  }, []);

  const playStation = useCallback(async (station) => {
    // Prevent rapid-fire calls
    if (radioLockRef.current) return;
    radioLockRef.current = true;

    try {
      // If tapping the same station that's already playing, stop it (toggle off)
      if (activeStation?.id === station.id) {
        try { await stopPlayback(); } catch {}
        setActiveStation(null);
        setRadioLoading(false);
        ToastAndroid.show(`⏹ ${station.name} stopped`, ToastAndroid.SHORT);
        return;
      }

      setRadioLoading(true);

      // Kill ALL audio before starting new stream
      await killAllAudio();
      setIsPlaying(false);

      // Play radio stream via TrackPlayer
      await playRadioStream(station);

      setActiveStation(station);
      setRadioLoading(false);
      ToastAndroid.show(`▶ ${station.name}`, ToastAndroid.SHORT);
    } catch (e) {
      console.log('Radio play error:', e);
      setRadioLoading(false);
      setActiveStation(null);
      ToastAndroid.show('Could not play station', ToastAndroid.SHORT);
    } finally {
      radioLockRef.current = false;
    }
  }, [activeStation, setIsPlaying, killAllAudio]);

  const stopStation = useCallback(async () => {
    try { await stopPlayback(); } catch {}
    setActiveStation(null);
    setRadioLoading(false);
  }, []);

  const toggleCategory = useCallback((catId) => {
    setExpandedCategory(prev => prev === catId ? null : catId);
  }, []);

  return {
    activeStation,
    radioLoading,
    expandedCategory,
    killAllAudio,
    playStation,
    stopStation,
    toggleCategory,
    categories: RADIO_CATEGORIES,
  };
}

// ======================== COMPONENTS ========================

// --- Now Playing Banner ---
function NowPlayingBanner({ station, onStop, loading }) {
  const pulseAnim = useRef(new Animated.Value(1)).current;

  useEffect(() => {
    if (station) {
      const anim = Animated.loop(
        Animated.sequence([
          Animated.timing(pulseAnim, { toValue: 0.4, duration: 800, useNativeDriver: true }),
          Animated.timing(pulseAnim, { toValue: 1, duration: 800, useNativeDriver: true }),
        ])
      );
      anim.start();
      return () => anim.stop();
    }
  }, [station]);

  if (!station) return null;

  return (
    <LinearGradient colors={['#8B5CF6', '#6D28D9']} style={RS.nowPlayingBar} start={{ x: 0, y: 0 }} end={{ x: 1, y: 0 }}>
      <View style={RS.nowPlayingInner}>
        <Animated.View style={[RS.liveIndicator, { opacity: pulseAnim }]}>
          <View style={RS.liveDot} />
        </Animated.View>
        <View style={{ flex: 1 }}>
          <Text style={RS.nowPlayingName} numberOfLines={1}>{station.name}</Text>
          <Text style={RS.nowPlayingLabel}>{loading ? 'Connecting...' : 'LIVE'}</Text>
        </View>
        {loading ? (
          <ActivityIndicator size="small" color="#FFF" />
        ) : (
          <TouchableOpacity onPress={onStop} style={RS.stopBtn} hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}>
            <Ionicons name="stop-circle" size={32} color="#FFF" />
          </TouchableOpacity>
        )}
      </View>
    </LinearGradient>
  );
}

// --- Category Card ---
function CategoryCard({ category, expanded, onToggle, onPlayStation, activeStation, radioLoading }) {
  const rotateAnim = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    Animated.timing(rotateAnim, {
      toValue: expanded ? 1 : 0,
      duration: 250,
      useNativeDriver: true,
    }).start();
  }, [expanded]);

  const rotate = rotateAnim.interpolate({ inputRange: [0, 1], outputRange: ['0deg', '180deg'] });

  const IconComponent = category.iconLib === 'Ionicons' ? Ionicons : MaterialCommunityIcons;

  return (
    <View style={RS.categoryCard}>
      <TouchableOpacity onPress={onToggle} activeOpacity={0.7}>
        <LinearGradient
          colors={[category.color + '30', category.color + '08']}
          style={RS.categoryHeader}
          start={{ x: 0, y: 0 }} end={{ x: 1, y: 0 }}
        >
          <View style={[RS.categoryIconWrap, { backgroundColor: category.color + '25' }]}>
            <IconComponent name={category.icon} size={22} color={category.color} />
          </View>
          <View style={{ flex: 1 }}>
            <Text style={RS.categoryTitle}>{category.title}</Text>
            <Text style={RS.categorySub}>{category.stations.length} stations · {category.subtitle}</Text>
          </View>
          <Animated.View style={{ transform: [{ rotate }] }}>
            <Ionicons name="chevron-down" size={20} color="#888" />
          </Animated.View>
        </LinearGradient>
      </TouchableOpacity>

      {expanded && (
        <View style={RS.stationList}>
          {category.stations.map((station) => {
            const isActive = activeStation?.id === station.id;
            return (
              <TouchableOpacity
                key={station.id}
                style={[RS.stationRow, isActive && RS.stationRowActive]}
                onPress={() => onPlayStation(station)}
                activeOpacity={0.6}
              >
                <View style={[RS.stationIcon, isActive && { backgroundColor: '#8B5CF6' + '30' }]}>
                  {station.iconName ? (
                    <Ionicons name={station.iconName} size={18} color={isActive ? '#8B5CF6' : '#888'} />
                  ) : (
                    <Text style={{ fontSize: 18 }}>{station.icon}</Text>
                  )}
                </View>
                <Text style={[RS.stationName, isActive && { color: '#8B5CF6', fontWeight: '700' }]} numberOfLines={1}>
                  {station.name}
                </Text>
                {isActive ? (
                  radioLoading ? (
                    <ActivityIndicator size="small" color="#8B5CF6" />
                  ) : (
                    <View style={RS.equalizerWrap}>
                      <EqualizerBars />
                    </View>
                  )
                ) : (
                  <Ionicons name="play-circle" size={28} color="#555" />
                )}
              </TouchableOpacity>
            );
          })}
        </View>
      )}
    </View>
  );
}

// --- Equalizer Animation ---
function EqualizerBars() {
  const bars = [useRef(new Animated.Value(0.3)).current, useRef(new Animated.Value(0.6)).current, useRef(new Animated.Value(0.4)).current];

  useEffect(() => {
    const anims = bars.map((bar, i) =>
      Animated.loop(
        Animated.sequence([
          Animated.timing(bar, { toValue: 1, duration: 300 + i * 100, useNativeDriver: true }),
          Animated.timing(bar, { toValue: 0.2, duration: 300 + i * 100, useNativeDriver: true }),
        ])
      )
    );
    anims.forEach(a => a.start());
    return () => anims.forEach(a => a.stop());
  }, []);

  return (
    <View style={RS.eqWrap}>
      {bars.map((bar, i) => (
        <Animated.View key={i} style={[RS.eqBar, { transform: [{ scaleY: bar }] }]} />
      ))}
    </View>
  );
}

// --- Main Radio Tab Content ---
export function RadioTabContent({ radio }) {
  const { activeStation, radioLoading, expandedCategory, playStation, stopStation, toggleCategory, categories } = radio;

  return (
    <>
      {/* Now Playing Banner */}
      <NowPlayingBanner station={activeStation} onStop={stopStation} loading={radioLoading} />

      {/* Categories */}
      <ScrollView contentContainerStyle={{ paddingBottom: 160 }} showsVerticalScrollIndicator={false}>
        {/* Quick Play — Popular Picks */}
        <View style={RS.quickSection}>
          <Text style={RS.quickTitle}>Quick Play</Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: 12 }}>
            {[
              { ...RADIO_CATEGORIES[0].stations[0], cat: 'AIR' },       // AIR Bengaluru
              { ...RADIO_CATEGORIES[1].stations[0], cat: 'Kannada' },    // Nudi Kannada
              { ...RADIO_CATEGORIES[2].stations[0], cat: 'Hindi' },      // Radio Mirchi
              { ...RADIO_CATEGORIES[3].stations[0], cat: 'English' },    // Classic Rock
              { ...RADIO_CATEGORIES[1].stations[10], cat: 'Kannada' },   // Puneet Rajkumar
              { ...RADIO_CATEGORIES[2].stations[12], cat: 'Tamil' },     // Top Tamil
              { ...RADIO_CATEGORIES[2].stations[13], cat: 'Malayalam' },  // Mirchi Malayalam
              { ...RADIO_CATEGORIES[2].stations[8], cat: 'Hindi' },      // Exclusive Bollywood (last)
            ].map((s) => {
              const isActive = activeStation?.id === s.id;
              return (
                <TouchableOpacity key={s.id} style={[RS.quickCard, isActive && RS.quickCardActive]} onPress={() => playStation(s)}>
                  {s.iconName ? (
                    <Ionicons name={s.iconName} size={28} color={isActive ? '#8B5CF6' : '#888'} />
                  ) : (
                    <Text style={{ fontSize: 28 }}>{s.icon}</Text>
                  )}
                  <Text style={[RS.quickName, isActive && { color: '#8B5CF6' }]} numberOfLines={1}>{s.name}</Text>
                  <Text style={RS.quickCat}>{s.cat}</Text>
                  {isActive && <View style={RS.quickLive}><Text style={RS.quickLiveText}>LIVE</Text></View>}
                </TouchableOpacity>
              );
            })}
          </ScrollView>
        </View>

        {/* All Categories */}
        {categories.map((cat) => (
          <CategoryCard
            key={cat.id}
            category={cat}
            expanded={expandedCategory === cat.id}
            onToggle={() => toggleCategory(cat.id)}
            onPlayStation={playStation}
            activeStation={activeStation}
            radioLoading={radioLoading}
          />
        ))}

        {/* Footer */}
        <View style={RS.footer}>
          <MaterialCommunityIcons name="radio-tower" size={28} color="#333" />
          <Text style={RS.footerText}>All streams are sourced from public internet radio stations</Text>
        </View>
      </ScrollView>
    </>
  );
}

// ======================== STYLES ========================
const RS = StyleSheet.create({
  // Now Playing Banner
  nowPlayingBar: { marginHorizontal: 12, marginBottom: 10, borderRadius: 14, overflow: 'hidden', elevation: 4 },
  nowPlayingInner: { flexDirection: 'row', alignItems: 'center', padding: 12, gap: 10 },
  liveIndicator: { width: 12, height: 12, borderRadius: 6, backgroundColor: '#FFF', justifyContent: 'center', alignItems: 'center' },
  liveDot: { width: 6, height: 6, borderRadius: 3, backgroundColor: '#FF4D6D' },
  nowPlayingName: { color: '#FFF', fontSize: 15, fontWeight: '700' },
  nowPlayingLabel: { color: 'rgba(255,255,255,0.7)', fontSize: 10, letterSpacing: 1.5, fontWeight: '800', marginTop: 1 },
  stopBtn: { padding: 2 },

  // Quick Play
  quickSection: { marginBottom: 16 },
  quickTitle: { color: '#FFF', fontSize: 16, fontWeight: '700', marginHorizontal: 16, marginBottom: 10 },
  quickCard: { width: 100, height: 110, backgroundColor: '#12121f', borderRadius: 14, alignItems: 'center', justifyContent: 'center', marginRight: 10, padding: 8, borderWidth: 1, borderColor: '#1e1e38' },
  quickCardActive: { borderColor: '#8B5CF6', backgroundColor: 'rgba(29,185,84,0.08)' },
  quickName: { color: '#CCC', fontSize: 11, fontWeight: '600', marginTop: 6, textAlign: 'center' },
  quickCat: { color: '#666', fontSize: 9, marginTop: 2 },
  quickLive: { position: 'absolute', top: 6, right: 6, backgroundColor: '#FF4D6D', paddingHorizontal: 5, paddingVertical: 1, borderRadius: 4 },
  quickLiveText: { color: '#FFF', fontSize: 7, fontWeight: '800', letterSpacing: 0.5 },

  // Category
  categoryCard: { marginHorizontal: 12, marginBottom: 10, borderRadius: 14, overflow: 'hidden', backgroundColor: '#0f0f1a', borderWidth: 1, borderColor: '#141424' },
  categoryHeader: { flexDirection: 'row', alignItems: 'center', padding: 14, gap: 12 },
  categoryIconWrap: { width: 40, height: 40, borderRadius: 12, justifyContent: 'center', alignItems: 'center' },
  categoryTitle: { color: '#FFF', fontSize: 15, fontWeight: '700' },
  categorySub: { color: '#888', fontSize: 11, marginTop: 1 },

  // Station List
  stationList: { paddingBottom: 8 },
  stationRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 10, paddingHorizontal: 14, gap: 12, borderTopWidth: 1, borderTopColor: '#141424' },
  stationRowActive: { backgroundColor: 'rgba(29,185,84,0.06)' },
  stationIcon: { width: 38, height: 38, borderRadius: 10, backgroundColor: '#141424', justifyContent: 'center', alignItems: 'center' },
  stationName: { color: '#CCC', fontSize: 14, flex: 1 },

  // Equalizer
  eqWrap: { flexDirection: 'row', alignItems: 'flex-end', gap: 2, height: 18 },
  eqBar: { width: 3, height: 18, backgroundColor: '#8B5CF6', borderRadius: 2 },
  equalizerWrap: { width: 28, alignItems: 'center' },

  // Footer
  footer: { alignItems: 'center', paddingVertical: 30, gap: 8 },
  footerText: { color: '#444', fontSize: 11, textAlign: 'center', paddingHorizontal: 40 },
});
