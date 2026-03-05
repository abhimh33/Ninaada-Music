'use client';

import { useState, useEffect } from 'react';
import { FaSearch, FaList, FaMusic, FaHeart } from 'react-icons/fa';
import Search from '../components/Search';
import Queue from '../components/Queue';
import PlaylistManager from '../components/PlaylistManager';
import Player from '../components/Player';
import SongDetail from '../components/SongDetail';
import ToastContainer from '../components/ToastContainer';
import { usePlayerStore } from '../store/playerStore';
import { Song } from '../services/api';
import AutoplaySettings from '../components/AutoplaySettings';

type Page = 'search' | 'queue' | 'playlists';

export default function Home() {
  const [currentPage, setCurrentPage] = useState<Page>('search');
  const [selectedSong, setSelectedSong] = useState<Song | null>(null);
  const { currentSong } = usePlayerStore();

  // Expose function to open song detail globally
  useEffect(() => {
    (window as any).openSongDetail = (song: Song) => {
      setSelectedSong(song);
    };
    return () => {
      delete (window as any).openSongDetail;
    };
  }, []);

  // Auto-navigate to next song's detail page when song changes
  useEffect(() => {
    if (currentSong && selectedSong && currentSong.id !== selectedSong.id) {
      setSelectedSong(currentSong);
    }
  }, [currentSong?.id]);

  const { likedSongs, setQueue, setCurrentSong, playPlaylist } = usePlayerStore();
  const [showLikedSongs, setShowLikedSongs] = useState(false);

  const handleLikedSongsClick = () => {
    if (likedSongs.length > 0) {
      setQueue(likedSongs);
      setCurrentSong(likedSongs[0]);
      setShowLikedSongs(true);
      setCurrentPage('playlists');
    }
  };

  return (
    <div className="flex flex-col sm:flex-row h-screen overflow-hidden">
      {/* Sidebar */}
      <aside className="w-full sm:w-64 bg-[#0f0f0f] border-b sm:border-b-0 sm:border-r border-gray-800/50 flex flex-row sm:flex-col">
        <div className="p-4 sm:p-6 border-b sm:border-b border-r sm:border-r-0 border-gray-800/50 flex items-center justify-between sm:block">
          <h1 className="text-xl sm:text-2xl font-bold text-[#ff0000] flex items-center gap-2">
            <FaMusic /> <span className="hidden sm:inline">Music Player</span>
          </h1>
        </div>

        <nav className="flex-1 flex sm:flex-col p-2 sm:p-4 space-x-2 sm:space-x-0 sm:space-y-2 overflow-x-auto">
          <button
            onClick={() => setCurrentPage('search')}
            className={`flex-shrink-0 flex items-center gap-2 sm:gap-3 px-3 sm:px-4 py-2 sm:py-3 rounded-lg transition-colors whitespace-nowrap ${
              currentPage === 'search'
                ? 'bg-white/10 text-white font-semibold'
                : 'text-gray-400 hover:bg-white/5 hover:text-white'
            }`}
          >
            <FaSearch /> <span className="text-sm sm:text-base">Search</span>
          </button>
          <button
            onClick={() => setCurrentPage('queue')}
            className={`flex-shrink-0 flex items-center gap-2 sm:gap-3 px-3 sm:px-4 py-2 sm:py-3 rounded-lg transition-colors whitespace-nowrap ${
              currentPage === 'queue'
                ? 'bg-white/10 text-white font-semibold'
                : 'text-gray-400 hover:bg-white/5 hover:text-white'
            }`}
          >
            <FaList /> <span className="text-sm sm:text-base">Queue</span>
          </button>
          <button
            onClick={() => setCurrentPage('playlists')}
            className={`flex-shrink-0 flex items-center gap-2 sm:gap-3 px-3 sm:px-4 py-2 sm:py-3 rounded-lg transition-colors whitespace-nowrap ${
              currentPage === 'playlists'
                ? 'bg-white/10 text-white font-semibold'
                : 'text-gray-400 hover:bg-white/5 hover:text-white'
            }`}
          >
            <FaMusic /> <span className="text-sm sm:text-base">Playlists</span>
          </button>
          {likedSongs.length > 0 && (
            <button
              onClick={handleLikedSongsClick}
              className={`flex-shrink-0 flex items-center gap-2 sm:gap-3 px-3 sm:px-4 py-2 sm:py-3 rounded-lg transition-colors whitespace-nowrap ${
                showLikedSongs
                  ? 'bg-white/10 text-white font-semibold'
                  : 'text-gray-400 hover:bg-white/5 hover:text-white'
              }`}
            >
              <FaHeart /> <span className="text-sm sm:text-base">Liked Songs ({likedSongs.length})</span>
            </button>
          )}
        </nav>
      </aside>

      {/* Main content */}
      <main className="flex-1 overflow-y-auto pb-20 sm:pb-24 bg-[#0f0f0f]">
        {currentPage === 'search' && (
          <>
            <div className="container mx-auto px-2 sm:px-4 pt-2 sm:pt-4">
              <AutoplaySettings />
            </div>
            <Search />
          </>
        )}
        {currentPage === 'queue' && <Queue onSongClick={(song) => setSelectedSong(song)} />}
        {currentPage === 'playlists' && <PlaylistManager />}
      </main>

      {/* Song Detail Modal */}
      {selectedSong && (
        <SongDetail
          song={selectedSong}
          onClose={() => setSelectedSong(null)}
        />
      )}

      {/* Player */}
      <Player onSongClick={() => currentSong && setSelectedSong(currentSong)} />
      
      {/* Toast Notifications */}
      <ToastContainer />
    </div>
  );
}
