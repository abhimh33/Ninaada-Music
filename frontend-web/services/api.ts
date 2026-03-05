import axios from 'axios';

const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000' ;

export interface Song {
  id: string;
  song: string;
  album: string;
  artists: string;
  singers: string;
  image: string;
  media_url?: string;
  lyrics?: string;
  duration?: string;
  year?: string;
  language?: string;
  copyright_text?: string;
  [key: string]: any;
}

export interface Album {
  id: string;
  name: string;
  image: string;
  primary_artists: string;
  songs: Song[];
  [key: string]: any;
}

export interface Playlist {
  id: string;
  listname: string;
  firstname: string;
  image: string;
  songs: Song[];
  [key: string]: any;
}

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

export const searchSongs = async (
  query: string,
  includeLyrics: boolean = false,
  fullData: boolean = true
): Promise<Song[]> => {
  const response = await api.get('/song/', {
    params: {
      query,
      lyrics: includeLyrics,
      songdata: fullData,
    },
  });
  return response.data;
};

export const getSong = async (
  songId: string,
  includeLyrics: boolean = true
): Promise<Song> => {
  const response = await api.get('/song/get', {
    params: {
      song_id: songId,
      lyrics: includeLyrics,
    },
  });
  return response.data;
};

export const getAlbum = async (
  query: string,
  includeLyrics: boolean = false
): Promise<Album> => {
  const response = await api.get('/album/', {
    params: {
      query,
      lyrics: includeLyrics,
    },
  });
  return response.data;
};

export const getPlaylist = async (
  query: string,
  includeLyrics: boolean = false
): Promise<Playlist> => {
  const response = await api.get('/playlist/', {
    params: {
      query,
      lyrics: includeLyrics,
    },
  });
  return response.data;
};

export const getLyrics = async (query: string): Promise<string> => {
  const response = await api.get('/lyrics/', {
    params: { query },
  });
  // Handle both direct string response and object with lyrics property
  if (typeof response.data === 'string') {
    return response.data;
  } else if (response.data?.lyrics) {
    return response.data.lyrics;
  }
  return '';
};

export const downloadSong = (songId: string): string => {
  return `${API_BASE_URL}/song/download?song_id=${songId}`;
};

export default api;


