'use client';

import { useState, useEffect } from 'react';
import { FaToggleOn, FaToggleOff, FaChevronDown, FaChevronUp } from 'react-icons/fa';
import { usePlayerStore } from '../store/playerStore';
import { searchSongs, Song } from '../services/api';
import SongCard from './SongCard';

export default function AutoplaySettings() {
  const { autoplayEnabled, setAutoplayEnabled, upNextSongs, setUpNextSongs, currentSong } = usePlayerStore();
  const [showUpNext, setShowUpNext] = useState(false);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (autoplayEnabled && currentSong) {
      loadSimilarSongs();
    }
  }, [autoplayEnabled, currentSong?.id]);

  const loadSimilarSongs = async () => {
    if (!currentSong) return;
    
    setLoading(true);
    try {
      // Search by language, album, or artists
      const queries = [
        currentSong.language || '',
        currentSong.album || '',
        currentSong.artists || currentSong.singers || '',
      ].filter(q => q);

      const allSongs: Song[] = [];
      for (const query of queries.slice(0, 2)) {
        if (query) {
          const songs = await searchSongs(query, false, true);
          const filtered = songs
            .filter(s => s.id !== currentSong.id && !allSongs.find(existing => existing.id === s.id))
            .slice(0, 10);
          allSongs.push(...filtered);
        }
      }

      setUpNextSongs(allSongs.slice(0, 10));
    } catch (error) {
      console.error('Error loading similar songs:', error);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="bg-[#181818] rounded-lg p-3 sm:p-4 mb-3 sm:mb-4">
      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center gap-2 sm:gap-3 flex-1 min-w-0">
          <button
            onClick={() => setAutoplayEnabled(!autoplayEnabled)}
            className="text-xl sm:text-2xl text-red-500 hover:text-red-600 transition-colors flex-shrink-0"
          >
            {autoplayEnabled ? <FaToggleOn /> : <FaToggleOff />}
          </button>
          <div className="min-w-0 flex-1">
            <h3 className="text-white font-semibold text-sm sm:text-base">Autoplay Similar Songs</h3>
            <p className="text-xs sm:text-sm text-gray-400 hidden sm:block">
              Automatically play songs from the same language, album, or artist
            </p>
          </div>
        </div>
        {autoplayEnabled && upNextSongs.length > 0 && (
          <button
            onClick={() => setShowUpNext(!showUpNext)}
            className="text-gray-400 hover:text-white transition-colors flex-shrink-0 ml-2"
          >
            {showUpNext ? <FaChevronUp /> : <FaChevronDown />}
          </button>
        )}
      </div>

      {autoplayEnabled && showUpNext && (
        <div className="mt-4 pt-4 border-t border-gray-700">
          <h4 className="text-white font-medium mb-3 text-sm sm:text-base">Up Next ({upNextSongs.length})</h4>
          {loading ? (
            <div className="text-gray-400 text-center py-4 text-sm">Loading similar songs...</div>
          ) : upNextSongs.length > 0 ? (
            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-2">
              {upNextSongs.map((song) => (
                <SongCard key={song.id} song={song} />
              ))}
            </div>
          ) : (
            <div className="text-gray-400 text-center py-4 text-sm">No similar songs found</div>
          )}
        </div>
      )}
    </div>
  );
}
