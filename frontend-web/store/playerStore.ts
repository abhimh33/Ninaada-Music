import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import { Song } from '../services/api';

export type PlaybackMode = 'sequential' | 'loop' | 'loop-one' | 'shuffle';

interface PlayerState {
  // Current playback state
  currentSong: Song | null;
  isPlaying: boolean;
  currentTime: number;
  duration: number;
  volume: number;
  playbackMode: PlaybackMode;
  
  // Queue management
  queue: Song[];
  queueIndex: number;
  history: Song[];
  
  // Playlists
  playlists: { id: string; name: string; songs: Song[] }[];
  
  // Liked songs
  likedSongs: Song[];
  
  // Autoplay settings
  autoplayEnabled: boolean;
  upNextSongs: Song[]; // Preview of upcoming similar songs
  
  // Actions
  setCurrentSong: (song: Song | null) => void;
  play: () => void;
  pause: () => void;
  togglePlay: () => void;
  setCurrentTime: (time: number) => void;
  setDuration: (duration: number) => void;
  setVolume: (volume: number) => void;
  setPlaybackMode: (mode: PlaybackMode) => void;
  
  // Queue actions
  addToQueue: (song: Song) => void;
  addMultipleToQueue: (songs: Song[]) => void;
  playNext: (song: Song) => void;
  removeFromQueue: (index: number) => void;
  clearQueue: () => void;
  setQueue: (songs: Song[]) => void;
  nextSong: () => void;
  previousSong: () => void;
  playSongFromQueue: (index: number) => void;
  
  // Playlist actions
  createPlaylist: (name: string) => string;
  deletePlaylist: (id: string) => void;
  editPlaylistName: (id: string, newName: string) => void;
  addSongToPlaylist: (playlistId: string, song: Song) => void;
  removeSongFromPlaylist: (playlistId: string, songId: string) => void;
  playPlaylist: (playlistId: string) => void;
  
  // Liked songs actions
  toggleLikeSong: (song: Song) => void;
  isSongLiked: (songId: string) => boolean;
  
  // Autoplay actions
  setAutoplayEnabled: (enabled: boolean) => void;
  setUpNextSongs: (songs: Song[]) => void;
}

