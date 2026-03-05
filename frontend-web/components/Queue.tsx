'use client';

import { FaPlay, FaTrash, FaGripVertical } from 'react-icons/fa';
import { usePlayerStore } from '../store/playerStore';
import { formatTime } from '../utils/formatTime';
import { Song } from '../services/api';

interface QueueProps {
  onSongClick?: (song: Song) => void;
}

export default function Queue({ onSongClick }: QueueProps) {
  const {
    queue,
    queueIndex,
    currentSong,
    removeFromQueue,
    clearQueue,
    playSongFromQueue,
  } = usePlayerStore();

  const handleSongClick = (song: Song) => {
    if (onSongClick) {
      onSongClick(song);
    } else if ((window as any).openSongDetail) {
      (window as any).openSongDetail(song);
    }
  };

  if (queue.length === 0) {
    return (
      <div className="text-center py-12 text-gray-400">
        <p>Your queue is empty</p>
        <p className="text-sm mt-2">Add songs to start playing</p>
      </div>
    );
  }

  return (
    <div className="w-full max-w-4xl mx-auto px-2 sm:px-4 py-4 sm:py-8">
      <div className="flex items-center justify-between mb-4 sm:mb-6">
        <h2 className="text-xl sm:text-2xl font-semibold text-white">Queue ({queue.length})</h2>
        <button
          onClick={clearQueue}
          className="px-3 sm:px-4 py-1.5 sm:py-2 bg-red-600 hover:bg-red-700 rounded-lg transition-colors text-xs sm:text-sm text-white"
        >
          Clear Queue
        </button>
      </div>

      <div className="space-y-2">
        {queue.map((song, index) => {
          const isCurrent = song.id === currentSong?.id;
          return (
            <div
              key={`${song.id}-${index}`}
              className={`flex items-center gap-2 sm:gap-4 p-2 sm:p-4 rounded-lg transition-colors cursor-pointer ${
                isCurrent
                  ? 'bg-red-600/20 border border-red-600/50'
                  : 'bg-gray-800 hover:bg-gray-700'
              }`}
              onClick={(e) => {
                // Don't trigger if clicking on buttons
                if ((e.target as HTMLElement).closest('button')) {
                  return;
                }
                handleSongClick(song);
              }}
            >
              <div className="flex items-center gap-2 sm:gap-3 flex-1 min-w-0">
                <div className="text-gray-400 text-xs sm:text-sm w-4 sm:w-6 flex-shrink-0">
                  {isCurrent ? (
                    <FaPlay className="text-red-500 text-xs sm:text-sm" />
                  ) : (
                    <span>{index + 1}</span>
                  )}
                </div>

                {song.image && (
                  <img
                    src={song.image}
                    alt={song.song}
                    className="w-10 h-10 sm:w-12 sm:h-12 rounded object-cover flex-shrink-0"
                  />
                )}

                <div className="flex-1 min-w-0">
                  <p
                    className={`font-medium truncate text-xs sm:text-base ${
                      isCurrent ? 'text-red-400' : 'text-white'
                    }`}
                    title={song.song}
                  >
                    {song.song}
                  </p>
                  <p className="text-xs sm:text-sm text-gray-400 truncate" title={song.artists || song.singers}>
                    {song.artists || song.singers}
                  </p>
                </div>
              </div>

              <div className="flex items-center gap-1 sm:gap-2 flex-shrink-0">
                {song.duration && (
                  <span className="text-xs sm:text-sm text-gray-400 hidden sm:inline">
                    {song.duration}
                  </span>
                )}
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    playSongFromQueue(index);
                  }}
                  className="p-1.5 sm:p-2 hover:bg-gray-700 rounded transition-colors"
                  title="Play"
                >
                  <FaPlay className="w-3 h-3 sm:w-4 sm:h-4" />
                </button>
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    removeFromQueue(index);
                  }}
                  className="p-1.5 sm:p-2 hover:bg-gray-700 rounded transition-colors text-red-400"
                  title="Remove"
                >
                  <FaTrash className="w-3 h-3 sm:w-4 sm:h-4" />
                </button>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}


