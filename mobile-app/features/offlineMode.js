import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
  View, Text, TouchableOpacity, FlatList, Alert, ToastAndroid,
  StyleSheet, Switch, ActivityIndicator, Image, ScrollView
} from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { File, Directory, Paths } from 'expo-file-system';
import { MaterialIcons, Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';

// ========== OFFLINE MODE & SMART DOWNLOADS HOOK ==========
export function useOfflineMode({ likedSongs, downloadedSongs, setDownloadedSongs, setDlProgress, reloadDownloads, soundRef }) {
  const [offlineMode, setOfflineMode] = useState(false);
  const [autoDownloadEnabled, setAutoDownloadEnabled] = useState(false);
  const [downloadQuality, setDownloadQuality] = useState('high'); // low|medium|high
  const [storageInfo, setStorageInfo] = useState({ used: 0, count: 0 });
  const [resumePositions, setResumePositions] = useState({});
  const [downloadQueue, setDownloadQueue] = useState([]);
  const [isAutoDownloading, setIsAutoDownloading] = useState(false);
  const [cacheSettings, setCacheSettings] = useState({ maxCacheMB: 500, autoClean: true });
  const autoDownloadRef = useRef(false);

  // Load saved settings
  useEffect(() => {
    (async () => {
      try {
        const [om, ad, dq, rp, cs] = await Promise.all([
          AsyncStorage.getItem('offlineMode'),
          AsyncStorage.getItem('autoDownloadEnabled'),
          AsyncStorage.getItem('downloadQuality'),
          AsyncStorage.getItem('resumePositions'),
          AsyncStorage.getItem('cacheSettings'),
        ]);
        if (om) setOfflineMode(JSON.parse(om));
        if (ad) setAutoDownloadEnabled(JSON.parse(ad));
        if (dq) setDownloadQuality(dq);
        if (rp) setResumePositions(JSON.parse(rp));
        if (cs) setCacheSettings(JSON.parse(cs));
      } catch (e) { console.log('Offline load error:', e); }
    })();
  }, []);

  // Calculate storage on mount + when downloads change
  useEffect(() => {
    calculateStorage();
  }, [downloadedSongs]);

  const calculateStorage = useCallback(async () => {
    try {
      const dir = new Directory(Paths.document, 'NinaadaDownloads');
      if (!dir.exists) { setStorageInfo({ used: 0, count: 0 }); return; }
      let totalBytes = 0;
      let count = 0;
      // Estimate from downloaded songs list
      count = downloadedSongs?.length || 0;
      // Rough estimate: ~4MB per song average
      totalBytes = count * 4 * 1024 * 1024;
      setStorageInfo({ used: totalBytes, count });
    } catch (e) {
      setStorageInfo({ used: 0, count: downloadedSongs?.length || 0 });
    }
  }, [downloadedSongs]);

  // Toggle offline mode
  const toggleOfflineMode = useCallback(async (val) => {
    setOfflineMode(val);
    await AsyncStorage.setItem('offlineMode', JSON.stringify(val));
    ToastAndroid.show(val ? 'Offline Mode ON — playing downloads only' : 'Offline Mode OFF', ToastAndroid.SHORT);
  }, []);

  // Toggle auto-download
  const toggleAutoDownload = useCallback(async (val) => {
    setAutoDownloadEnabled(val);
    autoDownloadRef.current = val;
    await AsyncStorage.setItem('autoDownloadEnabled', JSON.stringify(val));
    if (val) {
      ToastAndroid.show('Auto-download enabled for liked songs', ToastAndroid.SHORT);
      autoDownloadLikedSongs();
    }
  }, [likedSongs, downloadedSongs]);

  // Set download quality
  const setQuality = useCallback(async (q) => {
    setDownloadQuality(q);
    await AsyncStorage.setItem('downloadQuality', q);
    ToastAndroid.show(`Download quality: ${q}`, ToastAndroid.SHORT);
  }, []);

  // Save resume position for a song
  const saveResumePosition = useCallback(async (songId, positionMs) => {
    if (!songId || !positionMs || positionMs < 5000) return; // Don't save if < 5s
    const upd = { ...resumePositions, [songId]: { position: positionMs, savedAt: Date.now() } };
    setResumePositions(upd);
    await AsyncStorage.setItem('resumePositions', JSON.stringify(upd)).catch(() => {});
  }, [resumePositions]);

  // Get resume position for a song
  const getResumePosition = useCallback((songId) => {
    if (!songId || !resumePositions[songId]) return 0;
    const saved = resumePositions[songId];
    // Expire after 7 days
    if (Date.now() - saved.savedAt > 7 * 24 * 60 * 60 * 1000) return 0;
    return saved.position;
  }, [resumePositions]);

  // Clear resume position
  const clearResumePosition = useCallback(async (songId) => {
    const upd = { ...resumePositions };
    delete upd[songId];
    setResumePositions(upd);
    await AsyncStorage.setItem('resumePositions', JSON.stringify(upd)).catch(() => {});
  }, [resumePositions]);

  // Auto-download liked songs that aren't yet downloaded
  const autoDownloadLikedSongs = useCallback(async () => {
    if (isAutoDownloading) return;
    const downloadedIds = new Set((downloadedSongs || []).map(s => s.id));
    const toDownload = (likedSongs || []).filter(s => !downloadedIds.has(s.id) && s.media_url);
    if (toDownload.length === 0) return;

    setIsAutoDownloading(true);
    setDownloadQueue(toDownload.map(s => s.name));

    for (const song of toDownload) {
      if (!autoDownloadRef.current) break; // Stop if disabled
      try {
        const safe = (song.name || 'song').replace(/[^a-z0-9.\-_]/gi, '_');
        const dir = new Directory(Paths.document, 'NinaadaDownloads');
        if (!dir.exists) dir.create();
        const dl = await File.downloadFileAsync(song.media_url, new File(dir, `${safe}.mp3`));
        if (dl?.exists) {
          const stored = JSON.parse(await AsyncStorage.getItem('downloadedSongs') || '[]');
          const upd = [...stored.filter(s => s.id !== song.id), { ...song, localUri: dl.uri, downloadedAt: new Date().toISOString() }];
          await AsyncStorage.setItem('downloadedSongs', JSON.stringify(upd));
        }
      } catch (e) { console.log('Auto-download error:', e); }
      setDownloadQueue(prev => prev.filter(n => n !== song.name));
    }

    setIsAutoDownloading(false);
    if (reloadDownloads) reloadDownloads();
    ToastAndroid.show('Auto-download complete!', ToastAndroid.SHORT);
  }, [likedSongs, downloadedSongs, isAutoDownloading]);

  // Smart cache cleanup — remove oldest downloads when storage exceeds limit
  const smartCacheCleanup = useCallback(async () => {
    const maxBytes = cacheSettings.maxCacheMB * 1024 * 1024;
    if (storageInfo.used <= maxBytes) return;

    const sorted = [...(downloadedSongs || [])].sort((a, b) => {
      const aDate = a.downloadedAt ? new Date(a.downloadedAt).getTime() : 0;
      const bDate = b.downloadedAt ? new Date(b.downloadedAt).getTime() : 0;
      return aDate - bDate; // oldest first
    });

    let freed = 0;
    const toRemove = [];
    for (const song of sorted) {
      if (storageInfo.used - freed <= maxBytes) break;
      toRemove.push(song.id);
      freed += 4 * 1024 * 1024; // estimate 4MB per song
    }

    if (toRemove.length > 0) {
      for (const id of toRemove) {
        const song = downloadedSongs.find(s => s.id === id);
        if (song?.localUri) {
          try { const f = new File(song.localUri); if (f.exists) f.delete(); } catch (e) {}
        }
      }
      const upd = downloadedSongs.filter(s => !toRemove.includes(s.id));
      if (setDownloadedSongs) setDownloadedSongs(upd);
      await AsyncStorage.setItem('downloadedSongs', JSON.stringify(upd));
      ToastAndroid.show(`Cleaned ${toRemove.length} old downloads`, ToastAndroid.SHORT);
    }
  }, [downloadedSongs, storageInfo, cacheSettings]);

  // Clear all downloads
  const clearAllDownloads = useCallback(async () => {
    Alert.alert('Clear All Downloads?', 'This will remove all downloaded songs.', [
      { text: 'Cancel' },
      {
        text: 'Clear All', style: 'destructive', onPress: async () => {
          try {
            const dir = new Directory(Paths.document, 'NinaadaDownloads');
            if (dir.exists) dir.delete();
            if (setDownloadedSongs) setDownloadedSongs([]);
            await AsyncStorage.setItem('downloadedSongs', JSON.stringify([]));
            ToastAndroid.show('All downloads cleared', ToastAndroid.SHORT);
          } catch (e) { Alert.alert('Error', e.message); }
        }
      }
    ]);
  }, []);

  // Update cache settings
  const updateCacheSettings = useCallback(async (newSettings) => {
    const upd = { ...cacheSettings, ...newSettings };
    setCacheSettings(upd);
    await AsyncStorage.setItem('cacheSettings', JSON.stringify(upd));
  }, [cacheSettings]);

  return {
    offlineMode, toggleOfflineMode,
    autoDownloadEnabled, toggleAutoDownload,
    downloadQuality, setQuality,
    storageInfo, calculateStorage,
    resumePositions, saveResumePosition, getResumePosition, clearResumePosition,
    downloadQueue, isAutoDownloading, autoDownloadLikedSongs,
    smartCacheCleanup, clearAllDownloads,
    cacheSettings, updateCacheSettings,
  };
}

// ========== OFFLINE SETTINGS PANEL COMPONENT ==========
export function OfflineSettingsPanel({
  offlineMode, toggleOfflineMode,
  autoDownloadEnabled, toggleAutoDownload,
  downloadQuality, setQuality,
  storageInfo, clearAllDownloads,
  cacheSettings, updateCacheSettings,
  isAutoDownloading, downloadQueue,
  smartCacheCleanup,
}) {
  const formatBytes = (bytes) => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
  };

  return (
    <ScrollView style={OS.container} contentContainerStyle={{ paddingBottom: 30 }}>
      {/* Offline Mode Toggle */}
      <View style={OS.section}>
        <View style={OS.row}>
          <View style={OS.rowLeft}>
            <Ionicons name="cloud-offline-outline" size={22} color="#FF6B35" />
            <View style={{ marginLeft: 12 }}>
              <Text style={OS.rowTitle}>Offline Mode</Text>
              <Text style={OS.rowSub}>Play only downloaded songs</Text>
            </View>
          </View>
          <Switch value={offlineMode} onValueChange={toggleOfflineMode}
            trackColor={{ false: '#333', true: '#8B5CF666' }} thumbColor={offlineMode ? '#8B5CF6' : '#888'} />
        </View>
      </View>

      {/* Auto Download */}
      <View style={OS.section}>
        <View style={OS.row}>
          <View style={OS.rowLeft}>
            <Ionicons name="download-outline" size={22} color="#8B5CF6" />
            <View style={{ marginLeft: 12 }}>
              <Text style={OS.rowTitle}>Auto-Download Liked Songs</Text>
              <Text style={OS.rowSub}>Automatically download songs you like</Text>
            </View>
          </View>
          <Switch value={autoDownloadEnabled} onValueChange={toggleAutoDownload}
            trackColor={{ false: '#333', true: '#8B5CF666' }} thumbColor={autoDownloadEnabled ? '#8B5CF6' : '#888'} />
        </View>
        {isAutoDownloading && (
          <View style={OS.autoDownloadStatus}>
            <ActivityIndicator size="small" color="#8B5CF6" />
            <Text style={OS.autoDownloadText}>Downloading... {downloadQueue.length} remaining</Text>
          </View>
        )}
      </View>

      {/* Download Quality */}
      <View style={OS.section}>
        <Text style={OS.sectionTitle}>Download Quality</Text>
        <View style={OS.qualityRow}>
          {[
            { key: 'low', label: 'Low', desc: '~1MB/song', color: '#2A9D8F' },
            { key: 'medium', label: 'Medium', desc: '~3MB/song', color: '#FFD700' },
            { key: 'high', label: 'High', desc: '~5MB/song', color: '#FF6B35' },
          ].map(q => (
            <TouchableOpacity key={q.key}
              style={[OS.qualityBtn, downloadQuality === q.key && { borderColor: q.color, backgroundColor: q.color + '22' }]}
              onPress={() => setQuality(q.key)}>
              <Text style={[OS.qualityLabel, downloadQuality === q.key && { color: q.color }]}>{q.label}</Text>
              <Text style={OS.qualityDesc}>{q.desc}</Text>
            </TouchableOpacity>
          ))}
        </View>
      </View>

      {/* Storage Info */}
      <View style={OS.section}>
        <Text style={OS.sectionTitle}>Storage</Text>
        <View style={OS.storageCard}>
          <View style={OS.storageRow}>
            <MaterialIcons name="storage" size={20} color="#8B5CF6" />
            <Text style={OS.storageText}>{storageInfo.count} songs · {formatBytes(storageInfo.used)}</Text>
          </View>
          <View style={OS.storageBar}>
            <View style={[OS.storageBarFill, { width: `${Math.min((storageInfo.used / (cacheSettings.maxCacheMB * 1024 * 1024)) * 100, 100)}%` }]} />
          </View>
          <Text style={OS.storageLimit}>Limit: {cacheSettings.maxCacheMB} MB</Text>
        </View>

        {/* Cache limit buttons */}
        <View style={OS.cacheLimitRow}>
          {[200, 500, 1000, 2000].map(mb => (
            <TouchableOpacity key={mb}
              style={[OS.cacheLimitBtn, cacheSettings.maxCacheMB === mb && OS.cacheLimitBtnOn]}
              onPress={() => updateCacheSettings({ maxCacheMB: mb })}>
              <Text style={[OS.cacheLimitText, cacheSettings.maxCacheMB === mb && { color: '#8B5CF6' }]}>
                {mb >= 1000 ? `${mb / 1000}GB` : `${mb}MB`}
              </Text>
            </TouchableOpacity>
          ))}
        </View>
      </View>

      {/* Actions */}
      <View style={OS.section}>
        <TouchableOpacity style={OS.actionBtn} onPress={smartCacheCleanup}>
          <MaterialIcons name="cleaning-services" size={20} color="#FFD700" />
          <Text style={OS.actionText}>Smart Cache Cleanup</Text>
        </TouchableOpacity>
        <TouchableOpacity style={[OS.actionBtn, { borderColor: '#FF525244' }]} onPress={clearAllDownloads}>
          <MaterialIcons name="delete-sweep" size={20} color="#FF5252" />
          <Text style={[OS.actionText, { color: '#FF5252' }]}>Clear All Downloads</Text>
        </TouchableOpacity>
      </View>
    </ScrollView>
  );
}