export const usePlayerStore = create<PlayerState>()(
  persist(
    (set, get) => ({
      // Initial state
      currentSong: null,
      isPlaying: false,
      currentTime: 0,
      duration: 0,
      volume: 1,
      playbackMode: 'sequential',
      queue: [],
      queueIndex: -1,
      history: [],
      playlists: [],
      likedSongs: [],
      autoplayEnabled: false,
      upNextSongs: [],

      // Basic playback actions
      setCurrentSong: (song) => {
        if (song && song !== get().currentSong) {
          set({ currentSong: song, isPlaying: true });
        }
      },
      play: () => set({ isPlaying: true }),
      pause: () => set({ isPlaying: false }),
      togglePlay: () => set((state) => ({ isPlaying: !state.isPlaying })),
      setCurrentTime: (time) => set({ currentTime: time }),
      setDuration: (duration) => set({ duration }),
      setVolume: (volume) => set({ volume }),
      setPlaybackMode: (mode) => set({ playbackMode: mode }),

      // Queue actions
      addToQueue: (song) => {
        const queue = [...get().queue];
        if (!queue.find((s) => s.id === song.id)) {
          queue.push(song);
          set({ queue });
        }
      },
      addMultipleToQueue: (songs) => {
        const queue = [...get().queue];
        songs.forEach((song) => {
          if (!queue.find((s) => s.id === song.id)) {
            queue.push(song);
          }
        });
        set({ queue });
      },
      playNext: (song) => {
        const { queue, queueIndex } = get();
        const newQueue = [...queue];
        const existingIndex = newQueue.findIndex((s) => s.id === song.id);
        if (existingIndex !== -1) {
          newQueue.splice(existingIndex, 1);
        }
        const insertIndex = queueIndex + 1;
        newQueue.splice(insertIndex, 0, song);
        let newQueueIndex = queueIndex;
        if (insertIndex <= queueIndex) {
          newQueueIndex = queueIndex + 1;
        }
        set({ queue: newQueue, queueIndex: newQueueIndex });
      },
      removeFromQueue: (index) => {
        const queue = [...get().queue];
        queue.splice(index, 1);
        const queueIndex = get().queueIndex;
        let newIndex = queueIndex;
        if (index < queueIndex) {
          newIndex = queueIndex - 1;
        } else if (index === queueIndex && queue.length > 0) {
          newIndex = Math.min(queueIndex, queue.length - 1);
        } else if (queue.length === 0) {
          newIndex = -1;
        }
        set({ queue, queueIndex: newIndex });
      },
      clearQueue: () => set({ queue: [], queueIndex: -1 }),
      setQueue: (songs) => set({ queue: songs, queueIndex: 0 }),
      nextSong: () => {
        const { queue, queueIndex, playbackMode, currentSong, autoplayEnabled } = get();
        if (queue.length === 0) {
          if (currentSong && autoplayEnabled) {
            set({ isPlaying: false });
          }
          return;
        }

        let nextIndex = queueIndex;
        if (playbackMode === 'shuffle') {
          nextIndex = Math.floor(Math.random() * queue.length);
        } else if (playbackMode === 'loop' || playbackMode === 'loop-one') {
          if (playbackMode === 'loop-one') {
            nextIndex = queueIndex;
          } else {
            nextIndex = (queueIndex + 1) % queue.length;
          }
        } else {
          nextIndex = queueIndex + 1;
          if (nextIndex >= queue.length && autoplayEnabled) {
            set({ isPlaying: false });
            return;
          }
        }

        const nextSong = queue[nextIndex];
        set({ queueIndex: nextIndex, currentSong: nextSong, isPlaying: true });
      },
      previousSong: () => {
        const { queue, queueIndex, playbackMode, history } = get();
        if (queue.length === 0) return;

        let prevIndex = queueIndex;
        if (playbackMode === 'shuffle') {
          prevIndex = Math.floor(Math.random() * queue.length);
        } else {
          prevIndex = queueIndex - 1;
          if (prevIndex < 0) {
            if (history.length > 0) {
              const prevSong = history[history.length - 1];
              set({ currentSong: prevSong, isPlaying: true });
              return;
            }
            prevIndex = 0;
          }
        }

        const prevSong = queue[prevIndex];
        set({ queueIndex: prevIndex, currentSong: prevSong, isPlaying: true });
      },
      playSongFromQueue: (index) => {
        const queue = get().queue;
        if (index >= 0 && index < queue.length) {
          set({ queueIndex: index, currentSong: queue[index], isPlaying: true });
        }
      },

      // Playlist actions
      createPlaylist: (name) => {
        const id = Date.now().toString();
        const playlists = [...get().playlists, { id, name, songs: [] }];
        set({ playlists });
        return id;
      },
      deletePlaylist: (id) => {
        const playlists = get().playlists.filter((p) => p.id !== id);
        set({ playlists });
      },
      editPlaylistName: (id, newName) => {
        const playlists = get().playlists.map((p) => {
          if (p.id === id) {
            return { ...p, name: newName };
          }
          return p;
        });
        set({ playlists });
      },
      addSongToPlaylist: (playlistId, song) => {
        const playlists = get().playlists.map((p) => {
          if (p.id === playlistId) {
            if (!p.songs.find((s) => s.id === song.id)) {
              return { ...p, songs: [...p.songs, song] };
            }
            return p;
          }
          return p;
        });
        set({ playlists });
      },
      removeSongFromPlaylist: (playlistId, songId) => {
        const playlists = get().playlists.map((p) => {
          if (p.id === playlistId) {
            return { ...p, songs: p.songs.filter((s) => s.id !== songId) };
          }
          return p;
        });
        set({ playlists });
      },
      playPlaylist: (playlistId) => {
        const playlist = get().playlists.find((p) => p.id === playlistId);
        if (playlist && playlist.songs.length > 0) {
          set({
            queue: playlist.songs,
            queueIndex: 0,
            currentSong: playlist.songs[0],
            isPlaying: true,
          });
        }
      },

      // Liked songs actions
      toggleLikeSong: (song) => {
        const likedSongs = [...get().likedSongs];
        const index = likedSongs.findIndex((s) => s.id === song.id);
        if (index >= 0) {
          likedSongs.splice(index, 1);
        } else {
          likedSongs.push(song);
        }
        set({ likedSongs });
      },
      isSongLiked: (songId) => {
        return get().likedSongs.some((s) => s.id === songId);
      },

      // Autoplay actions
      setAutoplayEnabled: (enabled) => set({ autoplayEnabled: enabled }),
      setUpNextSongs: (songs) => set({ upNextSongs: songs }),
    }),
    {
      name: 'music-player-storage',
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({
        volume: state.volume,
        playbackMode: state.playbackMode,
        playlists: state.playlists,
        queue: state.queue,
        likedSongs: state.likedSongs,
        autoplayEnabled: state.autoplayEnabled,
      }),
    }
  )
);

