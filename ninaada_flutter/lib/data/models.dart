import 'package:flutter/material.dart';
import 'package:ninaada_music/core/helpers.dart';

// ========== SONG MODEL ==========
// Mirrors the RN `norm()` normalizer function

class Song {
  final String id;
  final String name;
  final String artist;
  final String image;
  final int duration;
  final String mediaUrl;
  final String album;
  final String year;
  final String language;
  final String label;
  final bool explicit;
  final String? localUri;
  final String? downloadedAt;
  final int? playCount;
  final String? primaryArtists;
  final String? subtitle;

  const Song({
    required this.id,
    required this.name,
    required this.artist,
    required this.image,
    this.duration = 240,
    this.mediaUrl = '',
    this.album = '',
    this.year = '',
    this.language = '',
    this.label = '',
    this.explicit = false,
    this.localUri,
    this.downloadedAt,
    this.playCount,
    this.primaryArtists,
    this.subtitle,
  });

  /// Normalize from API JSON (mirrors RN norm function)
  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: (json['id'] ?? '').toString(),
      name: (json['song'] ?? json['name'] ?? json['title'] ?? 'Unknown').toString(),
      artist: (json['primary_artists'] ?? json['artist'] ?? json['subtitle'] ?? 'Unknown Artist').toString(),
      image: safeImageUrl(json['image']?.toString()),
      duration: int.tryParse((json['duration'] ?? '240').toString()) ?? 240,
      mediaUrl: (json['media_url'] ?? '').toString(),
      album: (json['album'] ?? '').toString(),
      year: (json['year'] ?? '').toString(),
      language: (json['language'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      explicit: json['explicit_content'] == 1 || json['explicit_content'] == true,
      localUri: json['localUri']?.toString(),
      downloadedAt: json['downloadedAt']?.toString(),
      primaryArtists: json['primary_artists']?.toString(),
      subtitle: json['subtitle']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'artist': artist,
      'image': image,
      'duration': duration,
      'media_url': mediaUrl,
      'album': album,
      'year': year,
      'language': language,
      'label': label,
      'explicit_content': explicit ? 1 : 0,
      'localUri': localUri,
      'downloadedAt': downloadedAt,
      'primary_artists': primaryArtists,
      'subtitle': subtitle,
    };
  }

  Song copyWith({
    String? id,
    String? name,
    String? artist,
    String? image,
    int? duration,
    String? mediaUrl,
    String? album,
    String? year,
    String? language,
    String? label,
    bool? explicit,
    String? localUri,
    String? downloadedAt,
    int? playCount,
  }) {
    return Song(
      id: id ?? this.id,
      name: name ?? this.name,
      artist: artist ?? this.artist,
      image: image ?? this.image,
      duration: duration ?? this.duration,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      album: album ?? this.album,
      year: year ?? this.year,
      language: language ?? this.language,
      label: label ?? this.label,
      explicit: explicit ?? this.explicit,
      localUri: localUri ?? this.localUri,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      playCount: playCount ?? this.playCount,
      primaryArtists: primaryArtists,
      subtitle: subtitle,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Song && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

// ========== BROWSE ITEM (Album/Playlist/Trending) ==========
class BrowseItem {
  final String id;
  final String name;
  final String? subtitle;
  final String image;
  final String? type;
  final String? primaryArtists;
  final int? count;
  final String? year;
  final List<Song>? songs;

  const BrowseItem({
    required this.id,
    required this.name,
    this.subtitle,
    required this.image,
    this.type,
    this.primaryArtists,
    this.count,
    this.year,
    this.songs,
  });

  factory BrowseItem.fromJson(Map<String, dynamic> json) {
    List<Song>? songs;
    if (json['songs'] != null && json['songs'] is List) {
      songs = (json['songs'] as List).map((s) => Song.fromJson(s as Map<String, dynamic>)).toList();
    }
    return BrowseItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? json['title'] ?? json['listname'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? json['primary_artists'] ?? json['firstname'] ?? '').toString(),
      image: safeImageUrl(json['image']?.toString()),
      type: json['type']?.toString(),
      primaryArtists: json['primary_artists']?.toString(),
      count: json['count'] != null ? int.tryParse(json['count'].toString()) : null,
      year: json['year']?.toString(),
      songs: songs,
    );
  }
}

// ========== ARTIST MODEL ==========
class ArtistDetail {
  final String id;
  final String name;
  final String image;
  final String? followerCount;
  final String? bio;
  final List<Song> topSongs;
  final List<BrowseItem> topAlbums;
  final List<ArtistBrief> similarArtists;

  const ArtistDetail({
    required this.id,
    required this.name,
    required this.image,
    this.followerCount,
    this.bio,
    this.topSongs = const [],
    this.topAlbums = const [],
    this.similarArtists = const [],
  });

  factory ArtistDetail.fromJson(Map<String, dynamic> json) {
    return ArtistDetail(
      id: (json['id'] ?? json['artistId'] ?? '').toString(),
      name: (json['name'] ?? 'Artist').toString(),
      image: safeImageUrl(json['image']?.toString()),
      followerCount: json['follower_count']?.toString(),
      bio: json['bio']?.toString(),
      topSongs: (json['topSongs'] ?? json['songs'] ?? [])
          .map<Song>((s) => Song.fromJson(s as Map<String, dynamic>))
          .toList(),
      topAlbums: (json['topAlbums'] ?? json['albums'] ?? [])
          .map<BrowseItem>((a) => BrowseItem.fromJson(a as Map<String, dynamic>))
          .toList(),
      similarArtists: (json['similarArtists'] ?? [])
          .map<ArtistBrief>((a) => ArtistBrief.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ArtistBrief {
  final String id;
  final String name;
  final String image;

  const ArtistBrief({required this.id, required this.name, required this.image});

  factory ArtistBrief.fromJson(Map<String, dynamic> json) {
    return ArtistBrief(
      id: (json['id'] ?? json['artistId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      image: safeImageUrl(json['image']?.toString()),
    );
  }
}

// ========== PLAYLIST MODEL ==========
class PlaylistModel {
  final String id;
  final String name;
  final List<Song> songs;

  const PlaylistModel({required this.id, required this.name, this.songs = const []});

  factory PlaylistModel.fromJson(Map<String, dynamic> json) {
    return PlaylistModel(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      songs: json['songs'] != null
          ? (json['songs'] as List).map((s) => Song.fromJson(s as Map<String, dynamic>)).toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'songs': songs.map((s) => s.toJson()).toList(),
  };

  PlaylistModel copyWith({String? name, List<Song>? songs}) {
    return PlaylistModel(
      id: id,
      name: name ?? this.name,
      songs: songs ?? this.songs,
    );
  }
}

// ========== RADIO STATION MODEL ==========
class RadioStation {
  final String id;
  final String name;
  final String url;
  final String emoji;

  const RadioStation({
    required this.id,
    required this.name,
    required this.url,
    required this.emoji,
  });
}

class RadioCategory {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<RadioStation> stations;

  const RadioCategory({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.stations,
  });
}

// ========== PLAY COUNT MODEL ==========
class PlayCount {
  final int count;
  final Song song;

  const PlayCount({required this.count, required this.song});

  factory PlayCount.fromJson(Map<String, dynamic> json) {
    return PlayCount(
      count: json['count'] ?? 0,
      song: Song.fromJson(json['song'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
    'count': count,
    'song': song.toJson(),
  };
}
