import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
  View, Text, TouchableOpacity, Modal, StyleSheet, TextInput,
  ToastAndroid, ScrollView, Animated, Dimensions, Platform, Switch
} from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { MaterialIcons, Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';

const { width: SW } = Dimensions.get('window');
const fmt = (sec) => { const m = Math.floor(sec / 60), s = Math.floor(sec % 60); return `${m}:${s < 10 ? '0' : ''}${s}`; };

// ========== ENHANCED SLEEP TIMER & ALARM HOOK ==========
export function useSleepAlarm({ soundRef, isPlaying, setIsPlaying, currentSong, playlists, playSongRef }) {
  // Sleep Timer State
  const [sleepActive, setSleepActive] = useState(false);
  const [sleepRemaining, setSleepRemaining] = useState(0);
  const [sleepEndOfSong, setSleepEndOfSong] = useState(false);
  const [customSleepMin, setCustomSleepMin] = useState('');
  const [fadeOutEnabled, setFadeOutEnabled] = useState(true);
  const [fadeOutDuration, setFadeOutDuration] = useState(30); // seconds
  const [ambientDimEnabled, setAmbientDimEnabled] = useState(true);
  const [showSleepModal, setShowSleepModal] = useState(false);

  // Alarm State
  const [alarmEnabled, setAlarmEnabled] = useState(false);
  const [alarmHour, setAlarmHour] = useState(7);
  const [alarmMinute, setAlarmMinute] = useState(0);
  const [alarmPlaylistId, setAlarmPlaylistId] = useState(null);
  const [alarmVolume, setAlarmVolume] = useState(0.5);
  const [progressiveVolume, setProgressiveVolume] = useState(true);
  const [showAlarmModal, setShowAlarmModal] = useState(false);
  const [alarmTriggered, setAlarmTriggered] = useState(false);

  // Refs
  const sleepRef = useRef(null);
  const fadeRef = useRef(null);
  const alarmCheckRef = useRef(null);
  const sleepEndRef = useRef(false);
  const originalVolume = useRef(1);
  const ambientDimAnim = useRef(new Animated.Value(0)).current;

  // Sync ref
  useEffect(() => { sleepEndRef.current = sleepEndOfSong; }, [sleepEndOfSong]);

  // Load saved alarm settings
  useEffect(() => {
    (async () => {
      try {
        const [ae, ah, am, ap, av, fe, fd, ade] = await Promise.all([
          AsyncStorage.getItem('alarmEnabled'),
          AsyncStorage.getItem('alarmHour'),
          AsyncStorage.getItem('alarmMinute'),
          AsyncStorage.getItem('alarmPlaylistId'),
          AsyncStorage.getItem('alarmVolume'),
          AsyncStorage.getItem('fadeOutEnabled'),
          AsyncStorage.getItem('fadeOutDuration'),
          AsyncStorage.getItem('ambientDimEnabled'),
        ]);
        if (ae) setAlarmEnabled(JSON.parse(ae));
        if (ah) setAlarmHour(parseInt(ah));
        if (am) setAlarmMinute(parseInt(am));
        if (ap) setAlarmPlaylistId(ap);
        if (av) setAlarmVolume(parseFloat(av));
        if (fe !== null) setFadeOutEnabled(JSON.parse(fe));
        if (fd) setFadeOutDuration(parseInt(fd));
        if (ade !== null) setAmbientDimEnabled(JSON.parse(ade));
      } catch (e) {}
    })();
  }, []);

  // Alarm checker - runs every 30 seconds
  useEffect(() => {
    if (!alarmEnabled) {
      if (alarmCheckRef.current) clearInterval(alarmCheckRef.current);
      return;
    }
    alarmCheckRef.current = setInterval(() => {
      const now = new Date();
      if (now.getHours() === alarmHour && now.getMinutes() === alarmMinute && !alarmTriggered) {
        triggerAlarm();
      }
      // Reset triggered flag after 2 minutes
      if (alarmTriggered && (now.getMinutes() !== alarmMinute)) {
        setAlarmTriggered(false);
      }
    }, 30000);
    return () => { if (alarmCheckRef.current) clearInterval(alarmCheckRef.current); };
  }, [alarmEnabled, alarmHour, alarmMinute, alarmTriggered]);

  // Start sleep timer with fade-out
  const startSleep = useCallback((mins) => {
    if (sleepRef.current) clearInterval(sleepRef.current);
    if (fadeRef.current) clearInterval(fadeRef.current);

    if (mins === 0) {
      setSleepActive(false); setSleepRemaining(0); setSleepEndOfSong(false);
      // Reset volume
      if (soundRef?.current) soundRef.current.setVolumeAsync(1).catch(() => {});
      Animated.timing(ambientDimAnim, { toValue: 0, duration: 500, useNativeDriver: true }).start();
      ToastAndroid.show('Timer cancelled', ToastAndroid.SHORT);
      return;
    }

    if (mins === -1) {
      setSleepEndOfSong(true); setSleepActive(true); setSleepRemaining(0);
      setShowSleepModal(false);
      ToastAndroid.show('Stopping after this song', ToastAndroid.SHORT);
      return;
    }

    setSleepActive(true);
    setSleepRemaining(mins * 60);
    setSleepEndOfSong(false);
    setShowSleepModal(false);

    // Start ambient dim if enabled
    if (ambientDimEnabled) {
      Animated.timing(ambientDimAnim, { toValue: 0.3, duration: 2000, useNativeDriver: true }).start();
    }

    // Store original volume
    originalVolume.current = 1;

    sleepRef.current = setInterval(() => {
      setSleepRemaining(prev => {
        if (prev <= 1) {
          clearInterval(sleepRef.current);
          if (fadeOutEnabled) {
            startFadeOut();
          } else {
            // Just stop
            if (soundRef?.current) soundRef.current.pauseAsync().catch(() => {});
            setIsPlaying(false);
            setSleepActive(false);
            Animated.timing(ambientDimAnim, { toValue: 0, duration: 1000, useNativeDriver: true }).start();
            ToastAndroid.show('Sleep timer: stopped', ToastAndroid.LONG);
          }
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
  }, [fadeOutEnabled, ambientDimEnabled, soundRef]);

  // Fade out volume gradually
  const startFadeOut = useCallback(() => {
    let vol = originalVolume.current;
    const steps = fadeOutDuration; // 1 step per second
    const decrement = vol / steps;
    let count = 0;

    fadeRef.current = setInterval(() => {
      count++;
      vol = Math.max(0, vol - decrement);
      if (soundRef?.current) {
        soundRef.current.setVolumeAsync(vol).catch(() => {});
      }

      // Increase ambient dim
      if (ambientDimEnabled) {
        const dimVal = 0.3 + (count / steps) * 0.5;
        ambientDimAnim.setValue(Math.min(dimVal, 0.8));
      }

      if (count >= steps) {
        clearInterval(fadeRef.current);
        if (soundRef?.current) soundRef.current.pauseAsync().catch(() => {});
        setIsPlaying(false);
        setSleepActive(false);
        // Reset volume for next play
        if (soundRef?.current) soundRef.current.setVolumeAsync(1).catch(() => {});
        Animated.timing(ambientDimAnim, { toValue: 0, duration: 1000, useNativeDriver: true }).start();
        ToastAndroid.show('Good night! 🌙', ToastAndroid.LONG);
      }
    }, 1000);
  }, [fadeOutDuration, ambientDimEnabled, soundRef]);

  // Trigger alarm
  const triggerAlarm = useCallback(async () => {
    setAlarmTriggered(true);
    ToastAndroid.show('⏰ Wake up! Starting your alarm playlist', ToastAndroid.LONG);

    let songToPlay = null;
    if (alarmPlaylistId && playlists) {
      const pl = playlists.find(p => p.id === alarmPlaylistId);
      if (pl?.songs?.length > 0) {
        songToPlay = pl.songs[Math.floor(Math.random() * pl.songs.length)];
      }
    }

    if (!songToPlay) {
      // If no playlist selected, try to get a trending song
      try {
        const res = await fetch('http://10.20.3.243:8000/browse/top-songs?language=hindi&limit=5');
        const data = await res.json();
        if (data.data?.length) {
          songToPlay = {
            id: data.data[0].id,
            name: data.data[0].song || data.data[0].name,
            artist: data.data[0].primary_artists || data.data[0].artist || '',
            image: data.data[0].image || '',
            media_url: data.data[0].media_url || '',
            duration: data.data[0].duration || 240,
          };
        }
      } catch (e) {}
    }

    if (songToPlay && playSongRef?.current) {
      // Progressive volume ramp-up
      if (progressiveVolume && soundRef?.current) {
        // Start at very low volume
        if (soundRef.current) soundRef.current.setVolumeAsync(0.05).catch(() => {});
      }
      playSongRef.current(songToPlay);

      // Progressive volume increase over 60 seconds
      if (progressiveVolume) {
        let vol = 0.05;
        const targetVol = alarmVolume;
        const steps = 60;
        const increment = (targetVol - 0.05) / steps;

        const rampInterval = setInterval(() => {
          vol = Math.min(targetVol, vol + increment);
          if (soundRef?.current) soundRef.current.setVolumeAsync(vol).catch(() => {});
          if (vol >= targetVol) clearInterval(rampInterval);
        }, 1000);
      }
    }
  }, [alarmPlaylistId, playlists, alarmVolume, progressiveVolume, soundRef]);

  // Save alarm settings
  const saveAlarm = useCallback(async (enabled, hour, minute, playlistId, volume) => {
    setAlarmEnabled(enabled);
    setAlarmHour(hour);
    setAlarmMinute(minute);
    if (playlistId !== undefined) setAlarmPlaylistId(playlistId);
    setAlarmVolume(volume);

    await Promise.all([
      AsyncStorage.setItem('alarmEnabled', JSON.stringify(enabled)),
      AsyncStorage.setItem('alarmHour', hour.toString()),
      AsyncStorage.setItem('alarmMinute', minute.toString()),
      playlistId !== undefined && AsyncStorage.setItem('alarmPlaylistId', playlistId || ''),
      AsyncStorage.setItem('alarmVolume', volume.toString()),
    ]);

    if (enabled) {
      ToastAndroid.show(`Alarm set for ${hour}:${minute < 10 ? '0' : ''}${minute}`, ToastAndroid.SHORT);
    } else {
      ToastAndroid.show('Alarm cancelled', ToastAndroid.SHORT);
    }
    setShowAlarmModal(false);
  }, []);

  // Cleanup
  useEffect(() => {
    return () => {
      if (sleepRef.current) clearInterval(sleepRef.current);
      if (fadeRef.current) clearInterval(fadeRef.current);
      if (alarmCheckRef.current) clearInterval(alarmCheckRef.current);
    };
  }, []);

  return {
    // Sleep
    sleepActive, sleepRemaining, sleepEndOfSong, sleepEndRef,
    showSleepModal, setShowSleepModal,
    customSleepMin, setCustomSleepMin,
    fadeOutEnabled, setFadeOutEnabled,
    fadeOutDuration, setFadeOutDuration,
    ambientDimEnabled, setAmbientDimEnabled,
    ambientDimAnim,
    startSleep,
    // Alarm
    alarmEnabled, alarmHour, alarmMinute, alarmPlaylistId, alarmVolume,
    progressiveVolume, setProgressiveVolume,
    showAlarmModal, setShowAlarmModal,
    saveAlarm,
  };
}

// ========== ENHANCED SLEEP TIMER MODAL ==========
export function EnhancedSleepTimerModal({
  visible, onClose, startSleep, sleepActive, sleepRemaining, sleepEndOfSong,
  customSleepMin, setCustomSleepMin,
  fadeOutEnabled, setFadeOutEnabled,
  fadeOutDuration, setFadeOutDuration,
  ambientDimEnabled, setAmbientDimEnabled,
}) {
  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <View style={SS.overlay}>
        <View style={SS.modal}>
          <Text style={SS.title}>🌙 Sleep Timer</Text>

          {/* Timer Status */}
          {sleepActive && (
            <View style={SS.statusBanner}>
              <Ionicons name="moon" size={16} color="#7B2FBE" />
              <Text style={SS.statusText}>
                {sleepEndOfSong ? 'Stopping after current song' : `Time remaining: ${fmt(sleepRemaining)}`}
              </Text>
            </View>
          )}

          {/* Preset Times */}
          <View style={SS.presetGrid}>
            {[5, 10, 15, 20, 30, 45, 60, 90].map(m => (
              <TouchableOpacity key={m} style={SS.presetBtn} onPress={() => startSleep(m)}>
                <Text style={SS.presetTime}>{m}</Text>
                <Text style={SS.presetLabel}>min</Text>
              </TouchableOpacity>
            ))}
          </View>

          {/* Custom Time */}
          <View style={SS.customRow}>
            <TextInput style={SS.customInput} placeholder="Custom" placeholderTextColor="#666"
              keyboardType="numeric" value={customSleepMin} onChangeText={setCustomSleepMin}
              maxLength={3} />
            <TouchableOpacity style={SS.customBtn}
              onPress={() => { const m = parseInt(customSleepMin); if (m > 0) { startSleep(m); setCustomSleepMin(''); } }}>
              <Text style={SS.customBtnText}>Set</Text>
            </TouchableOpacity>
          </View>

          {/* End of Song */}
          <TouchableOpacity style={SS.endSongBtn} onPress={() => startSleep(-1)}>
            <Ionicons name="musical-note" size={18} color="#7B2FBE" />
            <Text style={SS.endSongText}>Stop after current song</Text>
          </TouchableOpacity>

          {/* Fade Out Toggle */}
          <View style={SS.settingRow}>
            <View style={{ flex: 1 }}>
              <Text style={SS.settingTitle}>Fade Out</Text>
              <Text style={SS.settingSub}>Gradually lower volume before stopping</Text>
            </View>
            <Switch value={fadeOutEnabled} onValueChange={async (v) => {
              setFadeOutEnabled(v);
              await AsyncStorage.setItem('fadeOutEnabled', JSON.stringify(v));
            }} trackColor={{ false: '#333', true: '#7B2FBE66' }} thumbColor={fadeOutEnabled ? '#7B2FBE' : '#888'} />
          </View>

          {/* Fade Duration */}
          {fadeOutEnabled && (
            <View style={SS.fadeDurRow}>
              <Text style={SS.fadeDurLabel}>Fade duration:</Text>
              {[15, 30, 60].map(d => (
                <TouchableOpacity key={d}
                  style={[SS.fadeDurBtn, fadeOutDuration === d && SS.fadeDurBtnOn]}
                  onPress={async () => { setFadeOutDuration(d); await AsyncStorage.setItem('fadeOutDuration', d.toString()); }}>
                  <Text style={[SS.fadeDurText, fadeOutDuration === d && { color: '#7B2FBE' }]}>{d}s</Text>
                </TouchableOpacity>
              ))}
            </View>
          )}

          {/* Ambient Dim Toggle */}
          <View style={SS.settingRow}>
            <View style={{ flex: 1 }}>
              <Text style={SS.settingTitle}>Ambient Dim</Text>
              <Text style={SS.settingSub}>Gradually darken screen during timer</Text>
            </View>
            <Switch value={ambientDimEnabled} onValueChange={async (v) => {
              setAmbientDimEnabled(v);
              await AsyncStorage.setItem('ambientDimEnabled', JSON.stringify(v));
            }} trackColor={{ false: '#333', true: '#7B2FBE66' }} thumbColor={ambientDimEnabled ? '#7B2FBE' : '#888'} />
          </View>

          {/* Cancel / Close */}
          {sleepActive && (
            <TouchableOpacity style={SS.cancelBtn} onPress={() => startSleep(0)}>
              <Ionicons name="close-circle" size={18} color="#FF5252" />
              <Text style={SS.cancelText}>Cancel Timer</Text>
            </TouchableOpacity>
          )}
          <TouchableOpacity style={SS.closeBtn} onPress={onClose}>
            <Text style={SS.closeBtnText}>Close</Text>
          </TouchableOpacity>
        </View>
      </View>
    </Modal>
  );
}

// ========== ALARM SETUP MODAL ==========
export function AlarmSetupModal({
  visible, onClose, saveAlarm,
  alarmEnabled, alarmHour, alarmMinute, alarmPlaylistId, alarmVolume,
  progressiveVolume, setProgressiveVolume,
  playlists,
}) {
  const [hour, setHour] = useState(alarmHour);
  const [minute, setMinute] = useState(alarmMinute);
  const [enabled, setEnabled] = useState(alarmEnabled);
  const [selPlaylist, setSelPlaylist] = useState(alarmPlaylistId);
  const [volume, setVolume] = useState(alarmVolume);

  useEffect(() => {
    setHour(alarmHour);
    setMinute(alarmMinute);
    setEnabled(alarmEnabled);
    setSelPlaylist(alarmPlaylistId);
    setVolume(alarmVolume);
  }, [visible]);

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <View style={SS.overlay}>
        <View style={SS.modal}>
          <Text style={SS.title}>⏰ Wake-Up Alarm</Text>

          {/* Enable/Disable */}
          <View style={SS.settingRow}>
            <Text style={SS.settingTitle}>Alarm Enabled</Text>
            <Switch value={enabled} onValueChange={setEnabled}
              trackColor={{ false: '#333', true: '#FF6B3566' }} thumbColor={enabled ? '#FF6B35' : '#888'} />
          </View>

          {/* Time Picker */}
          {enabled && (
            <>
              <Text style={[SS.settingTitle, { marginVertical: 12 }]}>Wake-Up Time</Text>
              <View style={SS.timePickerRow}>
                {/* Hour */}
                <View style={SS.timePicker}>
                  <TouchableOpacity style={SS.timeArrow} onPress={() => setHour((hour + 1) % 24)}>
                    <MaterialIcons name="keyboard-arrow-up" size={28} color="#FFF" />
                  </TouchableOpacity>
                  <Text style={SS.timeValue}>{hour < 10 ? '0' : ''}{hour}</Text>
                  <TouchableOpacity style={SS.timeArrow} onPress={() => setHour((hour - 1 + 24) % 24)}>
                    <MaterialIcons name="keyboard-arrow-down" size={28} color="#FFF" />
                  </TouchableOpacity>
                </View>
                <Text style={SS.timeColon}>:</Text>
                {/* Minute */}
                <View style={SS.timePicker}>
                  <TouchableOpacity style={SS.timeArrow} onPress={() => setMinute((minute + 5) % 60)}>
                    <MaterialIcons name="keyboard-arrow-up" size={28} color="#FFF" />
                  </TouchableOpacity>
                  <Text style={SS.timeValue}>{minute < 10 ? '0' : ''}{minute}</Text>
                  <TouchableOpacity style={SS.timeArrow} onPress={() => setMinute((minute - 5 + 60) % 60)}>
                    <MaterialIcons name="keyboard-arrow-down" size={28} color="#FFF" />
                  </TouchableOpacity>
                </View>
              </View>

              {/* Playlist Selection */}
              <Text style={[SS.settingTitle, { marginTop: 16, marginBottom: 8 }]}>Wake-Up Playlist</Text>
              <ScrollView horizontal showsHorizontalScrollIndicator={false}>
                <TouchableOpacity style={[SS.plChip, !selPlaylist && SS.plChipOn]} onPress={() => setSelPlaylist(null)}>
                  <Text style={[SS.plChipText, !selPlaylist && { color: '#FF6B35' }]}>Random</Text>
                </TouchableOpacity>
                {(playlists || []).map(pl => (
                  <TouchableOpacity key={pl.id} style={[SS.plChip, selPlaylist === pl.id && SS.plChipOn]}
                    onPress={() => setSelPlaylist(pl.id)}>
                    <Text style={[SS.plChipText, selPlaylist === pl.id && { color: '#FF6B35' }]}>{pl.name}</Text>
                  </TouchableOpacity>
                ))}
              </ScrollView>

              {/* Volume */}
              <View style={[SS.settingRow, { marginTop: 16 }]}>
                <Text style={SS.settingTitle}>Volume: {Math.round(volume * 100)}%</Text>
              </View>
              <View style={SS.volumeRow}>
                {[0.2, 0.4, 0.6, 0.8, 1.0].map(v => (
                  <TouchableOpacity key={v} style={[SS.volBtn, volume === v && SS.volBtnOn]}
                    onPress={() => setVolume(v)}>
                    <Text style={[SS.volBtnText, volume === v && { color: '#FF6B35' }]}>{Math.round(v * 100)}%</Text>
                  </TouchableOpacity>
                ))}
              </View>

              {/* Progressive Volume */}
              <View style={SS.settingRow}>
                <View style={{ flex: 1 }}>
                  <Text style={SS.settingTitle}>Progressive Volume</Text>
                  <Text style={SS.settingSub}>Start soft and gradually increase</Text>
                </View>
                <Switch value={progressiveVolume} onValueChange={setProgressiveVolume}
                  trackColor={{ false: '#333', true: '#FF6B3566' }} thumbColor={progressiveVolume ? '#FF6B35' : '#888'} />
              </View>
            </>
          )}

          {/* Save / Close */}
          <TouchableOpacity style={SS.saveBtn}
            onPress={() => saveAlarm(enabled, hour, minute, selPlaylist, volume)}>
            <Text style={SS.saveBtnText}>{enabled ? 'Save Alarm' : 'Turn Off Alarm'}</Text>
          </TouchableOpacity>
          <TouchableOpacity style={SS.closeBtn} onPress={onClose}>
            <Text style={SS.closeBtnText}>Cancel</Text>
          </TouchableOpacity>
        </View>
      </View>
    </Modal>
  );
}

// ========== AMBIENT DIM OVERLAY ==========
export function AmbientDimOverlay({ animValue }) {
  return (
    <Animated.View
      pointerEvents="none"
      style={{
        position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
        backgroundColor: '#000', opacity: animValue, zIndex: 9999, elevation: 9999,
      }}
    />
  );
}

// ========== STYLES ==========
const SS = StyleSheet.create({
  overlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.7)', justifyContent: 'center', alignItems: 'center' },
  modal: { backgroundColor: '#12121f', borderRadius: 20, width: '88%', maxHeight: '85%', paddingVertical: 20, paddingHorizontal: 20 },
  title: { color: '#FFF', fontSize: 20, fontWeight: '800', textAlign: 'center', marginBottom: 16 },
  // Status
  statusBanner: { flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: 'rgba(123,47,190,0.15)', padding: 12, borderRadius: 10, marginBottom: 16, borderWidth: 1, borderColor: 'rgba(123,47,190,0.3)' },
  statusText: { color: '#7B2FBE', fontSize: 13, fontWeight: '600' },
  // Presets
  presetGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, justifyContent: 'center', marginBottom: 16 },
  presetBtn: { width: 60, height: 50, borderRadius: 12, backgroundColor: '#141424', justifyContent: 'center', alignItems: 'center', borderWidth: 1, borderColor: '#1e1e38' },
  presetTime: { color: '#FFF', fontSize: 16, fontWeight: '700' },
  presetLabel: { color: '#666', fontSize: 9 },
  // Custom
  customRow: { flexDirection: 'row', gap: 8, marginBottom: 12 },
  customInput: { flex: 1, height: 42, backgroundColor: '#141424', borderRadius: 10, paddingHorizontal: 14, color: '#FFF', fontSize: 14, borderWidth: 1, borderColor: '#1e1e38' },
  customBtn: { backgroundColor: '#7B2FBE', paddingHorizontal: 20, borderRadius: 10, justifyContent: 'center' },
  customBtnText: { color: '#FFF', fontWeight: '700' },
  // End of song
  endSongBtn: { flexDirection: 'row', alignItems: 'center', gap: 10, backgroundColor: '#141424', padding: 12, borderRadius: 10, marginBottom: 16, borderWidth: 1, borderColor: '#1e1e38' },
  endSongText: { color: '#FFF', fontSize: 14 },
  // Settings
  settingRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: '#141424' },
  settingTitle: { color: '#FFF', fontSize: 14, fontWeight: '600' },
  settingSub: { color: '#888', fontSize: 11, marginTop: 2 },
  // Fade duration
  fadeDurRow: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingVertical: 8 },
  fadeDurLabel: { color: '#888', fontSize: 12, marginRight: 4 },
  fadeDurBtn: { paddingHorizontal: 14, paddingVertical: 6, borderRadius: 8, backgroundColor: '#141424', borderWidth: 1, borderColor: '#1e1e38' },
  fadeDurBtnOn: { borderColor: '#7B2FBE', backgroundColor: 'rgba(123,47,190,0.15)' },
  fadeDurText: { color: '#888', fontSize: 12, fontWeight: '600' },
  // Cancel
  cancelBtn: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, marginTop: 12, paddingVertical: 10 },
  cancelText: { color: '#FF5252', fontWeight: '600' },
  // Close
  closeBtn: { backgroundColor: '#1e1e38', borderRadius: 10, marginTop: 8, paddingVertical: 12, alignItems: 'center' },
  closeBtnText: { color: '#FFF', fontWeight: '600', fontSize: 14 },
  // Time picker
  timePickerRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 4 },
  timePicker: { alignItems: 'center' },
  timeArrow: { padding: 4 },
  timeValue: { color: '#FFF', fontSize: 36, fontWeight: '800', width: 60, textAlign: 'center' },
  timeColon: { color: '#FFF', fontSize: 36, fontWeight: '800' },
  // Playlist chips
  plChip: { paddingHorizontal: 16, paddingVertical: 8, borderRadius: 16, backgroundColor: '#141424', marginRight: 8, borderWidth: 1, borderColor: '#1e1e38' },
  plChipOn: { borderColor: '#FF6B35', backgroundColor: 'rgba(255,107,53,0.15)' },
  plChipText: { color: '#888', fontSize: 12, fontWeight: '600' },
  // Volume
  volumeRow: { flexDirection: 'row', gap: 8, marginBottom: 8 },
  volBtn: { flex: 1, paddingVertical: 8, borderRadius: 8, backgroundColor: '#141424', alignItems: 'center', borderWidth: 1, borderColor: '#1e1e38' },
  volBtnOn: { borderColor: '#FF6B35', backgroundColor: 'rgba(255,107,53,0.15)' },
  volBtnText: { color: '#888', fontSize: 11, fontWeight: '600' },
  // Save
  saveBtn: { backgroundColor: '#FF6B35', borderRadius: 12, paddingVertical: 14, alignItems: 'center', marginTop: 16 },
  saveBtnText: { color: '#FFF', fontWeight: '700', fontSize: 15 },
});
