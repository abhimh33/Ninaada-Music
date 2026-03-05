import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  View, Text, TouchableOpacity, FlatList, Image, StyleSheet,
  ActivityIndicator, ScrollView, Dimensions
} from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { MaterialIcons, Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';

const { width: SW } = Dimensions.get('window');
const API_BASE = "http://10.20.3.243:8000";

const norm = (s) => ({
  id: s.id, name: s.song || s.name || s.title || 'Unknown',
  artist: s.primary_artists || s.artist || s.subtitle || 'Unknown Artist',
  image: s.image || 'https://via.placeholder.com/150',
  duration: s.duration || 240, media_url: s.media_url || '',
  album: s.album || '', year: s.year || '', language: s.language || '',
  label: s.label || '', explicit: s.explicit_content === 1, ...s,
});

const dedupe = (arr) => {
  const s = new Set();
  return (arr || []).filter(i => { if (!i?.id || s.has(i.id)) return false; s.add(i.id); return true; });
};

// Fetch up to `limit` unique songs for multiple queries
const fetchManySongs = async (queries, limit = 50) => {
  const all = [];
  const usedIds = new Set();
  for (const q of queries) {
    if (all.length >= limit) break;
    try {
      const res = await fetch(`${API_BASE}/song/?query=${encodeURIComponent(q)}&limit=50`);
      const data = await res.json();
      if (Array.isArray(data)) {
        data.forEach(s => {
          const n = norm(s);
          if (!usedIds.has(n.id) && all.length < limit) {
            usedIds.add(n.id);
            all.push(n);
          }
        });
      }
    } catch (e) {}
  }
  return all;
};

// ========== AI RECOMMENDATION ENGINE HOOK ==========
export function useRecommendations({ recentlyPlayed, likedSongs, playCounts, playlists }) {
  const [madeForYou, setMadeForYou] = useState([]);
  const [dailyMix, setDailyMix] = useState([]);
  const [moodCollections, setMoodCollections] = useState([]);
  const [recoCards, setRecoCards] = useState([]);
  const [recoLoading, setRecoLoading] = useState(false);
  const [lastGenerated, setLastGenerated] = useState(0);
  const [topPicksSongs, setTopPicksSongs] = useState([]);
  const generatingRef = useRef(false);

  // Load cached recommendations
  useEffect(() => {
    (async () => {
      try {
        const [mfy, dm, mc, rc, lg, tp] = await Promise.all([
          AsyncStorage.getItem('reco_madeForYou'),
          AsyncStorage.getItem('reco_dailyMix'),
          AsyncStorage.getItem('reco_moodCollections'),
          AsyncStorage.getItem('reco_recoCards'),
          AsyncStorage.getItem('reco_lastGenerated'),
          AsyncStorage.getItem('reco_topPicks'),
        ]);
        if (mfy) setMadeForYou(JSON.parse(mfy));
        if (dm) setDailyMix(JSON.parse(dm));
        if (mc) setMoodCollections(JSON.parse(mc));
        if (rc) setRecoCards(JSON.parse(rc));
        if (lg) setLastGenerated(parseInt(lg));
        if (tp) setTopPicksSongs(JSON.parse(tp));
      } catch (e) { console.log('Reco load error:', e); }
    })();
  }, []);

  // Analyze user's listening habits
  const analyzeHabits = useCallback(() => {
    const artistFreq = {};
    const languageFreq = {};
    const genreFreq = {};

    const allSongs = [
      ...(recentlyPlayed || []),
      ...(likedSongs || []),
    ];

    allSongs.forEach(s => {
      const artist = s.artist || s.primary_artists || '';
      artist.split(',').forEach(a => {
        const name = a.trim();
        if (name) artistFreq[name] = (artistFreq[name] || 0) + 1;
      });
      if (s.language) languageFreq[s.language] = (languageFreq[s.language] || 0) + 1;
      if (s.album) genreFreq[s.album] = (genreFreq[s.album] || 0) + 1;
    });

    Object.values(playCounts || {}).forEach(pc => {
      if (pc.song?.artist) {
        pc.song.artist.split(',').forEach(a => {
          const name = a.trim();
          if (name) artistFreq[name] = (artistFreq[name] || 0) + (pc.count * 2);
        });
      }
    });

    const hour = new Date().getHours();
    let timeContext = 'morning';
    if (hour >= 12 && hour < 17) timeContext = 'afternoon';
    else if (hour >= 17 && hour < 21) timeContext = 'evening';
    else if (hour >= 21 || hour < 6) timeContext = 'night';

    return {
      topArtists: Object.entries(artistFreq).sort((a, b) => b[1] - a[1]).slice(0, 10).map(e => e[0]),
      topLanguages: Object.entries(languageFreq).sort((a, b) => b[1] - a[1]).slice(0, 5).map(e => e[0]),
      topGenres: Object.entries(genreFreq).sort((a, b) => b[1] - a[1]).slice(0, 5).map(e => e[0]),
      timeContext,
      totalPlayed: allSongs.length,
    };
  }, [recentlyPlayed, likedSongs, playCounts]);

  // Generate recommendations (50 songs per category)
  const generateRecommendations = useCallback(async (force = false) => {
    if (!force && Date.now() - lastGenerated < 3600000 && madeForYou.length > 0) return;
    if (generatingRef.current) return;
    generatingRef.current = true;
    setRecoLoading(true);

    try {
      const habits = analyzeHabits();
      const allPicks = [];
      const usedIds = new Set();

      // 1. Fetch similar songs based on recently played (12 seeds)
      const recentSeeds = (recentlyPlayed || []).slice(0, 12);
      const similarPromises = recentSeeds.map(seed =>
        fetch(`${API_BASE}/song/similar/?id=${seed.id}`).then(r => r.json()).catch(() => [])
      );
      const similarResults = await Promise.all(similarPromises);
      similarResults.forEach((data, idx) => {
        if (Array.isArray(data)) {
          data.slice(0, 10).forEach(s => {
            const normed = norm(s);
            if (!usedIds.has(normed.id)) {
              usedIds.add(normed.id);
              allPicks.push({ ...normed, _reason: `Because you played "${recentSeeds[idx]?.name}"` });
            }
          });
        }
      });

      // 2. Artist-based recommendations (parallel, 6 artists)
      const artistPromises = habits.topArtists.slice(0, 6).map(artist =>
        fetch(`${API_BASE}/song/?query=${encodeURIComponent(artist + ' songs')}&limit=15`).then(r => r.json()).catch(() => [])
      );
      const artistResults = await Promise.all(artistPromises);
      artistResults.forEach((data, idx) => {
        if (Array.isArray(data)) {
          data.slice(0, 10).forEach(s => {
            const normed = norm(s);
            if (!usedIds.has(normed.id)) {
              usedIds.add(normed.id);
              allPicks.push({ ...normed, _reason: `Because you love ${habits.topArtists[idx]}` });
            }
          });
        }
      });

      // 3. Language-based recommendations (parallel)
      const langPromises = habits.topLanguages.slice(0, 3).map(lang =>
        fetch(`${API_BASE}/browse/top-songs?language=${lang}&limit=20`).then(r => r.json()).catch(() => ({}))
      );
      const langResults = await Promise.all(langPromises);
      langResults.forEach((data, idx) => {
        if (data.data && Array.isArray(data.data)) {
          data.data.slice(0, 15).forEach(s => {
            const normed = norm(s);
            if (!usedIds.has(normed.id)) {
              usedIds.add(normed.id);
              allPicks.push({ ...normed, _reason: `Top ${habits.topLanguages[idx]} pick` });
            }
          });
        }
      });

      // Shuffle and split
      const shuffled = allPicks.sort(() => Math.random() - 0.5);
      const mfy = shuffled.slice(0, 50);
      const dm = shuffled.slice(50, 100).length > 5 ? shuffled.slice(50, 100) : shuffled.slice(0, 30);

      setMadeForYou(mfy);
      setDailyMix(dm);

      // Generate recommendation cards with 50 songs each
      const cards = [];
      if (habits.topArtists.length > 0) {
        const artistSongs = shuffled.filter(s => s._reason?.includes(habits.topArtists[0])).slice(0, 50);
        let finalSongs = artistSongs;
        if (artistSongs.length < 20) {
          const extra = await fetchManySongs([
            habits.topArtists[0] + ' best songs',
            habits.topArtists[0] + ' top hits',
            habits.topArtists[0] + ' latest',
          ], 50);
          finalSongs = dedupe([...artistSongs, ...extra]).slice(0, 50);
        }
        cards.push({
          id: 'artist-reco',
          title: `Because you love ${habits.topArtists[0]}`,
          subtitle: `More from artists like ${habits.topArtists.slice(0, 3).join(', ')}`,
          icon: 'person',
          color: '#7B2FBE',
          songs: finalSongs,
        });
      }
      if (habits.topLanguages.length > 0) {
        const langSongs = shuffled.filter(s => s.language === habits.topLanguages[0]).slice(0, 50);
        let finalSongs = langSongs;
        if (langSongs.length < 20) {
          const extra = await fetchManySongs([
            habits.topLanguages[0] + ' hits',
            habits.topLanguages[0] + ' latest songs',
            habits.topLanguages[0] + ' top songs',
          ], 50);
          finalSongs = dedupe([...langSongs, ...extra]).slice(0, 50);
        }
        cards.push({
          id: 'lang-reco',
          title: `Your ${habits.topLanguages[0]} Mix`,
          subtitle: `Hits in ${habits.topLanguages[0]}`,
          icon: 'language',
          color: '#FF6B35',
          songs: finalSongs,
        });
      }

      // Time-based card
      const moodQueries = {
        morning: ['happy morning vibes', 'upbeat positive energy', 'morning motivation songs'],
        afternoon: ['afternoon chill vibes', 'feel good afternoon', 'relaxing afternoon music'],
        evening: ['evening relaxation music', 'sunset chill vibes', 'evening mood songs'],
        night: ['late night calm music', 'night chill songs', 'midnight vibes'],
      };
      const moodQ = moodQueries[habits.timeContext] || moodQueries.evening;
      const timeSongs = await fetchManySongs(moodQ, 50);
      cards.push({
        id: 'time-reco',
        title: `${habits.timeContext.charAt(0).toUpperCase() + habits.timeContext.slice(1)} Vibes`,
        subtitle: 'Perfect for this time of day',
        icon: habits.timeContext === 'night' ? 'nightlight-round' : habits.timeContext === 'morning' ? 'wb-sunny' : 'cloud',
        color: habits.timeContext === 'night' ? '#4a0e4e' : '#FFD700',
        songs: timeSongs,
      });

      setRecoCards(cards);

      // Generate mood collections (merged into Made For You) with pre-fetched 50 songs each
      const moodDefs = [
        { name: 'Chill & Focus', queries: ['chill lo-fi focus', 'study music ambient', 'calm focus instrumental'], icon: 'headphones', color: '#2A9D8F' },
        { name: 'High Energy', queries: ['upbeat energy workout', 'high energy dance', 'pump up gym songs'], icon: 'flash-on', color: '#FF4D6D' },
        { name: 'Feel Good', queries: ['happy feel good vibes', 'feel good party songs', 'uplifting positive music'], icon: 'wb-sunny', color: '#FBBF24' },
      ];

      const moodPromises = moodDefs.map(m => fetchManySongs(m.queries, 50));
      const moodResults = await Promise.all(moodPromises);
      const moods = moodDefs.map((m, i) => ({
        ...m,
        songs: moodResults[i],
      }));
      setMoodCollections(moods);

      // Generate Top Picks (50 songs based on user listening)
      const topPicksQueries = [];
      habits.topArtists.slice(0, 5).forEach(a => topPicksQueries.push(a + ' best'));
      habits.topLanguages.slice(0, 2).forEach(l => topPicksQueries.push(l + ' trending'));
      topPicksQueries.push('trending hits popular');
      const tp = await fetchManySongs(topPicksQueries, 50);
      setTopPicksSongs(tp);

      // Save to cache
      await Promise.all([
        AsyncStorage.setItem('reco_madeForYou', JSON.stringify(mfy)),
        AsyncStorage.setItem('reco_dailyMix', JSON.stringify(dm)),
        AsyncStorage.setItem('reco_moodCollections', JSON.stringify(moods)),
        AsyncStorage.setItem('reco_recoCards', JSON.stringify(cards)),
        AsyncStorage.setItem('reco_lastGenerated', Date.now().toString()),
        AsyncStorage.setItem('reco_topPicks', JSON.stringify(tp)),
      ]);
      setLastGenerated(Date.now());

    } catch (e) {
      console.log('Reco generation error:', e);
    } finally {
      setRecoLoading(false);
      generatingRef.current = false;
    }
  }, [recentlyPlayed, likedSongs, playCounts, lastGenerated, madeForYou, analyzeHabits]);

  // Fetch songs for a mood collection (returns pre-loaded songs)
  const fetchMoodSongs = useCallback(async (mood) => {
    if (mood.songs && mood.songs.length > 0) return mood.songs;
    try {
      const songs = await fetchManySongs(mood.queries || [mood.name + ' songs'], 50);
      return songs;
    } catch (e) { return []; }
  }, []);

  // Fetch songs for a recommendation card (pre-loaded)
  const fetchCardSongs = useCallback(async (card) => {
    if (card.songs && card.songs.length > 0) return card.songs;
    return [];
  }, []);

  return {
    madeForYou, dailyMix, moodCollections, recoCards, recoLoading,
    generateRecommendations, fetchMoodSongs, fetchCardSongs, analyzeHabits,
    topPicksSongs,
  };
}

// ========== MADE FOR YOU SECTION COMPONENT ==========
export function MadeForYouSection({ madeForYou, dailyMix, recoCards, moodCollections, recoLoading, onPlaySong, onPlayAll, fetchMoodSongs, fetchCardSongs }) {
  const [expandedCard, setExpandedCard] = useState(null);
  const [cardSongs, setCardSongs] = useState([]);
  const [loadingCard, setLoadingCard] = useState(false);

  const handleCardPress = async (card) => {
    if (expandedCard?.id === card.id) { setExpandedCard(null); return; }
    setExpandedCard(card);
    setLoadingCard(true);
    const songs = await fetchCardSongs(card);
    setCardSongs(songs);
    setLoadingCard(false);
  };

  const handleMoodPress = async (mood) => {
    if (expandedCard?.id === mood.name) { setExpandedCard(null); return; }
    setExpandedCard({ id: mood.name, title: mood.name, color: mood.color });
    setLoadingCard(true);
    const songs = await fetchMoodSongs(mood);
    setCardSongs(songs);
    setLoadingCard(false);
  };

  return (
    <View style={{ marginBottom: 4 }}>
      {/* Made for You Header - no refresh button */}
      <View style={RS.secHeader}>
        <View>
          <Text style={RS.secTitle}>Made For You</Text>
          <Text style={RS.secSub}>Personalized picks based on your taste</Text>
        </View>
        {recoLoading && <ActivityIndicator size="small" color="#8B5CF6" />}
      </View>

      {/* Recommendation Cards (artist, language, time-based) */}
      {recoCards.length > 0 && (
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginBottom: 12 }}
          contentContainerStyle={{ paddingHorizontal: 16 }}>
          {recoCards.map(card => (
            <TouchableOpacity key={card.id} style={[RS.recoCard, { borderColor: card.color + '44' }]}
              onPress={() => handleCardPress(card)} activeOpacity={0.7}>
              <LinearGradient colors={[card.color + '33', '#0a0a14']} style={RS.recoCardGrad}>
                <MaterialIcons name={card.icon} size={28} color={card.color} />
                <Text style={RS.recoCardTitle} numberOfLines={2}>{card.title}</Text>
                <Text style={RS.recoCardSub} numberOfLines={1}>{card.subtitle}</Text>
                {card.songs?.length > 0 && (
                  <Text style={RS.recoCardCount}>{card.songs.length} songs</Text>
                )}
              </LinearGradient>
            </TouchableOpacity>
          ))}
        </ScrollView>
      )}

      {/* Mood Mixes (merged into Made For You section, same card theme) */}
      {moodCollections.length > 0 && (
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginBottom: 12 }}
          contentContainerStyle={{ paddingHorizontal: 16 }}>
          {moodCollections.map(mood => (
            <TouchableOpacity key={mood.name} style={[RS.recoCard, { borderColor: mood.color + '44' }]}
              onPress={() => handleMoodPress(mood)} activeOpacity={0.7}>
              <LinearGradient colors={[mood.color + '33', '#0a0a14']} style={RS.recoCardGrad}>
                <MaterialIcons name={mood.icon} size={28} color={mood.color} />
                <Text style={RS.recoCardTitle} numberOfLines={2}>{mood.name}</Text>
                <Text style={[RS.recoCardSub, { color: '#8B5CF6' }]} numberOfLines={1}>
                  {mood.songs?.length > 0 ? `${mood.songs.length} songs` : 'Curated for you'}
                </Text>
              </LinearGradient>
            </TouchableOpacity>
          ))}
        </ScrollView>
      )}

      {/* Expanded Card Songs - shows all songs, not just 6 */}
      {expandedCard && (
        <View style={RS.expandedSection}>
          <View style={RS.expandedHeader}>
            <Text style={[RS.expandedTitle, { color: expandedCard.color || '#FFF' }]}>{expandedCard.title}</Text>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
              {cardSongs.length > 0 && (
                <TouchableOpacity style={RS.playAllBtn} onPress={() => onPlayAll(cardSongs)}>
                  <Ionicons name="play" size={14} color="#FFF" />
                  <Text style={RS.playAllText}>Play All ({cardSongs.length})</Text>
                </TouchableOpacity>
              )}
              <TouchableOpacity onPress={() => setExpandedCard(null)}>
                <MaterialIcons name="close" size={20} color="#888" />
              </TouchableOpacity>
            </View>
          </View>
          {loadingCard ? <ActivityIndicator size="small" color="#8B5CF6" style={{ marginVertical: 16 }} /> : (
            <FlatList
              data={cardSongs}
              keyExtractor={(item, idx) => `exp-${item.id}-${idx}`}
              renderItem={({ item, index }) => (
                <TouchableOpacity style={RS.songRow} onPress={() => onPlaySong(item)}>
                  <Text style={RS.songIdx}>{index + 1}</Text>
                  <Image source={{ uri: item.image }} style={RS.songImg} />
                  <View style={{ flex: 1 }}>
                    <Text style={RS.songName} numberOfLines={1}>{item.name}</Text>
                    <Text style={RS.songArtist} numberOfLines={1}>{item.artist}</Text>
                  </View>
                </TouchableOpacity>
              )}
              style={{ maxHeight: 400 }}
              nestedScrollEnabled
              showsVerticalScrollIndicator={false}
              removeClippedSubviews
              initialNumToRender={10}
              maxToRenderPerBatch={5}
              windowSize={7}
            />
          )}
        </View>
      )}

      {/* Daily Mix Carousel */}
      {dailyMix.length > 0 && (
        <View style={{ marginTop: 12 }}>
          <View style={[RS.secHeader, { marginBottom: 8 }]}>
            <Text style={RS.secTitle}>Daily Mix</Text>
          </View>
          <FlatList data={dailyMix.slice(0, 15)} horizontal showsHorizontalScrollIndicator={false}
            contentContainerStyle={{ paddingHorizontal: 16 }}
            renderItem={({ item }) => (
              <TouchableOpacity style={RS.mixCard} onPress={() => onPlaySong(item)}>
                <Image source={{ uri: item.image }} style={RS.mixImg} />
                <Text style={RS.mixName} numberOfLines={1}>{item.name}</Text>
                <Text style={RS.mixArtist} numberOfLines={1}>{item.artist}</Text>
              </TouchableOpacity>
            )}
            keyExtractor={(item, idx) => `dm-${item.id}-${idx}`} />
        </View>
      )}

      {/* Discover Weekly */}
      {madeForYou.length > 0 && (
        <View style={{ marginTop: 16 }}>
          <View style={[RS.secHeader, { marginBottom: 8 }]}>
            <Text style={RS.secTitle}>Discover Weekly</Text>
          </View>
          <FlatList data={(() => {
            // Date-based shuffle so songs change daily
            const dayHash = Math.floor(Date.now() / 86400000);
            const shuffled = [...madeForYou].sort((a, b) => {
              const ha = ((a.id || '').charCodeAt(0) + dayHash) % 100;
              const hb = ((b.id || '').charCodeAt(0) + dayHash) % 100;
              return ha - hb;
            });
            return shuffled.slice(0, 15);
          })()} horizontal showsHorizontalScrollIndicator={false}
            contentContainerStyle={{ paddingHorizontal: 16 }}
            renderItem={({ item }) => (
              <TouchableOpacity style={RS.mixCard} onPress={() => onPlaySong(item)}>
                <Image source={{ uri: item.image }} style={RS.mixImg} />
                <Text style={RS.mixName} numberOfLines={1}>{item.name}</Text>
                <Text style={RS.mixArtist} numberOfLines={1}>{item.artist}</Text>
              </TouchableOpacity>
            )}
            keyExtractor={(item, idx) => `mfy-${item.id}-${idx}`} />
        </View>
      )}
    </View>
  );
}