// ========== STYLES ==========
const OS = StyleSheet.create({
  container: { flex: 1 },
  section: { marginBottom: 20, paddingHorizontal: 16 },
  sectionTitle: { color: '#FFF', fontSize: 16, fontWeight: '700', marginBottom: 12 },
  row: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', backgroundColor: '#12121f', padding: 16, borderRadius: 12 },
  rowLeft: { flexDirection: 'row', alignItems: 'center', flex: 1 },
  rowTitle: { color: '#FFF', fontSize: 14, fontWeight: '600' },
  rowSub: { color: '#888', fontSize: 11, marginTop: 2 },
  qualityRow: { flexDirection: 'row', gap: 10 },
  qualityBtn: { flex: 1, paddingVertical: 14, borderRadius: 12, alignItems: 'center', backgroundColor: '#12121f', borderWidth: 1, borderColor: '#1e1e38' },
  qualityLabel: { color: '#CCC', fontSize: 14, fontWeight: '700' },
  qualityDesc: { color: '#666', fontSize: 10, marginTop: 4 },
  storageCard: { backgroundColor: '#12121f', borderRadius: 12, padding: 16 },
  storageRow: { flexDirection: 'row', alignItems: 'center', gap: 10, marginBottom: 10 },
  storageText: { color: '#FFF', fontSize: 14, fontWeight: '600' },
  storageBar: { height: 6, backgroundColor: '#333', borderRadius: 3, overflow: 'hidden' },
  storageBarFill: { height: 6, backgroundColor: '#8B5CF6', borderRadius: 3 },
  storageLimit: { color: '#666', fontSize: 11, marginTop: 6, textAlign: 'right' },
  cacheLimitRow: { flexDirection: 'row', gap: 8, marginTop: 12 },
  cacheLimitBtn: { flex: 1, paddingVertical: 10, borderRadius: 10, alignItems: 'center', backgroundColor: '#12121f', borderWidth: 1, borderColor: '#1e1e38' },
  cacheLimitBtnOn: { borderColor: '#8B5CF6', backgroundColor: 'rgba(29,185,84,0.15)' },
  cacheLimitText: { color: '#888', fontSize: 12, fontWeight: '600' },
  autoDownloadStatus: { flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 10, paddingHorizontal: 16 },
  autoDownloadText: { color: '#8B5CF6', fontSize: 12 },
  actionBtn: { flexDirection: 'row', alignItems: 'center', gap: 12, backgroundColor: '#12121f', padding: 16, borderRadius: 12, marginBottom: 8, borderWidth: 1, borderColor: '#1e1e38' },
  actionText: { color: '#FFF', fontSize: 14, fontWeight: '600' },
});
