'use client';

import { useState, useEffect, useRef } from 'react';
import {
  FaPlay,
  FaPause,
  FaPlus,
  FaDownload,
  FaShare,
  FaList,
  FaArrowLeft,
  FaHeart,
  FaForward,
} from 'react-icons/fa';
import { Song, getSong, getLyrics, downloadSong } from '../services/api';
import { usePlayerStore } from '../store/playerStore';
import PlaylistSelector from './PlaylistSelector';
import { parseLyrics, getCurrentLyricsLine, LyricsLine } from '../utils/lyricsParser';

interface SongDetailProps {
  song: Song;
  onClose: () => void;
}

export default function SongDetail({ song: initialSong, onClose }: SongDetailProps) {
  const [song, setSong] = useState<Song>(initialSong);
  const [lyrics, setLyrics] = useState<string | null>(null);
  const [lyricsLines, setLyricsLines] = useState<LyricsLine[]>([]);
  const [currentLineIndex, setCurrentLineIndex] = useState(-1);
  const [loadingLyrics, setLoadingLyrics] = useState(false);
  const [showPlaylistSelector, setShowPlaylistSelector] = useState(false);
  const lyricsRef = useRef<HTMLDivElement>(null);
  const {
    currentSong,
    isPlaying,
    currentTime,
    duration,
    setCurrentSong,
    addToQueue,
    playNext,
    togglePlay,
    addSongToPlaylist,
  } = usePlayerStore();

  const isCurrentSong = currentSong?.id === song.id;

  useEffect(() => {
    // Update when song prop changes
    setSong(initialSong);
    setLyrics(null);
    setCurrentLineIndex(-1);
    setLoadingLyrics(true);
    
    // Fetch full song details with lyrics
    const fetchSongDetails = async () => {
      try {
        // Always fetch with lyrics
        const fullSong = await getSong(initialSong.id, true);
        setSong(fullSong);
        
        // Check if lyrics are in the song object
        if (fullSong.lyrics && fullSong.lyrics.trim()) {
          setLyrics(fullSong.lyrics);
        } else {
          // Try to fetch lyrics separately
          try {
            const lyricsResponse = await getLyrics(initialSong.id);
            if (lyricsResponse && lyricsResponse.trim()) {
              setLyrics(lyricsResponse);
            }
          } catch (lyricsError) {
            console.error('Error fetching lyrics:', lyricsError);
            // Try one more time with song URL if available
            if (initialSong.url) {
              try {
                const lyricsResponse = await getLyrics(initialSong.url);
                if (lyricsResponse && lyricsResponse.trim()) {
                  setLyrics(lyricsResponse);
                }
              } catch (e) {
                console.error('Error fetching lyrics from URL:', e);
              }
            }
          }
        }
      } catch (error) {
        console.error('Error fetching song details:', error);
      } finally {
        setLoadingLyrics(false);
      }
    };

    fetchSongDetails();
  }, [initialSong.id]);

  // Parse lyrics when lyrics or duration changes
  useEffect(() => {
    if (lyrics && duration && duration > 0) {
      const parsed = parseLyrics(lyrics, duration);
      setLyricsLines(parsed);
    }
  }, [lyrics, duration]);

  // Sync lyrics with playback
  useEffect(() => {
    if (isCurrentSong && isPlaying && lyricsLines.length > 0 && duration > 0 && currentTime >= 0) {
      const lineIndex = getCurrentLyricsLine(lyricsLines, currentTime);
      if (lineIndex !== currentLineIndex && lineIndex >= 0) {
        setCurrentLineIndex(lineIndex);
        // Scroll to current line with a small delay for smoother animation
        const scrollTimeout = setTimeout(() => {
          if (lyricsRef.current) {
            const lineElement = lyricsRef.current.querySelector(`[data-line-index="${lineIndex}"]`);
            if (lineElement) {
              lineElement.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
          }
        }, 50);
        return () => clearTimeout(scrollTimeout);
      }
    } else if (!isCurrentSong || !isPlaying) {
      // Reset highlight when not playing or not current song
      if (currentLineIndex !== -1) {
        setCurrentLineIndex(-1);
      }
    }
  }, [currentTime, isCurrentSong, isPlaying, lyricsLines, duration, currentLineIndex]);

  const handlePlay = () => {
    if (isCurrentSong) {
      togglePlay();
    } else {
      setCurrentSong(song);
      addToQueue(song);
    }
  };

  const handlePlayNext = () => {
    playNext(song);
  };

  const handleAddToQueue = () => {
    addToQueue(song);
  };

  const handleDownload = () => {
    const downloadUrl = downloadSong(song.id);
    window.open(downloadUrl, '_blank');
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
  };

  return (
    <div className="fixed inset-0 bg-black z-50 overflow-y-auto">
      {/* Header */}
      <div className="sticky top-0 bg-gradient-to-b from-black/80 to-transparent backdrop-blur-sm z-10 pb-2 sm:pb-4">
        <div className="container mx-auto px-4 pt-2 sm:pt-4">
          <button
            onClick={onClose}
            className="mb-2 sm:mb-4 p-2 hover:bg-white/10 rounded-full transition-colors"
          >
            <FaArrowLeft className="text-white text-lg sm:text-xl" />
          </button>
        </div>
      </div>

      {/* Hero Section */}
      <div className="container mx-auto px-4 pb-4 sm:pb-8">
        <div className="flex flex-col md:flex-row gap-4 sm:gap-8 items-start">
          {/* Album Art */}
          <div className="w-full md:w-80 flex-shrink-0">
            {song.image && (
              <img
                src={song.image}
                alt={song.song}
                className="w-full aspect-square object-cover rounded-lg shadow-2xl"
              />
            )}
          </div>

          {/* Song Info */}
          <div className="flex-1 min-w-0">
            <h1 className="text-2xl sm:text-4xl md:text-5xl font-bold text-white mb-2 sm:mb-4">
              {song.song}
            </h1>
            <p className="text-lg sm:text-xl text-gray-300 mb-2">
              {song.artists || song.singers}
            </p>
            {song.album && (
              <p className="text-base sm:text-lg text-gray-400 mb-4 sm:mb-6">{song.album}</p>
            )}

            {/* Action Buttons */}
            <div className="flex flex-wrap items-center gap-2 sm:gap-3 mb-4 sm:mb-8">
              <button
                onClick={handlePlay}
                className="flex items-center gap-2 px-4 sm:px-6 py-2 sm:py-3 bg-red-500 hover:bg-red-600 rounded-full font-semibold transition-colors text-sm sm:text-base"
              >
                {isCurrentSong && isPlaying ? (
                  <>
                    <FaPause /> Pause
                  </>
                ) : (
                  <>
                    <FaPlay /> Play
                  </>
                )}
              </button>
              <button
                onClick={handlePlayNext}
                className="flex items-center gap-2 px-3 sm:px-4 py-2 sm:py-3 bg-white/10 hover:bg-white/20 rounded-full font-medium transition-colors text-xs sm:text-sm"
                title="Play next"
              >
                <FaForward className="text-xs sm:text-sm" /> <span className="hidden sm:inline">Play Next</span>
              </button>
              <button
                onClick={handleAddToQueue}
                className="flex items-center gap-2 px-3 sm:px-4 py-2 sm:py-3 bg-white/10 hover:bg-white/20 rounded-full font-medium transition-colors text-xs sm:text-sm"
              >
                <FaPlus className="text-xs sm:text-sm" /> <span className="hidden sm:inline">Add to Queue</span>
              </button>
              <button
                onClick={() => setShowPlaylistSelector(true)}
                className="flex items-center gap-2 px-3 sm:px-4 py-2 sm:py-3 bg-white/10 hover:bg-white/20 rounded-full font-medium transition-colors text-xs sm:text-sm"
              >
                <FaList className="text-xs sm:text-sm" /> <span className="hidden sm:inline">Add to Playlist</span>
              </button>
              <button
                onClick={handleDownload}
                className="p-3 bg-white/10 hover:bg-white/20 rounded-full transition-colors"
                title="Download"
              >
                <FaDownload />
              </button>
              <button
                onClick={handleShare}
                className="p-3 bg-white/10 hover:bg-white/20 rounded-full transition-colors"
                title="Share"
              >
                <FaShare />
              </button>
            </div>

            {/* Song Details */}
            <div className="space-y-4 text-gray-300">
              {song.year && (
                <div>
                  <span className="text-gray-500">Year: </span>
                  {song.year}
                </div>
              )}
              {song.language && (
                <div>
                  <span className="text-gray-500">Language: </span>
                  {song.language}
                </div>
              )}
              {song.duration && (
                <div>
                  <span className="text-gray-500">Duration: </span>
                  {song.duration}
                </div>
              )}
              {song.copyright_text && (
                <div className="text-sm text-gray-400">
                  {song.copyright_text}
                </div>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Lyrics Section */}
      {(lyrics || loadingLyrics) && (
        <div className="container mx-auto px-4 py-4 sm:py-8 border-t border-gray-800">
          <h2 className="text-xl sm:text-2xl font-bold text-white mb-4 sm:mb-6">Lyrics</h2>
          {loadingLyrics ? (
            <div className="text-gray-400 text-center py-8">Loading lyrics...</div>
          ) : lyrics ? (
            <div 
              ref={lyricsRef}
              className="max-h-[50vh] sm:max-h-[60vh] overflow-y-auto space-y-2 sm:space-y-3 px-2"
            >
              {lyricsLines.length > 0 ? (
                lyricsLines.map((line, index) => (
                  <div
                    key={index}
                    data-line-index={index}
                    className={`text-base sm:text-lg leading-relaxed transition-all duration-300 px-2 py-1 rounded ${
                      index === currentLineIndex && isCurrentSong && isPlaying
                        ? 'text-[#ff0000] font-bold scale-105 bg-red-500/10'
                        : 'text-gray-300'
                    }`}
                  >
                    {line.text}
                  </div>
                ))
              ) : (
                <div className="text-gray-300 whitespace-pre-wrap font-sans text-sm sm:text-base leading-relaxed">
                  {lyrics.split('\n').map((line, index) => (
                    <div key={index} className="py-1">{line || '\u00A0'}</div>
                  ))}
                </div>
              )}
            </div>
          ) : (
            <div className="text-gray-400 text-center py-8">No lyrics available for this song.</div>
          )}
        </div>
      )}

      {/* Playlist Selector Modal */}
      {showPlaylistSelector && (
        <PlaylistSelector
          song={song}
          onSelect={(playlistId) => {
            addSongToPlaylist(playlistId, song);
            setShowPlaylistSelector(false);
          }}
          onClose={() => setShowPlaylistSelector(false)}
        />
      )}
    </div>
  );
}


