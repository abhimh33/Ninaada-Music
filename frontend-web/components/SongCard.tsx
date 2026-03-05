'use client';

import { useState, useRef, useEffect } from 'react';
import { FaPlay, FaPlus, FaDownload, FaShare, FaList, FaForward, FaEllipsisV, FaHeart } from 'react-icons/fa';
import { Song, downloadSong } from '../services/api';
import { usePlayerStore } from '../store/playerStore';
import PlaylistSelector from './PlaylistSelector';
import { toast } from '../utils/toast';

interface SongCardProps {
  song: Song;
  onPlay?: () => void;
  onAddToQueue?: () => void;
  onPlayNext?: () => void;
  onAddToPlaylist?: (song: Song) => void;
  showPlaylistButton?: boolean;
  onCardClick?: (song: Song) => void;
}

export default function SongCard({
  song,
  onPlay,
  onAddToQueue,
  onPlayNext,
  onAddToPlaylist,
  showPlaylistButton = false,
  onCardClick,
}: SongCardProps) {
  const { 
    setCurrentSong, 
    addToQueue, 
    playNext, 
    toggleLikeSong, 
    isSongLiked,
  } = usePlayerStore();
  
  const [showMenu, setShowMenu] = useState(false);
  const [showPlaylistSelector, setShowPlaylistSelector] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  const isLiked = isSongLiked(song.id);

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
        setShowMenu(false);
      }
    };

    if (showMenu) {
      document.addEventListener('mousedown', handleClickOutside);
    }

    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [showMenu]);

  const handlePlay = () => {
    if (onPlay) {
      onPlay();
    } else {
      setCurrentSong(song);
      addToQueue(song);
    }
  };

  const handleAddToQueue = () => {
    if (onAddToQueue) {
      onAddToQueue();
    } else {
      addToQueue(song);
    }
    toast.show('Added to queue', 'success');
    setShowMenu(false);
  };

  const handlePlayNext = () => {
    if (onPlayNext) {
      onPlayNext();
    } else {
      playNext(song);
    }
    toast.show('Will play next', 'success');
    setShowMenu(false);
  };

  const handleDownload = () => {
    const downloadUrl = downloadSong(song.id);
    window.open(downloadUrl, '_blank');
    setShowMenu(false);
  };

  const handleShare = async () => {
    const shareData = {
      title: song.song,
      text: `Listen to ${song.song} by ${song.artists || song.singers}`,
      url: window.location.href,
    };

    if (navigator.share) {
      try {
        await navigator.share(shareData);
      } catch (err) {
        console.error('Error sharing:', err);
      }
    } else {
      navigator.clipboard.writeText(`${shareData.title} - ${shareData.text}`);
      alert('Link copied to clipboard!');
    }
    setShowMenu(false);
  };

  const handleLike = () => {
    toggleLikeSong(song);
    setShowMenu(false);
  };

  const handleCardClick = (e: React.MouseEvent) => {
    if ((e.target as HTMLElement).closest('button') || (e.target as HTMLElement).closest('.menu-container')) {
      return;
    }
    if (onCardClick) {
      onCardClick(song);
    }
  };

  return (
    <>
      <div 
        className="bg-[#181818] rounded-lg p-3 sm:p-4 hover:bg-[#282828] transition-colors group cursor-pointer relative"
        onClick={handleCardClick}
      >
        {/* 3-dots menu button */}
        <button
          onClick={(e) => {
            e.stopPropagation();
            setShowMenu(!showMenu);
          }}
          className="absolute top-2 right-2 p-2 bg-black/70 hover:bg-black/90 rounded-full opacity-0 group-hover:opacity-100 transition-opacity z-20 menu-container"
          title="More options"
        >
          <FaEllipsisV className="text-white text-xs" />
        </button>

        {/* Dropdown menu */}
        {showMenu && (
          <div
            ref={menuRef}
            className="absolute top-10 right-2 bg-[#282828] rounded-lg shadow-xl z-30 min-w-[200px] py-2 menu-container"
            onClick={(e) => e.stopPropagation()}
          >
            <button
              onClick={handlePlayNext}
              className="w-full px-4 py-2 text-left text-white hover:bg-white/10 flex items-center gap-2"
            >
              <FaForward className="text-sm" /> Play Next
            </button>
            <button
              onClick={handleAddToQueue}
              className="w-full px-4 py-2 text-left text-white hover:bg-white/10 flex items-center gap-2"
            >
              <FaPlus className="text-sm" /> Add to Queue
            </button>
            <button
              onClick={() => {
                setShowPlaylistSelector(true);
                setShowMenu(false);
              }}
              className="w-full px-4 py-2 text-left text-white hover:bg-white/10 flex items-center gap-2"
            >
              <FaList className="text-sm" /> Save to Playlist
            </button>
            <button
              onClick={handleLike}
              className={`w-full px-4 py-2 text-left hover:bg-white/10 flex items-center gap-2 ${
                isLiked ? 'text-red-500' : 'text-white'
              }`}
            >
              <FaHeart className="text-sm" /> {isLiked ? 'Liked' : 'Like'}
            </button>
            <button
              onClick={handleDownload}
              className="w-full px-4 py-2 text-left text-white hover:bg-white/10 flex items-center gap-2"
            >
              <FaDownload className="text-sm" /> Download
            </button>
            <button
              onClick={handleShare}
              className="w-full px-4 py-2 text-left text-white hover:bg-white/10 flex items-center gap-2"
            >
              <FaShare className="text-sm" /> Share
            </button>
          </div>
        )}

        <div className="relative mb-3">
          {song.image ? (
            <img
              src={song.image}
              alt={song.song}
              className="w-full aspect-square object-cover rounded-lg"
            />
          ) : (
            <div className="w-full aspect-square bg-gray-700 rounded-lg flex items-center justify-center">
              <FaPlay className="text-gray-500 text-2xl" />
            </div>
          )}
          <div className="absolute inset-0 bg-black/60 opacity-0 group-hover:opacity-100 transition-opacity rounded-lg flex items-center justify-center gap-1 sm:gap-2">
            <button
              onClick={(e) => {
                e.stopPropagation();
                handlePlay();
              }}
              className="p-2 sm:p-3 bg-red-500 rounded-full hover:bg-red-600 transition-colors shadow-lg"
              title="Play"
            >
              <FaPlay className="text-white text-xs sm:text-sm" />
            </button>
            <button
              onClick={(e) => {
                e.stopPropagation();
                handlePlayNext();
              }}
              className="p-2 sm:p-3 bg-white/90 rounded-full hover:bg-white transition-colors shadow-lg"
              title="Play next"
            >
              <FaForward className="text-gray-900 text-xs" />
            </button>
            <button
              onClick={(e) => {
                e.stopPropagation();
                handleAddToQueue();
              }}
              className="p-2 sm:p-3 bg-gray-700/90 rounded-full hover:bg-gray-600 transition-colors shadow-lg"
              title="Add to queue"
            >
              <FaPlus className="text-white text-xs sm:text-sm" />
            </button>
          </div>
        </div>

        <div className="space-y-1">
          <h3 className="font-semibold text-white truncate" title={song.song}>
            {song.song}
          </h3>
          <p className="text-sm text-gray-400 truncate" title={song.artists || song.singers}>
            {song.artists || song.singers}
          </p>
          {song.album && (
            <p className="text-xs text-gray-500 truncate" title={song.album}>
              {song.album}
            </p>
          )}
        </div>

        <div className="mt-3 flex items-center justify-between text-gray-400">
          {song.duration && (
            <span className="text-xs">{song.duration}</span>
          )}
          {isLiked && (
            <FaHeart className="text-red-500 text-sm" title="Liked" />
          )}
        </div>
      </div>

      {/* Playlist Selector */}
      {showPlaylistSelector && (
        <PlaylistSelector
          song={song}
          onSelect={(playlistId) => {
            if (onAddToPlaylist) {
              onAddToPlaylist(song);
            }
            setShowPlaylistSelector(false);
          }}
          onClose={() => setShowPlaylistSelector(false)}
        />
      )}

    </>
  );
}

