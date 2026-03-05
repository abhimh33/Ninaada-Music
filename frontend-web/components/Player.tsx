'use client';

import { useEffect, useRef, useState } from 'react';
import {
  FaPlay,
  FaPause,
  FaStepForward,
  FaStepBackward,
  FaVolumeUp,
  FaVolumeMute,
  FaRandom,
  FaRedo,
  FaRedoAlt,
} from 'react-icons/fa';
import { usePlayerStore } from '../store/playerStore';
import { formatTime } from '../utils/formatTime';
import { searchSongs } from '../services/api';

interface PlayerProps {
  onSongClick?: () => void;
}

export default function Player({ onSongClick }: PlayerProps) {
  const audioRef = useRef<HTMLAudioElement>(null);
  const {
    currentSong,
    isPlaying,
    currentTime,
    duration,
    volume,
    playbackMode,
    queue,
    queueIndex,
    setCurrentTime,
    setDuration,
    togglePlay,
    pause,
    setVolume,
    nextSong,
    previousSong,
    setPlaybackMode,
  } = usePlayerStore();

  const [showVolumeSlider, setShowVolumeSlider] = useState(false);
  const progressRef = useRef<HTMLDivElement>(null);
  const [isDragging, setIsDragging] = useState(false);
  const [dragTime, setDragTime] = useState(0);
  const [isLoading, setIsLoading] = useState(false);

  // Handle audio element events
  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;

    const updateTime = () => {
      // Update time continuously as song plays
      if (!isDragging && audio && !isLoading) {
        const time = audio.currentTime;
        if (isFinite(time) && time >= 0) {
          setCurrentTime(time);
        }
      }
    };
    
    const updateDuration = () => {
      if (audio.duration && isFinite(audio.duration) && audio.duration > 0) {
        setDuration(audio.duration);
      }
    };
    
    const handleEnded = async () => {
      const { queue, queueIndex } = usePlayerStore.getState();
      // If queue has more songs, play next
      if (queueIndex < queue.length - 1) {
        nextSong();
      } else {
        // Auto-play similar songs
        const currentSong = usePlayerStore.getState().currentSong;
        if (currentSong) {
          try {
            // Search for similar songs from same album/movie
            const searchQuery = currentSong.album || currentSong.artists || currentSong.song;
            const similarSongs = await searchSongs(searchQuery, false, true);
            
            // Filter out current song and add similar songs to queue
            const filteredSongs = similarSongs
              .filter((s) => s && s.id && s.id !== currentSong.id)
              .slice(0, 5); // Add up to 5 similar songs
            
            if (filteredSongs.length > 0) {
              usePlayerStore.getState().addMultipleToQueue(filteredSongs);
              usePlayerStore.getState().nextSong();
            } else {
              nextSong();
            }
          } catch (error) {
            console.error('Error fetching similar songs:', error);
            nextSong();
          }
        } else {
          nextSong();
        }
      }
    };

    // Add event listeners
    audio.addEventListener('timeupdate', updateTime);
    audio.addEventListener('loadedmetadata', updateDuration);
    audio.addEventListener('durationchange', updateDuration);
    audio.addEventListener('ended', handleEnded);
    audio.addEventListener('canplay', () => setIsLoading(false));
    audio.addEventListener('loadstart', () => setIsLoading(true));

    return () => {
      audio.removeEventListener('timeupdate', updateTime);
      audio.removeEventListener('loadedmetadata', updateDuration);
      audio.removeEventListener('durationchange', updateDuration);
      audio.removeEventListener('ended', handleEnded);
      audio.removeEventListener('canplay', () => setIsLoading(false));
      audio.removeEventListener('loadstart', () => setIsLoading(true));
    };
  }, [setCurrentTime, setDuration, nextSong, isDragging, isLoading]);

  // Sync audio playback state
  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;

    if (isPlaying && !isLoading) {
      const playPromise = audio.play();
      if (playPromise !== undefined) {
        playPromise.catch((error) => {
          // Ignore interruption errors
          if (error.name !== 'AbortError' && error.name !== 'NotAllowedError') {
            console.error('Play error:', error);
          }
        });
      }
    } else {
      audio.pause();
    }
  }, [isPlaying, isLoading]);

  // Update audio source when song changes
  useEffect(() => {
    const audio = audioRef.current;
    if (!audio || !currentSong?.media_url) return;

    setIsLoading(true);
    // Pause first to avoid interruption
    audio.pause();
    audio.src = currentSong.media_url;
    setCurrentTime(0);
    
    // Load the new source
    audio.load();
    
    // Wait for canplay before playing
    const handleCanPlay = () => {
      setIsLoading(false);
      if (isPlaying) {
        const playPromise = audio.play();
        if (playPromise !== undefined) {
          playPromise.catch((error) => {
            if (error.name !== 'AbortError' && error.name !== 'NotAllowedError') {
              console.error('Play error:', error);
            }
          });
        }
      }
      audio.removeEventListener('canplay', handleCanPlay);
    };
    
    audio.addEventListener('canplay', handleCanPlay);
    
    return () => {
      audio.removeEventListener('canplay', handleCanPlay);
    };
  }, [currentSong?.id, currentSong?.media_url, isPlaying, setCurrentTime]);

  // Set volume
  useEffect(() => {
    const audio = audioRef.current;
    if (audio) {
      audio.volume = volume;
    }
  }, [volume]);

  // Media Session API for background playback
  useEffect(() => {
    if ('mediaSession' in navigator && currentSong) {
      navigator.mediaSession.metadata = new MediaMetadata({
        title: currentSong.song,
        artist: currentSong.artists || currentSong.singers || '',
        album: currentSong.album || '',
        artwork: currentSong.image ? [{ src: currentSong.image, sizes: '512x512', type: 'image/jpeg' }] : [],
      });

      navigator.mediaSession.setActionHandler('play', () => {
        togglePlay();
      });
      navigator.mediaSession.setActionHandler('pause', () => {
        pause();
      });
      navigator.mediaSession.setActionHandler('previoustrack', () => {
        previousSong();
      });
      navigator.mediaSession.setActionHandler('nexttrack', () => {
        nextSong();
      });
    }
  }, [currentSong, isPlaying, togglePlay, pause, nextSong, previousSong]);

  // Keyboard volume control
  useEffect(() => {
    const handleKeyPress = (e: KeyboardEvent) => {
      // Only handle if not typing in an input
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) {
        return;
      }

      if (e.key === 'ArrowUp') {
        e.preventDefault();
        const newVolume = Math.min(1, volume + 0.05);
        setVolume(newVolume);
      } else if (e.key === 'ArrowDown') {
        e.preventDefault();
        const newVolume = Math.max(0, volume - 0.05);
        setVolume(newVolume);
      }
    };

    window.addEventListener('keydown', handleKeyPress);
    return () => {
      window.removeEventListener('keydown', handleKeyPress);
    };
  }, [volume, setVolume]);

  // Calculate progress position
  const getProgressPosition = (clientX: number): number => {
    if (!progressRef.current || !duration || duration <= 0) return 0;
    const rect = progressRef.current.getBoundingClientRect();
    const percent = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
    return percent * duration;
  };

  // Handle progress bar click
  const handleProgressClick = (e: React.MouseEvent<HTMLDivElement>) => {
    if (isDragging) return; // Don't handle click if we're dragging
    
    const audio = audioRef.current;
    if (!audio || !duration || duration <= 0) return;

    const newTime = getProgressPosition(e.clientX);
    audio.currentTime = newTime;
    setCurrentTime(newTime);
  };

  // Handle progress bar drag
  const handleProgressMouseDown = (e: React.MouseEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    if (!duration || duration <= 0) return;
    
    setIsDragging(true);
    const initialTime = getProgressPosition(e.clientX);
    setDragTime(initialTime);
    
    // Update audio immediately on mouse down
    const audio = audioRef.current;
    if (audio) {
      audio.currentTime = initialTime;
      setCurrentTime(initialTime);
    }
    
    const handleMouseMove = (moveEvent: MouseEvent) => {
      moveEvent.preventDefault();
      if (!duration || duration <= 0) return;
      const newTime = getProgressPosition(moveEvent.clientX);
      setDragTime(newTime);
      
      // Update audio position while dragging
      const audio = audioRef.current;
      if (audio) {
        audio.currentTime = newTime;
        setCurrentTime(newTime);
      }
    };

    const handleMouseUp = (upEvent: MouseEvent) => {
      upEvent.preventDefault();
      if (!duration || duration <= 0) return;
      const finalTime = getProgressPosition(upEvent.clientX);
      
      const audio = audioRef.current;
      if (audio) {
        audio.currentTime = finalTime;
        setCurrentTime(finalTime);
      }
      
      setIsDragging(false);
      setDragTime(0);
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
  };

  // Handle volume change
  const handleVolumeChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newVolume = parseFloat(e.target.value);
    setVolume(newVolume);
  };

  // Toggle playback mode
  const cyclePlaybackMode = () => {
    const modes: Array<'sequential' | 'loop' | 'loop-one' | 'shuffle'> = [
      'sequential',
      'loop',
      'loop-one',
      'shuffle',
    ];
    const currentIndex = modes.indexOf(playbackMode);
    const nextIndex = (currentIndex + 1) % modes.length;
    setPlaybackMode(modes[nextIndex]);
  };

  if (!currentSong) {
    return null;
  }

  // Use dragTime when dragging, otherwise use currentTime
  const displayTime = isDragging ? dragTime : (currentTime || 0);
  const progressPercent = duration > 0 && isFinite(duration) ? Math.min(100, Math.max(0, (displayTime / duration) * 100)) : 0;

  return (
    <div className="fixed bottom-0 left-0 right-0 bg-[#0f0f0f] text-white border-t border-gray-800/50 z-50 shadow-2xl">
      <audio ref={audioRef} preload="metadata" />
      
      {/* Progress bar */}
      <div
        ref={progressRef}
        className="h-1 bg-gray-800/50 cursor-pointer hover:h-1.5 transition-all relative group touch-none"
        onMouseDown={handleProgressMouseDown}
        onClick={handleProgressClick}
        onTouchStart={(e) => {
          e.preventDefault();
          if (!progressRef.current || !duration || duration <= 0) return;
          const touch = e.touches[0];
          const rect = progressRef.current.getBoundingClientRect();
          const percent = Math.max(0, Math.min(1, (touch.clientX - rect.left) / rect.width));
          const newTime = percent * duration;
          setIsDragging(true);
          setDragTime(newTime);
          const audio = audioRef.current;
          if (audio) {
            audio.currentTime = newTime;
            setCurrentTime(newTime);
          }
          
          const handleTouchMove = (moveEvent: TouchEvent) => {
            moveEvent.preventDefault();
            if (!progressRef.current || !duration || duration <= 0) return;
            const moveTouch = moveEvent.touches[0];
            const moveRect = progressRef.current.getBoundingClientRect();
            const movePercent = Math.max(0, Math.min(1, (moveTouch.clientX - moveRect.left) / moveRect.width));
            const moveTime = movePercent * duration;
            setDragTime(moveTime);
            const moveAudio = audioRef.current;
            if (moveAudio) {
              moveAudio.currentTime = moveTime;
              setCurrentTime(moveTime);
            }
          };
          
          const handleTouchEnd = (endEvent: TouchEvent) => {
            endEvent.preventDefault();
            setIsDragging(false);
            setDragTime(0);
            document.removeEventListener('touchmove', handleTouchMove);
            document.removeEventListener('touchend', handleTouchEnd);
          };
          
          document.addEventListener('touchmove', handleTouchMove, { passive: false });
          document.addEventListener('touchend', handleTouchEnd, { passive: false });
        }}
        style={{ userSelect: 'none' }}
      >
        <div
          className="h-full bg-[#ff0000] transition-all pointer-events-none"
          style={{ width: `${progressPercent}%` }}
        />
        <div
          className="absolute top-1/2 -translate-y-1/2 w-3 h-3 bg-[#ff0000] rounded-full opacity-0 group-hover:opacity-100 transition-opacity shadow-lg pointer-events-none"
          style={{ left: `calc(${progressPercent}% - 6px)` }}
        />
      </div>

      {/* Player controls */}
      <div className="container mx-auto px-3 sm:px-6 py-3 flex items-center justify-between gap-2 sm:gap-4">
        {/* Song info */}
        <div
          className="flex items-center space-x-2 sm:space-x-3 flex-1 min-w-0 cursor-pointer hover:opacity-80 transition-opacity group"
          onClick={onSongClick}
        >
          {currentSong.image && (
            <img
              src={currentSong.image}
              alt={currentSong.song}
              className="w-10 h-10 sm:w-12 sm:h-12 rounded object-cover flex-shrink-0"
            />
          )}
          <div className="min-w-0 flex-1 hidden sm:block">
            <p className="text-xs sm:text-sm font-medium truncate text-white group-hover:text-[#ff0000] transition-colors">
              {currentSong.song}
            </p>
            <p className="text-xs text-gray-400 truncate">
              {currentSong.artists || currentSong.singers}
            </p>
          </div>
        </div>

        {/* Playback controls */}
        <div className="flex items-center space-x-1 sm:space-x-2 flex-1 justify-center max-w-2xl">
          <button
            onClick={cyclePlaybackMode}
            className={`p-2 hover:bg-white/10 rounded-full transition-colors ${
              playbackMode === 'shuffle' || playbackMode === 'loop' || playbackMode === 'loop-one'
                ? 'text-[#ff0000]'
                : 'text-gray-400'
            }`}
            title={`Playback mode: ${playbackMode}`}
          >
            {playbackMode === 'shuffle' && <FaRandom className="w-4 h-4" />}
            {playbackMode === 'loop' && <FaRedo className="w-4 h-4" />}
            {playbackMode === 'loop-one' && <FaRedoAlt className="w-4 h-4" />}
            {playbackMode === 'sequential' && (
              <FaStepForward className="w-4 h-4" />
            )}
          </button>

          <button
            onClick={previousSong}
            disabled={queueIndex <= 0 && playbackMode === 'sequential'}
            className="p-2 hover:bg-white/10 rounded-full transition-colors disabled:opacity-30 disabled:cursor-not-allowed text-white"
            title="Previous"
          >
            <FaStepBackward className="w-5 h-5" />
          </button>

          <button
            onClick={togglePlay}
            className="p-3 bg-white text-black rounded-full hover:bg-gray-200 transition-colors shadow-lg hover:scale-105 active:scale-95"
            title={isPlaying ? 'Pause' : 'Play'}
          >
            {isPlaying ? (
              <FaPause className="w-5 h-5" />
            ) : (
              <FaPlay className="w-5 h-5 ml-0.5" />
            )}
          </button>

          <button
            onClick={nextSong}
            disabled={
              queueIndex >= queue.length - 1 && playbackMode === 'sequential'
            }
            className="p-2 hover:bg-white/10 rounded-full transition-colors disabled:opacity-30 disabled:cursor-not-allowed text-white"
            title="Next"
          >
            <FaStepForward className="w-5 h-5" />
          </button>

          <div className="text-xs text-gray-400 ml-2 sm:ml-4 min-w-[60px] sm:min-w-[80px] text-right hidden sm:block">
            {formatTime(displayTime)} / {formatTime(duration)}
          </div>
        </div>

        {/* Volume and additional controls */}
        <div className="flex items-center space-x-2 flex-1 justify-end">
          <div
            className="relative"
            onMouseEnter={() => setShowVolumeSlider(true)}
            onMouseLeave={() => setShowVolumeSlider(false)}
            onFocus={() => setShowVolumeSlider(true)}
            onBlur={() => setShowVolumeSlider(false)}
          >
            <button
              className="p-2 hover:bg-white/10 rounded-full transition-colors text-white"
              title="Volume (Use ↑↓ keys)"
            >
              {volume === 0 ? (
                <FaVolumeMute className="w-5 h-5" />
              ) : (
                <FaVolumeUp className="w-5 h-5" />
              )}
            </button>
            {showVolumeSlider && (
              <div className="absolute bottom-full mb-2 right-0 bg-[#282828] p-3 rounded-lg shadow-xl border border-gray-700">
                <input
                  type="range"
                  min="0"
                  max="1"
                  step="0.01"
                  value={volume}
                  onChange={handleVolumeChange}
                  className="w-24 h-1 bg-gray-700 rounded-lg appearance-none cursor-pointer"
                  style={{
                    background: `linear-gradient(to right, #ff0000 0%, #ff0000 ${volume * 100}%, #4b5563 ${volume * 100}%, #4b5563 100%)`,
                  }}
                />
              </div>
            )}
          </div>

        </div>
      </div>
    </div>
  );
}

