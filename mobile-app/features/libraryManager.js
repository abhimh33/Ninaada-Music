import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, TouchableOpacity, FlatList, Modal, Alert, ToastAndroid,
  StyleSheet, TextInput, Image, ScrollView, Dimensions, Switch, Share
} from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { MaterialIcons, Ionicons, Feather } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { File, Directory, Paths } from 'expo-file-system';

const { width: SW } = Dimensions.get('window');
const fmt = (sec) => { const m = Math.floor(sec / 60), s = Math.floor(sec % 60); return `${m}:${s < 10 ? '0' : ''}${s}`; };

// ========== ADVANCED LIBRARY MANAGER HOOK ==========
export function useLibraryManager({ playlists, setPlaylists, downloadedSongs, setDownloadedSongs, likedSongs, setLikedSongs, playCounts }) {
  const [smartFolders, setSmartFolders] = useState([]);
  const [librarySortBy, setLibrarySortBy] = useState('name'); // name|artist|date|plays|duration
  const [librarySortOrder, setLibrarySortOrder] = useState('asc');
  const [multiSelectMode, setMultiSelectMode] = useState(false);
  const [selectedItems, setSelectedItems] = useState(new Set());
  const [showImportExport, setShowImportExport] = useState(false);
  const [showSortModal, setShowSortModal] = useState(false);
  const [showDuplicates, setShowDuplicates] = useState(false);
  const [duplicates, setDuplicates] = useState([]);

  // Generate smart folders from library data
  const generateSmartFolders = useCallback(() => {
    const folders = [];
    const allSongs = [...(likedSongs || []), ...(downloadedSongs || [])];

    // By Language
    const langMap = {};
    allSongs.forEach(s => {
      const lang = s.language || 'Unknown';
      if (!langMap[lang]) langMap[lang] = [];
      if (!langMap[lang].find(x => x.id === s.id)) langMap[lang].push(s);
    });
    Object.entries(langMap).forEach(([lang, songs]) => {
      if (songs.length >= 2) {
        folders.push({
          id: `lang-${lang}`, name: lang.charAt(0).toUpperCase() + lang.slice(1),
          type: 'language', icon: 'language', color: '#8B5CF6', songs, count: songs.length,
        });
      }
    });

    // By Artist (top artists)
    const artistMap = {};
    allSongs.forEach(s => {
      const artist = (s.artist || s.primary_artists || '').split(',')[0].trim();
      if (artist && artist !== 'Unknown Artist') {
        if (!artistMap[artist]) artistMap[artist] = [];
        if (!artistMap[artist].find(x => x.id === s.id)) artistMap[artist].push(s);
      }
    });
    Object.entries(artistMap)
      .sort((a, b) => b[1].length - a[1].length)
      .slice(0, 10)
      .forEach(([artist, songs]) => {
        if (songs.length >= 2) {
          folders.push({
            id: `artist-${artist}`, name: artist,
            type: 'artist', icon: 'person', color: '#7B2FBE', songs, count: songs.length,
          });
        }
      });

    // By Year
    const yearMap = {};
    allSongs.forEach(s => {
      const year = s.year || '';
      if (year) {
        if (!yearMap[year]) yearMap[year] = [];
        if (!yearMap[year].find(x => x.id === s.id)) yearMap[year].push(s);
      }
    });
    Object.entries(yearMap)
      .sort((a, b) => b[0].localeCompare(a[0]))
      .slice(0, 8)
      .forEach(([year, songs]) => {
        if (songs.length >= 2) {
          folders.push({
            id: `year-${year}`, name: year,
            type: 'year', icon: 'calendar-today', color: '#FF6B35', songs, count: songs.length,
          });
        }
      });

    // Most Played (from playCounts)
    const mostPlayed = Object.values(playCounts || {})
      .sort((a, b) => b.count - a.count)
      .slice(0, 20)
      .map(pc => ({ ...pc.song, playCount: pc.count }))
      .filter(s => s.id);
    if (mostPlayed.length >= 3) {
      folders.push({
        id: 'most-played', name: 'Most Played',
        type: 'smart', icon: 'trending-up', color: '#FF4D6D', songs: mostPlayed, count: mostPlayed.length,
      });
    }

    // Recently Downloaded
    const recentDl = (downloadedSongs || [])
      .filter(s => s.downloadedAt)
      .sort((a, b) => new Date(b.downloadedAt) - new Date(a.downloadedAt))
      .slice(0, 15);
    if (recentDl.length >= 2) {
      folders.push({
        id: 'recent-downloads', name: 'Recent Downloads',
        type: 'smart', icon: 'cloud-download', color: '#00B4D8', songs: recentDl, count: recentDl.length,
      });
    }

    // Long Songs (> 5 min)
    const longSongs = allSongs.filter(s => parseInt(s.duration || 0) > 300);
    if (longSongs.length >= 2) {
      folders.push({
        id: 'long-songs', name: 'Extended Plays',
        type: 'smart', icon: 'timer', color: '#2A9D8F', songs: longSongs, count: longSongs.length,
      });
    }

    setSmartFolders(folders);
    return folders;
  }, [likedSongs, downloadedSongs, playCounts]);

  // Detect duplicates across library
  const detectDuplicates = useCallback(() => {
    const allSongs = [
      ...(likedSongs || []).map(s => ({ ...s, _source: 'liked' })),
      ...(downloadedSongs || []).map(s => ({ ...s, _source: 'downloaded' })),
    ];

    const nameMap = {};
    allSongs.forEach(s => {
      const key = `${(s.name || '').toLowerCase().trim()}-${(s.artist || '').toLowerCase().trim()}`;
      if (!nameMap[key]) nameMap[key] = [];
      nameMap[key].push(s);
    });

    const dupes = Object.entries(nameMap)
      .filter(([_, songs]) => songs.length > 1)
      .map(([key, songs]) => ({
        key, name: songs[0].name, artist: songs[0].artist,
        copies: songs.length, songs,
      }));

    setDuplicates(dupes);
    setShowDuplicates(true);
    if (dupes.length === 0) {
      ToastAndroid.show('No duplicates found!', ToastAndroid.SHORT);
    }
    return dupes;
  }, [likedSongs, downloadedSongs]);

  // Sort songs
  const sortSongs = useCallback((songs, sortBy = librarySortBy, order = librarySortOrder) => {
    const sorted = [...songs].sort((a, b) => {
      let cmp = 0;
      switch (sortBy) {
        case 'name':
          cmp = (a.name || '').localeCompare(b.name || '');
          break;
        case 'artist':
          cmp = (a.artist || '').localeCompare(b.artist || '');
          break;
        case 'date':
          const aDate = a.downloadedAt || a.year || '';
          const bDate = b.downloadedAt || b.year || '';
          cmp = bDate.localeCompare(aDate);
          break;
        case 'plays':
          const aPlays = (playCounts || {})[a.id]?.count || 0;
          const bPlays = (playCounts || {})[b.id]?.count || 0;
          cmp = bPlays - aPlays;
          break;
        case 'duration':
          cmp = parseInt(a.duration || 0) - parseInt(b.duration || 0);
          break;
        default:
          cmp = 0;
      }
      return order === 'desc' ? -cmp : cmp;
    });
    return sorted;
  }, [librarySortBy, librarySortOrder, playCounts]);

  // Multi-select toggle
  const toggleSelect = useCallback((songId) => {
    setSelectedItems(prev => {
      const next = new Set(prev);
      if (next.has(songId)) next.delete(songId);
      else next.add(songId);
      return next;
    });
  }, []);

  const selectAll = useCallback((songs) => {
    setSelectedItems(new Set(songs.map(s => s.id)));
  }, []);

  const clearSelection = useCallback(() => {
    setSelectedItems(new Set());
    setMultiSelectMode(false);
  }, []);

  // Bulk operations
  const bulkAddToPlaylist = useCallback(async (playlistId) => {
    if (selectedItems.size === 0) return;
    const allSongs = [...(likedSongs || []), ...(downloadedSongs || [])];
    const toAdd = allSongs.filter(s => selectedItems.has(s.id));

    const upd = playlists.map(p => {
      if (p.id === playlistId) {
        const existing = new Set((p.songs || []).map(s => s.id));
        const newSongs = toAdd.filter(s => !existing.has(s.id));
        return { ...p, songs: [...(p.songs || []), ...newSongs] };
      }
      return p;
    });

    setPlaylists(upd);
    await AsyncStorage.setItem('playlists', JSON.stringify(upd));
    clearSelection();
    ToastAndroid.show(`Added ${toAdd.length} songs to playlist`, ToastAndroid.SHORT);
  }, [selectedItems, likedSongs, downloadedSongs, playlists]);

  const bulkDelete = useCallback(async (source) => {
    if (selectedItems.size === 0) return;

    Alert.alert('Delete Selected?', `Remove ${selectedItems.size} songs from ${source}?`, [
      { text: 'Cancel' },
      {
        text: 'Delete', style: 'destructive', onPress: async () => {
          if (source === 'liked') {
            const upd = likedSongs.filter(s => !selectedItems.has(s.id));
            setLikedSongs(upd);
            await AsyncStorage.setItem('likedSongs', JSON.stringify(upd));
          } else if (source === 'downloads') {
            // Delete files
            for (const id of selectedItems) {
              const song = downloadedSongs.find(s => s.id === id);
              if (song?.localUri) {
                try { const f = new File(song.localUri); if (f.exists) f.delete(); } catch (e) {}
              }
            }
            const upd = downloadedSongs.filter(s => !selectedItems.has(s.id));
            setDownloadedSongs(upd);
            await AsyncStorage.setItem('downloadedSongs', JSON.stringify(upd));
          }
          clearSelection();
          ToastAndroid.show('Deleted selected songs', ToastAndroid.SHORT);
        }
      }
    ]);
  }, [selectedItems, likedSongs, downloadedSongs]);

  const bulkLike = useCallback(async () => {
    if (selectedItems.size === 0) return;
    const allSongs = [...(likedSongs || []), ...(downloadedSongs || [])];
    const toAdd = allSongs.filter(s => selectedItems.has(s.id));
    const existingIds = new Set(likedSongs.map(s => s.id));
    const newLiked = toAdd.filter(s => !existingIds.has(s.id));
    const upd = [...likedSongs, ...newLiked];
    setLikedSongs(upd);
    await AsyncStorage.setItem('likedSongs', JSON.stringify(upd));
    clearSelection();
    ToastAndroid.show(`Liked ${newLiked.length} songs`, ToastAndroid.SHORT);
  }, [selectedItems, likedSongs, downloadedSongs]);

  // Export library as JSON
  const exportLibrary = useCallback(async () => {
    try {
      const data = {
        exportDate: new Date().toISOString(),
        appVersion: '1.0',
        playlists: playlists.map(p => ({
          name: p.name,
          songs: (p.songs || []).map(s => ({ id: s.id, name: s.name, artist: s.artist, image: s.image, duration: s.duration, media_url: s.media_url })),
        })),
        likedSongs: likedSongs.map(s => ({ id: s.id, name: s.name, artist: s.artist, image: s.image, duration: s.duration, media_url: s.media_url })),
        playCounts: playCounts,
      };
      const json = JSON.stringify(data, null, 2);
      // Save to file
      const dir = new Directory(Paths.document, 'NinaadaBackups');
      if (!dir.exists) dir.create();
      const filename = `ninaada_backup_${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
      const file = new File(dir, filename);
      file.text = json;

      // Also offer to share
      await Share.share({ message: json, title: 'Ninaada Library Backup' });
      ToastAndroid.show(`Exported to ${filename}`, ToastAndroid.LONG);
    } catch (e) {
      Alert.alert('Export Error', e.message);
    }
  }, [playlists, likedSongs, playCounts]);

  // Import library from JSON
  const importLibrary = useCallback(async (jsonString) => {
    try {
      const data = JSON.parse(jsonString);
      if (!data.playlists && !data.likedSongs) {
        Alert.alert('Invalid Format', 'This does not look like a Ninaada backup.');
        return;
      }

      let imported = { playlists: 0, liked: 0 };

      if (data.playlists) {
        const newPlaylists = data.playlists.map(p => ({
          id: Date.now().toString() + Math.random().toString(36).slice(2, 6),
          name: p.name + ' (imported)',
          songs: p.songs || [],
        }));
        const upd = [...playlists, ...newPlaylists];
        setPlaylists(upd);
        await AsyncStorage.setItem('playlists', JSON.stringify(upd));
        imported.playlists = newPlaylists.length;
      }

      if (data.likedSongs) {
        const existingIds = new Set(likedSongs.map(s => s.id));
        const newLiked = data.likedSongs.filter(s => !existingIds.has(s.id));
        const upd = [...likedSongs, ...newLiked];
        setLikedSongs(upd);
        await AsyncStorage.setItem('likedSongs', JSON.stringify(upd));
        imported.liked = newLiked.length;
      }

      ToastAndroid.show(`Imported ${imported.playlists} playlists, ${imported.liked} liked songs`, ToastAndroid.LONG);
    } catch (e) {
      Alert.alert('Import Error', 'Failed to parse backup data: ' + e.message);
    }
  }, [playlists, likedSongs]);

  // Refresh smart folders on data change
  useEffect(() => {
    if (likedSongs?.length > 0 || downloadedSongs?.length > 0) {
      generateSmartFolders();
    }
  }, [likedSongs, downloadedSongs, playCounts]);

  return {
    smartFolders, generateSmartFolders,
    librarySortBy, setLibrarySortBy,
    librarySortOrder, setLibrarySortOrder,
    showSortModal, setShowSortModal,
    multiSelectMode, setMultiSelectMode,
    selectedItems, toggleSelect, selectAll, clearSelection,
    bulkAddToPlaylist, bulkDelete, bulkLike,
    showImportExport, setShowImportExport,
    exportLibrary, importLibrary,
    duplicates, showDuplicates, setShowDuplicates, detectDuplicates,
    sortSongs,
  };
}

// ========== SMART FOLDERS VIEW ==========
export function SmartFoldersView({ smartFolders, onPlaySong, onPlayAll }) {
  const [selectedFolder, setSelectedFolder] = useState(null);

  if (selectedFolder) {
    return (
      <View style={{ flex: 1 }}>
        <View style={LS.folderHeader}>
          <TouchableOpacity onPress={() => setSelectedFolder(null)}>
            <Ionicons name="chevron-back" size={24} color="#FFF" />
          </TouchableOpacity>
          <MaterialIcons name={selectedFolder.icon} size={22} color={selectedFolder.color} />
          <Text style={LS.folderHeaderTitle}>{selectedFolder.name}</Text>
          <Text style={LS.folderHeaderCount}>{selectedFolder.count}</Text>
        </View>
        {selectedFolder.songs.length > 0 && (
          <TouchableOpacity style={LS.playAllBtn} onPress={() => onPlayAll(selectedFolder.songs)}>
            <Ionicons name="play" size={14} color="#FFF" />
            <Text style={LS.playAllText}>Play All</Text>
          </TouchableOpacity>
        )}
        <FlatList data={selectedFolder.songs} keyExtractor={(item, idx) => `sf-${item.id}-${idx}`}
          contentContainerStyle={{ paddingBottom: 20 }}
          renderItem={({ item, index }) => (
            <TouchableOpacity style={LS.songRow} onPress={() => onPlaySong(item)}>
              <Text style={LS.songIdx}>{index + 1}</Text>
              <Image source={{ uri: item.image }} style={LS.songImg} />
              <View style={{ flex: 1 }}>
                <Text style={LS.songName} numberOfLines={1}>{item.name}</Text>
                <Text style={LS.songArtist} numberOfLines={1}>{item.artist}</Text>
              </View>
              <Text style={LS.songDur}>{fmt(parseInt(item.duration || 0))}</Text>
            </TouchableOpacity>
          )} />
      </View>
    );
  }

  return (
    <View style={{ flex: 1 }}>
      <Text style={LS.sectionTitle}>Smart Folders</Text>
      <Text style={LS.sectionSub}>Auto-organized from your library</Text>
      <FlatList data={smartFolders} keyExtractor={item => item.id} numColumns={2}
        columnWrapperStyle={{ gap: 10, paddingHorizontal: 16, marginBottom: 10 }}
        contentContainerStyle={{ paddingBottom: 20, paddingTop: 8 }}
        renderItem={({ item }) => (
          <TouchableOpacity style={[LS.folderCard, { borderColor: item.color + '44' }]}
            onPress={() => setSelectedFolder(item)} activeOpacity={0.7}>
            <LinearGradient colors={[item.color + '22', '#0a0a14']} style={LS.folderGrad}>
              <MaterialIcons name={item.icon} size={28} color={item.color} />
              <Text style={LS.folderName} numberOfLines={1}>{item.name}</Text>
              <Text style={LS.folderCount}>{item.count} songs</Text>
              <Text style={LS.folderType}>{item.type}</Text>
            </LinearGradient>
          </TouchableOpacity>
        )}
        ListEmptyComponent={
          <View style={{ alignItems: 'center', paddingTop: 40 }}>
            <MaterialIcons name="folder-open" size={50} color="#333" />
            <Text style={{ color: '#888', marginTop: 8 }}>Add more songs to see smart folders</Text>
          </View>
        } />
    </View>
  );
}

// ========== BULK ACTIONS BAR ==========
export function BulkActionsBar({ selectedCount, onLike, onAddToPlaylist, onDelete, onCancel, source }) {
  if (selectedCount === 0) return null;

  return (
    <View style={LS.bulkBar}>
      <Text style={LS.bulkCount}>{selectedCount} selected</Text>
      <View style={LS.bulkActions}>
        <TouchableOpacity style={LS.bulkBtn} onPress={onLike}>
          <Ionicons name="heart" size={18} color="#FF4D6D" />
        </TouchableOpacity>
        <TouchableOpacity style={LS.bulkBtn} onPress={onAddToPlaylist}>
          <MaterialIcons name="playlist-add" size={20} color="#8B5CF6" />
        </TouchableOpacity>
        <TouchableOpacity style={LS.bulkBtn} onPress={onDelete}>
          <MaterialIcons name="delete" size={18} color="#FF5252" />
        </TouchableOpacity>
        <TouchableOpacity style={LS.bulkBtn} onPress={onCancel}>
          <MaterialIcons name="close" size={18} color="#888" />
        </TouchableOpacity>
      </View>
    </View>
  );
}

// ========== SORT MODAL ==========
export function SortModal({ visible, onClose, sortBy, setSortBy, sortOrder, setSortOrder }) {
  const options = [
    { key: 'name', label: 'Name', icon: 'sort-by-alpha' },
    { key: 'artist', label: 'Artist', icon: 'person' },
    { key: 'date', label: 'Date Added', icon: 'calendar-today' },
    { key: 'plays', label: 'Play Count', icon: 'trending-up' },
    { key: 'duration', label: 'Duration', icon: 'timer' },
  ];

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <View style={LS.modalOverlay}>
        <View style={LS.sortModal}>
          <Text style={LS.sortTitle}>Sort By</Text>
          {options.map(opt => (
            <TouchableOpacity key={opt.key} style={[LS.sortOpt, sortBy === opt.key && LS.sortOptOn]}
              onPress={() => { setSortBy(opt.key); }}>
              <MaterialIcons name={opt.icon} size={18} color={sortBy === opt.key ? '#8B5CF6' : '#888'} />
              <Text style={[LS.sortOptText, sortBy === opt.key && { color: '#8B5CF6' }]}>{opt.label}</Text>
              {sortBy === opt.key && <Ionicons name="checkmark" size={18} color="#8B5CF6" />}
            </TouchableOpacity>
          ))}
          <View style={LS.orderRow}>
            <TouchableOpacity style={[LS.orderBtn, sortOrder === 'asc' && LS.orderBtnOn]}
              onPress={() => setSortOrder('asc')}>
              <MaterialIcons name="arrow-upward" size={16} color={sortOrder === 'asc' ? '#8B5CF6' : '#888'} />
              <Text style={[LS.orderText, sortOrder === 'asc' && { color: '#8B5CF6' }]}>Ascending</Text>
            </TouchableOpacity>
            <TouchableOpacity style={[LS.orderBtn, sortOrder === 'desc' && LS.orderBtnOn]}
              onPress={() => setSortOrder('desc')}>
              <MaterialIcons name="arrow-downward" size={16} color={sortOrder === 'desc' ? '#8B5CF6' : '#888'} />
              <Text style={[LS.orderText, sortOrder === 'desc' && { color: '#8B5CF6' }]}>Descending</Text>
            </TouchableOpacity>
          </View>
          <TouchableOpacity style={LS.closeBtn} onPress={onClose}>
            <Text style={LS.closeBtnText}>Done</Text>
          </TouchableOpacity>
        </View>
      </View>
    </Modal>
  );
}

// ========== IMPORT/EXPORT MODAL ==========
export function ImportExportModal({ visible, onClose, onExport, onImport }) {
  const [importText, setImportText] = useState('');

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <View style={LS.modalOverlay}>
        <View style={LS.ieModal}>
          <Text style={LS.ieTitle}>Import / Export Library</Text>

          <TouchableOpacity style={LS.ieBtn} onPress={onExport}>
            <MaterialIcons name="file-upload" size={22} color="#8B5CF6" />
            <View style={{ flex: 1, marginLeft: 12 }}>
              <Text style={LS.ieBtnTitle}>Export Library</Text>
              <Text style={LS.ieBtnSub}>Save playlists, likes & play counts as JSON</Text>
            </View>
            <Ionicons name="chevron-forward" size={18} color="#666" />
          </TouchableOpacity>

          <View style={LS.ieDivider} />

          <Text style={[LS.ieLabel, { marginTop: 16 }]}>Import from JSON</Text>
          <TextInput style={LS.ieInput} placeholder="Paste backup JSON here..." placeholderTextColor="#666"
            value={importText} onChangeText={setImportText} multiline numberOfLines={4} />
          <TouchableOpacity style={[LS.ieImportBtn, !importText.trim() && { opacity: 0.5 }]}
            onPress={() => { if (importText.trim()) { onImport(importText); setImportText(''); } }}
            disabled={!importText.trim()}>
            <MaterialIcons name="file-download" size={18} color="#FFF" />
            <Text style={LS.ieImportText}>Import</Text>
          </TouchableOpacity>

          <TouchableOpacity style={LS.closeBtn} onPress={onClose}>
            <Text style={LS.closeBtnText}>Close</Text>
          </TouchableOpacity>
        </View>
      </View>
    </Modal>
  );
}

// ========== DUPLICATE DETECTOR VIEW ==========
export function DuplicateDetectorModal({ visible, onClose, duplicates }) {
  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <View style={LS.modalOverlay}>
        <View style={LS.dupeModal}>
          <View style={LS.dupeHeader}>
            <Text style={LS.dupeTitle}>Duplicate Songs</Text>
            <TouchableOpacity onPress={onClose}>
              <MaterialIcons name="close" size={24} color="#8B5CF6" />
            </TouchableOpacity>
          </View>
          {duplicates.length === 0 ? (
            <View style={{ alignItems: 'center', paddingVertical: 30 }}>
              <Ionicons name="checkmark-circle" size={50} color="#8B5CF6" />
              <Text style={{ color: '#FFF', fontSize: 16, fontWeight: '600', marginTop: 12 }}>No Duplicates Found!</Text>
              <Text style={{ color: '#888', fontSize: 12, marginTop: 4 }}>Your library is clean</Text>
            </View>
          ) : (
            <FlatList data={duplicates} keyExtractor={item => item.key}
              renderItem={({ item }) => (
                <View style={LS.dupeRow}>
                  <View style={{ flex: 1 }}>
                    <Text style={LS.dupeName}>{item.name}</Text>
                    <Text style={LS.dupeArtist}>{item.artist}</Text>
                  </View>
                  <View style={LS.dupeBadge}>
                    <Text style={LS.dupeBadgeText}>{item.copies}x</Text>
                  </View>
                </View>
              )} />
          )}
          <TouchableOpacity style={LS.closeBtn} onPress={onClose}>
            <Text style={LS.closeBtnText}>Close</Text>
          </TouchableOpacity>
        </View>
      </View>
    </Modal>
  );
}

// ========== STYLES ==========
const LS = StyleSheet.create({
  sectionTitle: { color: '#FFF', fontSize: 18, fontWeight: '700', marginHorizontal: 16, marginBottom: 2 },
  sectionSub: { color: '#888', fontSize: 12, marginHorizontal: 16, marginBottom: 12 },
  // Folder cards
  folderCard: { flex: 1, borderRadius: 14, overflow: 'hidden', borderWidth: 1, maxWidth: (SW - 42) / 2 },
  folderGrad: { padding: 16, minHeight: 110, justifyContent: 'space-between' },
  folderName: { color: '#FFF', fontSize: 14, fontWeight: '700', marginTop: 8 },
  folderCount: { color: '#aaa', fontSize: 11 },
  folderType: { color: '#555', fontSize: 9, textTransform: 'uppercase', letterSpacing: 1 },
  // Folder detail header
  folderHeader: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 16, paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: '#141424' },
  folderHeaderTitle: { color: '#FFF', fontSize: 18, fontWeight: '700', flex: 1 },
  folderHeaderCount: { color: '#888', fontSize: 13 },
  // Song rows
  songRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 10, paddingHorizontal: 16, gap: 10 },
  songIdx: { color: '#666', fontWeight: '600', width: 24, fontSize: 13, textAlign: 'center' },
  songImg: { width: 42, height: 42, borderRadius: 6, backgroundColor: '#141424' },
  songName: { color: '#FFF', fontWeight: '600', fontSize: 14 },
  songArtist: { color: '#888', fontSize: 12 },
  songDur: { color: '#666', fontSize: 11 },
  // Play all
  playAllBtn: { flexDirection: 'row', alignItems: 'center', gap: 6, backgroundColor: '#8B5CF6', paddingVertical: 8, paddingHorizontal: 16, borderRadius: 20, alignSelf: 'center', marginVertical: 8 },
  playAllText: { color: '#FFF', fontWeight: '600', fontSize: 12 },
  // Bulk bar
  bulkBar: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', backgroundColor: '#12121f', paddingVertical: 10, paddingHorizontal: 16, borderRadius: 12, marginHorizontal: 16, marginBottom: 8, borderWidth: 1, borderColor: '#1e1e38' },
  bulkCount: { color: '#FFF', fontSize: 13, fontWeight: '600' },
  bulkActions: { flexDirection: 'row', gap: 12 },
  bulkBtn: { width: 36, height: 36, borderRadius: 18, backgroundColor: '#141424', justifyContent: 'center', alignItems: 'center' },
  // Modal
  modalOverlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.7)', justifyContent: 'center', alignItems: 'center' },
  // Sort
  sortModal: { backgroundColor: '#12121f', borderRadius: 20, width: '82%', paddingVertical: 20, paddingHorizontal: 16 },
  sortTitle: { color: '#FFF', fontSize: 18, fontWeight: '700', textAlign: 'center', marginBottom: 12 },
  sortOpt: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 12, paddingHorizontal: 8, borderBottomWidth: 1, borderBottomColor: '#141424' },
  sortOptOn: { backgroundColor: 'rgba(29,185,84,0.08)' },
  sortOptText: { color: '#FFF', fontSize: 14, flex: 1 },
  orderRow: { flexDirection: 'row', gap: 10, marginTop: 12 },
  orderBtn: { flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, paddingVertical: 10, borderRadius: 10, backgroundColor: '#141424', borderWidth: 1, borderColor: '#1e1e38' },
  orderBtnOn: { borderColor: '#8B5CF6', backgroundColor: 'rgba(29,185,84,0.15)' },
  orderText: { color: '#888', fontSize: 12, fontWeight: '600' },
  // Import/Export
  ieModal: { backgroundColor: '#12121f', borderRadius: 20, width: '88%', paddingVertical: 20, paddingHorizontal: 20 },
  ieTitle: { color: '#FFF', fontSize: 20, fontWeight: '800', textAlign: 'center', marginBottom: 16 },
  ieBtn: { flexDirection: 'row', alignItems: 'center', backgroundColor: '#141424', padding: 16, borderRadius: 12, borderWidth: 1, borderColor: '#1e1e38' },
  ieBtnTitle: { color: '#FFF', fontSize: 14, fontWeight: '600' },
  ieBtnSub: { color: '#888', fontSize: 11 },
  ieDivider: { height: 1, backgroundColor: '#141424', marginVertical: 16 },
  ieLabel: { color: '#888', fontSize: 12, fontWeight: '600', marginBottom: 8 },
  ieInput: { backgroundColor: '#141424', borderRadius: 10, padding: 12, color: '#FFF', fontSize: 13, minHeight: 80, textAlignVertical: 'top', borderWidth: 1, borderColor: '#1e1e38', marginBottom: 12 },
  ieImportBtn: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, backgroundColor: '#8B5CF6', paddingVertical: 12, borderRadius: 10 },
  ieImportText: { color: '#FFF', fontWeight: '700' },
  // Close
  closeBtn: { backgroundColor: '#1e1e38', borderRadius: 10, marginTop: 12, paddingVertical: 12, alignItems: 'center' },
  closeBtnText: { color: '#FFF', fontWeight: '600', fontSize: 14 },
  // Duplicate
  dupeModal: { backgroundColor: '#12121f', borderRadius: 20, width: '88%', maxHeight: '70%', paddingVertical: 20, paddingHorizontal: 16 },
  dupeHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 },
  dupeTitle: { color: '#FFF', fontSize: 18, fontWeight: '700' },
  dupeRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: '#141424' },
  dupeName: { color: '#FFF', fontSize: 14, fontWeight: '600' },
  dupeArtist: { color: '#888', fontSize: 12 },
  dupeBadge: { backgroundColor: '#FF6B35', borderRadius: 10, paddingHorizontal: 8, paddingVertical: 3 },
  dupeBadgeText: { color: '#FFF', fontSize: 11, fontWeight: '700' },
});
