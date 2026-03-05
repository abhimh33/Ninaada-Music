import 'package:flutter/material.dart';
import 'package:ninaada_music/data/models.dart';

/// All curated radio station data — matches RN RADIO_CATEGORIES exactly
final List<RadioCategory> radioCategories = [
  RadioCategory(
    id: 'air_karnataka',
    title: 'AIR Karnataka',
    subtitle: 'All India Radio — Official Stations',
    icon: Icons.cell_tower,
    color: const Color(0xFFA0522D),
    stations: [
      RadioStation(id: 'air_bengaluru', name: 'AIR Bengaluru', url: 'https://airhlspush.pc.cdn.bitgravity.com/httppush/hlspbaudio030/hlspbaudio03064kbps.m3u8', emoji: '🏙️'),
      RadioStation(id: 'air_dharwad', name: 'AIR Dharwad', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio150/chunklist.m3u8', emoji: '🎵'),
      RadioStation(id: 'air_mysuru', name: 'AIR Mysuru', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio177/chunklist.m3u8', emoji: '🏰'),
      RadioStation(id: 'air_mangalore', name: 'AIR Mangalore', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio073/chunklist.m3u8', emoji: '🌊'),
      RadioStation(id: 'air_kalaburagi', name: 'AIR Kalaburagi', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio015/chunklist.m3u8', emoji: '📻'),
      RadioStation(id: 'air_raichur', name: 'AIR Raichur', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio198/chunklist.m3u8', emoji: '🌾'),
      RadioStation(id: 'air_hassan', name: 'AIR Hassan', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio172/chunklist.m3u8', emoji: '⛰️'),
      RadioStation(id: 'air_chitradurga', name: 'AIR Chitradurga', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio105/chunklist.m3u8', emoji: '🛡️'),
      RadioStation(id: 'air_ballari', name: 'AIR Ballari', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio142/chunklist.m3u8', emoji: '🪨'),
      RadioStation(id: 'air_bijapur', name: 'AIR Bijapur', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio145/chunklist.m3u8', emoji: '🕍'),
      RadioStation(id: 'air_madikeri', name: 'AIR Madikeri', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio068/chunklist.m3u8', emoji: '🌿'),
      RadioStation(id: 'air_karwar', name: 'AIR Karwar', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio123/chunklist.m3u8', emoji: '🏖️'),
      RadioStation(id: 'air_hospet', name: 'AIR Hospet', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio184/chunklist.m3u8', emoji: '🛕'),
      RadioStation(id: 'air_bhadravati', name: 'AIR Bhadravati', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio211/chunklist.m3u8', emoji: '🏭'),
      RadioStation(id: 'vividh_bharati', name: 'Vividh Bharati', url: 'https://air.pc.cdn.bitgravity.com/air/live/pbaudio001/chunklist.m3u8', emoji: '🎙️'),
      RadioStation(id: 'air_fm_gold', name: 'AIR FM Gold', url: 'https://airhlspush.pc.cdn.bitgravity.com/httppush/hlspbaudio005/hlspbaudio00532kbps.m3u8', emoji: '🥇'),
      RadioStation(id: 'air_ragam', name: 'AIR Ragam', url: 'https://airhlspush.pc.cdn.bitgravity.com/httppush/hlspbaudioragam/hlspbaudioragam64kbps115323444.aac', emoji: '🎼'),
      RadioStation(id: 'rainbow_kannada', name: 'Rainbow Kannada', url: 'https://airhlspush.pc.cdn.bitgravity.com/httppush/hlspbaudio027/hlspbaudio02764kbps.m3u8', emoji: '🌈'),
      RadioStation(id: 'vb_kannada', name: 'VB Kannada', url: 'https://airhlspush.pc.cdn.bitgravity.com/httppush/hlspbaudio026/hlspbaudio02664kbps.m3u8', emoji: '📻'),
      RadioStation(id: 'air_samachara', name: '24×7 Samachara', url: 'https://airhlspush.pc.cdn.bitgravity.com/httppush/hlspbaudio002/hlspbaudio00264kbps.m3u8', emoji: '📰'),
    ],
  ),
  RadioCategory(
    id: 'kannada_internet',
    title: 'Kannada Songs',
    subtitle: 'Kannada Internet Radio Stations',
    icon: Icons.music_note,
    color: const Color(0xFF6B3FA0),
    stations: [
      RadioStation(id: 'nudi_kannada', name: 'Nudi Kannada', url: 'https://stream.zeno.fm/en4wu0vg74zuv', emoji: '📖'),
      RadioStation(id: 'sakath_radio', name: 'Sakath Radio', url: 'https://stream.zeno.fm/fcsk9ryerd0uv', emoji: '🔥'),
      RadioStation(id: 'kannada_geete', name: 'Kannada Geete', url: 'https://server.geetradio.com:8040/radio.mp3', emoji: '🎶'),
      RadioStation(id: 'radio_city_kn', name: 'Radio City Kannada', url: 'https://server.geetradio.com:8040/radio.mp3', emoji: '🏙️'),
      RadioStation(id: 'vv_radio', name: 'VV Radio Kannada', url: 'https://eu1.fastcast4u.com/proxy/vvradio?mp=/;', emoji: '📡'),
      RadioStation(id: 'premaloka', name: 'Kannada City Premaloka', url: 'https://stream-157.zeno.fm/68snnbug8rhvv', emoji: '💕'),
      RadioStation(id: 'sarang', name: 'Sarang Kannada', url: 'https://cast1.asurahosting.com/proxy/deltaast/stream', emoji: '🎻'),
      RadioStation(id: 'madhura_taranga', name: 'Madhura Taranga', url: 'https://stream-166.zeno.fm/v0gde6udfg8uv', emoji: '🌊'),
      RadioStation(id: 'shiva_lahari', name: 'Shiva Lahari', url: 'https://17653.live.streamtheworld.com/SP_R2925215_SC', emoji: '🙏'),
      RadioStation(id: 'nimma_dhwani', name: 'Nimma Dhwani', url: 'https://dx8jkkbno1vwo.cloudfront.net/nammadhwani.m3u8', emoji: '🗣️'),
      RadioStation(id: 'puneet_raj', name: 'Puneet Rajkumar', url: 'https://stream-174.zeno.fm/rketbsyc5uhvv', emoji: '⭐'),
      RadioStation(id: 'suno_kannada', name: 'Suno Kannada', url: 'https://17813.live.streamtheworld.com/RADIO_SUNO_MELODY_S06_SC', emoji: '🎧'),
      RadioStation(id: 'mirchi_kannada', name: 'Mirchi Kannada', url: 'https://stream.zeno.fm/68snnbug8rhvv', emoji: '🌶️'),
      RadioStation(id: 'gulf_kannada', name: 'Gulf Kannada', url: 'https://stream-164.zeno.fm/kgw2tp5p1y5tv', emoji: '🌍'),
      RadioStation(id: 'usa_kannada', name: 'USA Kannada', url: 'https://stream-164.zeno.fm/kc4wg3ent1duv', emoji: '🇺🇸'),
      RadioStation(id: 'fresh_kannada', name: 'Fresh Kannada', url: 'https://worldradio.online/proxy/?q=http://85.25.185.202:8625/stream', emoji: '🍃'),
      RadioStation(id: 'girmit_kannada', name: 'Girmit Kannada', url: 'https://stream.radiojar.com/g6dgm6m6p3hvv', emoji: '🎭'),
      RadioStation(id: 'shalom_kannada', name: 'Shalom Kannada', url: 'https://worldradio.online/proxy/?q=http://rd.shalombeatsradio.com:8090/stream', emoji: '🕊️'),
      RadioStation(id: 'your_beloved', name: 'Your Beloved', url: 'https://player.vvradio.co.in/proxy/vvradio/stream', emoji: '❤️'),
    ],
  ),
  RadioCategory(
    id: 'hindi_stations',
    title: 'Hindi Stations',
    subtitle: 'Bollywood & Hindi Music',
    icon: Icons.library_music,
    color: const Color(0xFF9B3344),
    stations: [
      RadioStation(id: 'radio_mirchi', name: 'Radio Mirchi', url: 'https://eu8.fastcast4u.com/proxy/clyedupq?mp=%2F1', emoji: '🌶️'),
      RadioStation(id: 'red_fm', name: 'Red FM', url: 'https://stream.zeno.fm/9phrkb1e3v8uv', emoji: '🔴'),
      RadioStation(id: 'big_fm_hindi', name: 'Big FM Hindi', url: 'https://stream.zeno.fm/dbstwo3dvhhtv', emoji: '📻'),
      RadioStation(id: '90s_bollywood', name: "90's Bollywood", url: 'https://stream.zeno.fm/u0hrd3xkzhhvv', emoji: '🕺'),
      RadioStation(id: 'lata_mangeshkar', name: 'Lata Mangeshkar', url: 'https://stream.zeno.fm/g95zm67prfhvv', emoji: '👑'),
      RadioStation(id: 'sonu_nigam', name: 'Sonu Nigam', url: 'https://3.mystreaming.net/uber/bollywoodsonunigam/icecast.audio', emoji: '🎤'),
      RadioStation(id: 'shreya_ghoshal', name: 'Shreya Ghoshal', url: 'https://nl4.mystreaming.net/uber/bollywoodshreyaghosal/icecast.audio', emoji: '🎵'),
      RadioStation(id: 'bollywood_love', name: 'Bollywood Love', url: 'https://3.mystreaming.net/uber/bollywoodlove/icecast.audio', emoji: '💕'),
      RadioStation(id: 'exclusive_bw', name: 'Exclusive Bollywood', url: 'https://nl4.mystreaming.net/er/bollywood/icecast.audio', emoji: '💎'),
      RadioStation(id: 'big_fm_retro', name: 'Big FM Retro', url: 'https://stream.zeno.fm/dbstwo3dvhhtv', emoji: '🎞️'),
      RadioStation(id: 'isqu_fm', name: 'Isqu FM', url: 'https://nl4.mystreaming.net/uber/bollywoodlove/icecast.audio', emoji: '🎧'),
      RadioStation(id: 'mirchi_tamil', name: 'Mirchi Tamil', url: 'https://free.rcast.net/72516', emoji: '🌶️'),
      RadioStation(id: 'top_tamil', name: 'Top Tamil', url: 'https://stream.zeno.fm/ex1yqu2gsh1tv', emoji: '🎶'),
      RadioStation(id: 'mirchi_malayalam', name: 'Mirchi Malayalam', url: 'https://stream.aiir.com/dbv0rxpwp6ytv', emoji: '🌴'),
    ],
  ),
  RadioCategory(
    id: 'english_intl',
    title: 'English / International',
    subtitle: 'International Radio Stations',
    icon: Icons.language,
    color: const Color(0xFF3A6B8C),
    stations: [
      RadioStation(id: 'classic_rock', name: 'Classic Rock', url: 'https://streaming.shoutcast.com/classic-rock-vibes-aac', emoji: '🎸'),
      RadioStation(id: 'adult_hits', name: 'Adult Hits', url: 'https://beamadult.streeemer.com/listen/beamadult/radio.aac', emoji: '🎵'),
      RadioStation(id: 'reggaeton', name: '100% Reggaeton', url: 'https://stream.zeno.fm/8wup8yd9dm0uv', emoji: '💃'),
      RadioStation(id: 'heart_uk', name: 'UK Hearts', url: 'https://media-ssl.musicradio.com/HeartUK', emoji: '❤️'),
      RadioStation(id: 'uk_songs', name: 'UK Songs', url: 'https://virgin.live.stream.broadcasting.news/stream', emoji: '🇬🇧'),
      RadioStation(id: 'nethdima', name: 'Nethdima English', url: 'https://stream-160.zeno.fm/fgcaapesa78uv', emoji: '🌐'),
      RadioStation(id: 'bitter_sweet', name: 'Bitter Sweet', url: 'https://beamfm.streeemer.com/listen/beam_fm/radio.aac', emoji: '🍬'),
      RadioStation(id: 'feba_online', name: 'FEBA Online', url: 'https://listen.radioking.com/radio/557210/stream/618317', emoji: '📻'),
      RadioStation(id: 'erre_jackson', name: 'Erre Jackson', url: 'https://stream.zeno.fm/rxx6d9fbvv8uv', emoji: '🎤'),
    ],
  ),
];

/// Quick-play picks (first station from each category + popular ones)
List<RadioStation> get quickPlayStations => [
  radioCategories[0].stations[0],  // AIR Bengaluru
  radioCategories[1].stations[0],  // Nudi Kannada
  radioCategories[2].stations[0],  // Radio Mirchi
  radioCategories[3].stations[0],  // Classic Rock
  radioCategories[1].stations[10], // Puneet Rajkumar
  radioCategories[2].stations[12], // Top Tamil
  radioCategories[2].stations[13], // Mirchi Malayalam
  radioCategories[2].stations[8],  // Exclusive Bollywood
];
