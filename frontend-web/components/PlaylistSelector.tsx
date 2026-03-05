'use client';

import { useState } from 'react';
import { FaTimes } from 'react-icons/fa';
import { usePlayerStore } from '../store/playerStore';
import { Song } from '../services/api';
import { toast } from '../utils/toast';

interface PlaylistSelectorProps {
  song: Song;
  onSelect: (playlistId: string) => void;
  onClose: () => void;
}

export default function PlaylistSelector({
  song,
  onSelect,
  onClose,
}: PlaylistSelectorProps) {
  const { playlists, createPlaylist } = usePlayerStore();
  const [newPlaylistName, setNewPlaylistName] = useState('');
  const [showCreateForm, setShowCreateForm] = useState(false);

  const handleCreateAndAdd = () => {
    if (newPlaylistName.trim()) {
      const playlistId = createPlaylist(newPlaylistName.trim());
      onSelect(playlistId);
      setNewPlaylistName('');
      setShowCreateForm(false);
    }
  };

  const handleSelect = (playlistId: string) => {
    onSelect(playlistId);
    // Show feedback
    const playlist = playlists.find(p => p.id === playlistId);
    if (playlist) {
      toast.show(`Added to "${playlist.name}"`, 'success');
    }
  };

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div className="bg-gray-800 rounded-lg p-4 sm:p-6 max-w-md w-full mx-4">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg sm:text-xl font-semibold text-white">Add to Playlist</h3>
          <button
            onClick={onClose}
            className="p-2 hover:bg-gray-700 rounded transition-colors"
          >
            <FaTimes />
          </button>
        </div>

        <p className="text-gray-300 mb-4 truncate text-sm sm:text-base">
          {song.song} - {song.artists || song.singers}
        </p>

        {showCreateForm ? (
          <div className="space-y-4">
            <input
              type="text"
              value={newPlaylistName}
              onChange={(e) => setNewPlaylistName(e.target.value)}
              placeholder="Playlist name"
              className="w-full px-3 sm:px-4 py-2 bg-gray-700 text-white rounded-lg focus:outline-none focus:ring-2 focus:ring-red-500 text-sm sm:text-base"
              onKeyPress={(e) => {
                if (e.key === 'Enter') {
                  handleCreateAndAdd();
                }
              }}
              autoFocus
            />
            <div className="flex gap-2">
              <button
                onClick={handleCreateAndAdd}
                className="flex-1 px-3 sm:px-4 py-2 bg-red-600 hover:bg-red-700 rounded-lg transition-colors text-white text-sm sm:text-base"
              >
                Create & Add
              </button>
              <button
                onClick={() => {
                  setShowCreateForm(false);
                  setNewPlaylistName('');
                }}
                className="px-3 sm:px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg transition-colors text-white text-sm sm:text-base"
              >
                Cancel
              </button>
            </div>
          </div>
        ) : (
          <div className="space-y-4">
            {playlists.length > 0 ? (
              <div className="space-y-2 max-h-64 overflow-y-auto">
                {playlists.map((playlist) => (
                  <button
                    key={playlist.id}
                    onClick={() => handleSelect(playlist.id)}
                    className="w-full text-left px-4 py-3 bg-gray-700 hover:bg-gray-600 rounded-lg transition-colors"
                  >
                    <div className="font-medium">{playlist.name}</div>
                    <div className="text-sm text-gray-400">
                      {playlist.songs.length} songs
                    </div>
                  </button>
                ))}
              </div>
            ) : (
              <p className="text-gray-400 text-center py-4">
                No playlists yet
              </p>
            )}
            <button
              onClick={() => setShowCreateForm(true)}
              className="w-full px-4 py-2 bg-red-600 hover:bg-red-700 rounded-lg transition-colors"
            >
              Create New Playlist
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

