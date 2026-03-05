'use client';

import { useState, useEffect, useCallback } from 'react';
import { FaSearch, FaSpinner } from 'react-icons/fa';
import { searchSongs, Song } from '../services/api';
import SongCard from './SongCard';
import { usePlayerStore } from '../store/playerStore';
import PlaylistSelector from './PlaylistSelector';

export default function Search() {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Song[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selectedSongForPlaylist, setSelectedSongForPlaylist] = useState<Song | null>(null);
  const { addToQueue, setCurrentSong, addSongToPlaylist, playNext } = usePlayerStore();
  
  // Persist search results in sessionStorage
  useEffect(() => {
    const savedResults = sessionStorage.getItem('searchResults');
    const savedQuery = sessionStorage.getItem('searchQuery');
    if (savedResults && savedQuery) {
      try {
        setResults(JSON.parse(savedResults));
        setQuery(savedQuery);
      } catch (e) {
        console.error('Error loading saved results:', e);
      }
    }
  }, []);

  // Expose setSelectedSong to parent
  const handleCardClick = (song: Song) => {
    // This will be passed from parent
    if ((window as any).openSongDetail) {
      (window as any).openSongDetail(song);
    }
  };

  const performSearch = useCallback(async (searchQuery: string) => {
    if (!searchQuery.trim()) {
      setResults([]);
      sessionStorage.removeItem('searchResults');
      sessionStorage.removeItem('searchQuery');
      return;
    }

    setLoading(true);
    setError(null);

    try {
      // Request lyrics for all search results
      const songs = await searchSongs(searchQuery, true, true);
      setResults(songs);
      // Save to sessionStorage
      sessionStorage.setItem('searchResults', JSON.stringify(songs));
      sessionStorage.setItem('searchQuery', searchQuery);
    } catch (err) {
      setError('Failed to search songs. Please try again.');
      console.error('Search error:', err);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    const timeoutId = setTimeout(() => {
      performSearch(query);
    }, 500); // Debounce search

    return () => clearTimeout(timeoutId);
  }, [query, performSearch]);

  const handlePlaySong = (song: Song) => {
    setCurrentSong(song);
    addToQueue(song);
  };

  const handlePlayNext = (song: Song) => {
    playNext(song);
  };

  return (
    <div className="w-full max-w-4xl mx-auto px-2 sm:px-4 py-4 sm:py-8">
      {/* Search bar */}
      <div className="relative mb-4 sm:mb-8">
        <FaSearch className="absolute left-3 sm:left-4 top-1/2 transform -translate-y-1/2 text-gray-400 text-sm sm:text-base" />
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search for songs, artists, albums..."
          className="w-full pl-10 sm:pl-12 pr-4 py-2 sm:py-3 bg-[#181818] text-white rounded-full focus:outline-none focus:ring-2 focus:ring-[#ff0000] border border-transparent focus:border-[#ff0000]/50 transition-colors text-sm sm:text-base"
        />
        {loading && (
          <FaSpinner className="absolute right-4 top-1/2 transform -translate-y-1/2 animate-spin text-gray-400" />
        )}
      </div>

      {/* Error message */}
      {error && (
        <div className="mb-4 p-4 bg-red-900/50 text-red-200 rounded-lg">
          {error}
        </div>
      )}

      {/* Results */}
      {results.length > 0 && (
        <div>
          <h2 className="text-xl sm:text-2xl font-bold mb-4 sm:mb-6 text-white">
            Search Results ({results.length})
          </h2>
          <div className="grid grid-cols-2 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-2 sm:gap-4">
            {results.map((song) => (
              <SongCard
                key={song.id}
                song={song}
                onPlay={() => handlePlaySong(song)}
                onAddToQueue={() => addToQueue(song)}
                onPlayNext={() => handlePlayNext(song)}
                onAddToPlaylist={(song) => setSelectedSongForPlaylist(song)}
                showPlaylistButton={true}
                onCardClick={handleCardClick}
              />
            ))}
          </div>
        </div>
      )}

      {/* Playlist selector modal */}
      {selectedSongForPlaylist && (
        <PlaylistSelector
          song={selectedSongForPlaylist}
          onSelect={(playlistId) => {
            addSongToPlaylist(playlistId, selectedSongForPlaylist);
            setSelectedSongForPlaylist(null);
          }}
          onClose={() => setSelectedSongForPlaylist(null)}
        />
      )}

      {/* Empty state */}
      {!loading && query && results.length === 0 && !error && (
        <div className="text-center py-12 text-gray-400">
          No results found for &quot;{query}&quot;
        </div>
      )}

      {/* Initial state */}
      {!query && !loading && results.length === 0 && (
        <div className="text-center py-12 text-gray-400">
          Start typing to search for music
        </div>
      )}
    </div>
  );
}

