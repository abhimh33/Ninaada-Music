'use client';

import { useState } from 'react';
import { FaPlus, FaTrash, FaPlay, FaEdit, FaTimes, FaCheck, FaHeart } from 'react-icons/fa';
import { usePlayerStore } from '../store/playerStore';
import SongCard from './SongCard';
import { Song } from '../services/api';
import { toast } from '../utils/toast';

export default function PlaylistManager() {
  const {
    playlists,
    createPlaylist,
    deletePlaylist,
    editPlaylistName,
    addSongToPlaylist,
    removeSongFromPlaylist,
    playPlaylist,
    likedSongs,
    playSongFromQueue,
    setQueue,
    setCurrentSong,
  } = usePlayerStore();

  const [showCreateForm, setShowCreateForm] = useState(false);
  const [newPlaylistName, setNewPlaylistName] = useState('');
  const [selectedPlaylist, setSelectedPlaylist] = useState<string | null>(null);
  const [editingPlaylistId, setEditingPlaylistId] = useState<string | null>(null);
  const [editName, setEditName] = useState('');

  const handleCreatePlaylist = () => {
    if (newPlaylistName.trim()) {
      createPlaylist(newPlaylistName.trim());
      toast.show(`Playlist "${newPlaylistName.trim()}" created`, 'success');
      setNewPlaylistName('');
      setShowCreateForm(false);
    }
  };

  const handleEditPlaylist = (playlistId: string, currentName: string) => {
    setEditingPlaylistId(playlistId);
    setEditName(currentName);
  };

  const handleSaveEdit = () => {
    if (editingPlaylistId && editName.trim()) {
      editPlaylistName(editingPlaylistId, editName.trim());
      toast.show('Playlist name updated', 'success');
      setEditingPlaylistId(null);
      setEditName('');
    }
  };

  const handlePlayLikedSongs = () => {
    if (likedSongs.length > 0) {
      setQueue(likedSongs);
      setCurrentSong(likedSongs[0]);
      usePlayerStore.getState().play();
      toast.show('Playing liked songs', 'success');
    }
  };

  const selectedPlaylistData = selectedPlaylist
    ? playlists.find((p) => p.id === selectedPlaylist)
    : null;

  return (
    <div className="w-full max-w-6xl mx-auto px-2 sm:px-4 py-4 sm:py-8">
      <div className="flex items-center justify-between mb-4 sm:mb-6">
        <h2 className="text-xl sm:text-2xl font-semibold text-white">My Playlists</h2>
        <button
          onClick={() => setShowCreateForm(true)}
          className="flex items-center gap-1 sm:gap-2 px-2 sm:px-4 py-1.5 sm:py-2 bg-red-600 hover:bg-red-700 rounded-lg transition-colors text-white text-xs sm:text-sm"
        >
          <FaPlus className="text-xs sm:text-sm" /> <span className="hidden sm:inline">Create Playlist</span>
        </button>
      </div>

      {/* Liked Songs - Show when viewing playlists */}
      {likedSongs.length > 0 && !selectedPlaylist && (
        <div className="mb-6 bg-[#181818] rounded-lg p-4 sm:p-6 hover:bg-[#282828] transition-colors cursor-pointer"
          onClick={handlePlayLikedSongs}
        >
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <FaHeart className="text-red-500 text-2xl" />
              <div>
                <h3 className="text-lg font-semibold text-white">Liked Songs</h3>
                <p className="text-sm text-gray-400">
                  {likedSongs.length} song{likedSongs.length !== 1 ? 's' : ''}
                </p>
              </div>
            </div>
            <button
              onClick={(e) => {
                e.stopPropagation();
                handlePlayLikedSongs();
              }}
              className="flex items-center gap-2 px-4 py-2 bg-red-600 hover:bg-red-700 rounded-lg transition-colors text-white"
            >
              <FaPlay /> Play
            </button>
          </div>
        </div>
      )}

      {/* Create playlist form */}
      {showCreateForm && (
        <div className="mb-6 p-4 bg-gray-800 rounded-lg">
          <div className="flex items-center gap-2">
            <input
              type="text"
              value={newPlaylistName}
              onChange={(e) => setNewPlaylistName(e.target.value)}
              placeholder="Playlist name"
              className="flex-1 px-4 py-2 bg-gray-700 text-white rounded-lg focus:outline-none focus:ring-2 focus:ring-red-500"
              onKeyPress={(e) => {
                if (e.key === 'Enter') {
                  handleCreatePlaylist();
                }
              }}
            />
            <button
              onClick={handleCreatePlaylist}
              className="px-4 py-2 bg-red-600 hover:bg-red-700 rounded-lg transition-colors text-white"
            >
              Create
            </button>
            <button
              onClick={() => {
                setShowCreateForm(false);
                setNewPlaylistName('');
              }}
              className="p-2 hover:bg-gray-700 rounded-lg transition-colors text-white"
            >
              <FaTimes />
            </button>
          </div>
        </div>
      )}

      {selectedPlaylistData ? (
        /* Playlist detail view */
        <div>
          <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between mb-4 sm:mb-6 gap-3">
            <div className="flex-1 min-w-0">
              <button
                onClick={() => setSelectedPlaylist(null)}
                className="text-gray-400 hover:text-white mb-2 text-sm sm:text-base"
              >
                ← Back to playlists
              </button>
              {editingPlaylistId === selectedPlaylistData.id ? (
                <div className="flex items-center gap-2">
                  <input
                    type="text"
                    value={editName}
                    onChange={(e) => setEditName(e.target.value)}
                    className="text-xl sm:text-2xl font-semibold bg-gray-700 text-white px-2 py-1 rounded"
                    onKeyPress={(e) => {
                      if (e.key === 'Enter') {
                        handleSaveEdit();
                      }
                    }}
                    autoFocus
                  />
                  <button
                    onClick={handleSaveEdit}
                    className="p-2 hover:bg-gray-700 rounded transition-colors text-green-400"
                  >
                    <FaCheck />
                  </button>
                  <button
                    onClick={() => {
                      setEditingPlaylistId(null);
                      setEditName('');
                    }}
                    className="p-2 hover:bg-gray-700 rounded transition-colors text-red-400"
                  >
                    <FaTimes />
                  </button>
                </div>
              ) : (
                <h3 className="text-xl sm:text-2xl font-semibold text-white">{selectedPlaylistData.name}</h3>
              )}
              <p className="text-gray-400 text-sm sm:text-base">
                {selectedPlaylistData.songs.length} songs
              </p>
            </div>
            <div className="flex gap-2 flex-shrink-0">
              <button
                onClick={() => playPlaylist(selectedPlaylistData.id)}
                className="flex items-center gap-1 sm:gap-2 px-3 sm:px-4 py-1.5 sm:py-2 bg-red-600 hover:bg-red-700 rounded-lg transition-colors text-white text-xs sm:text-sm"
              >
                <FaPlay className="text-xs sm:text-sm" /> <span className="hidden sm:inline">Play All</span>
              </button>
              <button
                onClick={() => handleEditPlaylist(selectedPlaylistData.id, selectedPlaylistData.name)}
                className="p-1.5 sm:p-2 bg-gray-700 hover:bg-gray-600 rounded-lg transition-colors text-white"
                title="Edit playlist name"
              >
                <FaEdit className="text-xs sm:text-sm" />
              </button>
              <button
                onClick={() => handleDeletePlaylist(selectedPlaylistData.id)}
                className="p-1.5 sm:p-2 bg-gray-700 hover:bg-gray-600 rounded-lg transition-colors text-red-400"
                title="Delete playlist"
              >
                <FaTrash className="text-xs sm:text-sm" />
              </button>
            </div>
          </div>

          {selectedPlaylistData.songs.length > 0 ? (
            <div className="grid grid-cols-2 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-2 sm:gap-4">
              {selectedPlaylistData.songs.map((song) => (
                <div key={song.id} className="relative group">
                  <SongCard 
                    song={song}
                    onCardClick={(song) => {
                      if ((window as any).openSongDetail) {
                        (window as any).openSongDetail(song);
                      }
                    }}
                  />
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      removeSongFromPlaylist(selectedPlaylistData.id, song.id);
                    }}
                    className="absolute top-2 right-2 p-2 bg-black/70 hover:bg-black/90 rounded-full opacity-0 group-hover:opacity-100 transition-opacity z-10"
                    title="Remove from playlist"
                  >
                    <FaTimes className="text-white text-xs" />
                  </button>
                </div>
              ))}
            </div>
          ) : (
            <div className="text-center py-12 text-gray-400">
              <p>This playlist is empty</p>
            </div>
          )}
        </div>
      ) : (
        /* Playlist list view */
        <div>
          {playlists.length > 0 ? (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 sm:gap-4">
              {playlists.map((playlist) => (
                <div
                  key={playlist.id}
                  className="bg-gray-800 rounded-lg p-6 hover:bg-gray-700 transition-colors cursor-pointer"
                  onClick={() => setSelectedPlaylist(playlist.id)}
                >
                  <div className="flex items-start justify-between mb-3 sm:mb-4">
                    <div className="flex-1 min-w-0">
                      {editingPlaylistId === playlist.id ? (
                        <div className="flex items-center gap-2">
                          <input
                            type="text"
                            value={editName}
                            onChange={(e) => setEditName(e.target.value)}
                            className="text-base sm:text-lg font-semibold bg-gray-700 text-white px-2 py-1 rounded flex-1 text-sm sm:text-base"
                            onKeyPress={(e) => {
                              if (e.key === 'Enter') {
                                handleSaveEdit();
                              }
                            }}
                            autoFocus
                            onClick={(e) => e.stopPropagation()}
                          />
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              handleSaveEdit();
                            }}
                            className="p-1 hover:bg-gray-600 rounded text-green-400"
                          >
                            <FaCheck />
                          </button>
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              setEditingPlaylistId(null);
                              setEditName('');
                            }}
                            className="p-1 hover:bg-gray-600 rounded text-red-400"
                          >
                            <FaTimes />
                          </button>
                        </div>
                      ) : (
                        <h3 className="text-base sm:text-lg font-semibold mb-1 text-white truncate">
                          {playlist.name}
                        </h3>
                      )}
                      <p className="text-xs sm:text-sm text-gray-400">
                        {playlist.songs.length} song{playlist.songs.length !== 1 ? 's' : ''}
                      </p>
                    </div>
                    <div className="flex gap-1 flex-shrink-0">
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          handleEditPlaylist(playlist.id, playlist.name);
                        }}
                        className="p-1.5 sm:p-2 hover:bg-gray-600 rounded transition-colors text-white"
                        title="Edit playlist name"
                      >
                        <FaEdit className="text-xs sm:text-sm" />
                      </button>
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          if (confirm('Are you sure you want to delete this playlist?')) {
                            handleDeletePlaylist(playlist.id);
                          }
                        }}
                        className="p-1.5 sm:p-2 hover:bg-gray-600 rounded transition-colors text-red-400"
                        title="Delete playlist"
                      >
                        <FaTrash className="text-xs sm:text-sm" />
                      </button>
                    </div>
                  </div>
                  <div className="flex gap-2">
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        playPlaylist(playlist.id);
                      }}
                      className="flex-1 flex items-center justify-center gap-2 px-3 sm:px-4 py-1.5 sm:py-2 bg-red-600 hover:bg-red-700 rounded-lg transition-colors text-white text-xs sm:text-sm"
                    >
                      <FaPlay className="text-xs sm:text-sm" /> <span>Play</span>
                    </button>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div className="text-center py-12 text-gray-400">
              <p>No playlists yet</p>
            </div>
          )}
        </div>
      )}
    </div>
  );
}