// ========== TOP PICKS SECTION (7x7 grid, slidable) ==========
export function TopPicksSection({ songs, onPlaySong, onPlayAll }) {
  if (!songs || songs.length === 0) return null;

  const ROWS = 5;
  const totalNeeded = 50;
  const displaySongs = songs.slice(0, totalNeeded);

  // Split into columns of 5 rows each (10 cards)
  const columns = [];
  for (let i = 0; i < displaySongs.length; i += ROWS) {
    columns.push(displaySongs.slice(i, i + ROWS));
  }

  return (
    <View style={{ marginBottom: 20 }}>
      <View style={RS.secHeader}>
        <Text style={RS.secTitle}>Top Picks</Text>
        {displaySongs.length > 0 && (
          <TouchableOpacity onPress={() => onPlayAll(displaySongs)}>
            <Text style={RS.playAllLink}>Play All</Text>
          </TouchableOpacity>
        )}
      </View>
      <Text style={[RS.secSub, { paddingHorizontal: 16, marginBottom: 8 }]}>Based on your listening</Text>
      <FlatList
        data={columns}
        horizontal
        showsHorizontalScrollIndicator={false}
        pagingEnabled={false}
        snapToInterval={SW - 16}
        decelerationRate="fast"
        contentContainerStyle={{ paddingHorizontal: 16 }}
        keyExtractor={(_, idx) => `tp-col-${idx}`}
        renderItem={({ item: col, index: colIdx }) => (
          <View style={RS.topPickCol}>
            {col.map((song, rowIdx) => (
              <TouchableOpacity
                key={`tp-${song.id}-${rowIdx}`}
                style={RS.topPickRow}
                onPress={() => onPlaySong(song)}
                activeOpacity={0.7}
              >
                <Image source={{ uri: song.image }} style={RS.topPickImg} />
                <View style={{ flex: 1 }}>
                  <Text style={RS.topPickName} numberOfLines={1}>{song.name}</Text>
                  <Text style={RS.topPickArtist} numberOfLines={1}>{song.artist}</Text>
                </View>
                <Text style={RS.topPickDur}>
                  {Math.floor((song.duration || 0) / 60)}:{String(Math.floor((song.duration || 0) % 60)).padStart(2, '0')}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
        )}
      />
    </View>
  );
}

// ========== STYLES ==========
const RS = StyleSheet.create({
  secHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 16, marginBottom: 4 },
  secTitle: { fontSize: 18, fontWeight: '700', color: '#FFF' },
  secSub: { color: '#888', fontSize: 11, marginTop: 2 },
  // Reco cards
  recoCard: { width: 160, marginRight: 12, borderRadius: 14, overflow: 'hidden', borderWidth: 1 },
  recoCardGrad: { padding: 16, minHeight: 130, justifyContent: 'space-between' },
  recoCardTitle: { color: '#FFF', fontSize: 14, fontWeight: '700', marginTop: 10, lineHeight: 18 },
  recoCardSub: { color: '#aaa', fontSize: 11, marginTop: 4 },
  recoCardCount: { color: '#8B5CF6', fontSize: 10, fontWeight: '600', marginTop: 6 },
  // Expanded
  expandedSection: { marginHorizontal: 16, marginBottom: 16, backgroundColor: 'rgba(18,18,31,0.95)', borderRadius: 14, padding: 14, borderWidth: 1, borderColor: 'rgba(139,92,246,0.12)' },
  expandedHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 },
  expandedTitle: { fontSize: 16, fontWeight: '700', flex: 1 },
  playAllBtn: { flexDirection: 'row', alignItems: 'center', gap: 6, backgroundColor: '#8B5CF6', paddingVertical: 8, paddingHorizontal: 16, borderRadius: 20 },
  playAllText: { color: '#FFF', fontWeight: '600', fontSize: 12 },
  playAllLink: { color: '#8B5CF6', fontSize: 13, fontWeight: '600' },
  // Song row in expanded
  songRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 8, gap: 10 },
  songIdx: { color: '#666', fontWeight: '600', width: 24, fontSize: 12, textAlign: 'center' },
  songImg: { width: 42, height: 42, borderRadius: 6, backgroundColor: '#141424' },
  songName: { color: '#FFF', fontSize: 13, fontWeight: '600' },
  songArtist: { color: '#888', fontSize: 11 },
  // Mix cards
  mixCard: { width: 130, marginRight: 12 },
  mixImg: { width: 130, height: 130, borderRadius: 8, backgroundColor: '#141424', marginBottom: 6 },
  mixName: { color: '#FFF', fontSize: 12, fontWeight: '600' },
  mixArtist: { color: '#888', fontSize: 10 },
  // Top Picks
  topPickCol: { width: SW - 32, marginRight: 16, backgroundColor: 'rgba(18,18,31,0.6)', borderRadius: 14, padding: 12, borderWidth: 1, borderColor: 'rgba(139,92,246,0.08)' },
  topPickRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 8, gap: 12, borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.04)' },
  topPickIdx: { color: 'rgba(139,92,246,0.6)', fontWeight: '700', width: 22, fontSize: 13, textAlign: 'center' },
  topPickImg: { width: 48, height: 48, borderRadius: 10, backgroundColor: '#141424' },
  topPickName: { color: '#FFF', fontSize: 14, fontWeight: '600' },
  topPickArtist: { color: '#888', fontSize: 12 },
  topPickDur: { color: '#555', fontSize: 11 },
});
