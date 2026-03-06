# 🎵 Ninaada Music

**Resonating Beyond Listening**

A premium, high-performance Indian music streaming application available across multiple platforms — Flutter (Android), React Native (Android), and Next.js (Web).

## 📱 Platforms

| Platform | Directory | Tech Stack |
|----------|-----------|------------|
| **Flutter App** | `ninaada_flutter/` | Flutter, Dart, Riverpod, just_audio |
| **React Native App** | `mobile-app/` | React Native, react-native-track-player |
| **Web App** | `frontend-web/` | Next.js, React, TypeScript, Tailwind CSS |

## 📸 Screenshots

<details>
<summary><strong>🚀 Onboarding</strong></summary>
<br>
<p align="center">
  <img src="screenshots/01_welcome.png" width="250" alt="Welcome Screen"/>
  &nbsp;&nbsp;
  <img src="screenshots/02_pick_artists.png" width="250" alt="Pick Artists"/>
</p>
</details>

<details>
<summary><strong>🏠 Home Screen</strong></summary>
<br>
<p align="center">
  <img src="screenshots/03_home_recently_played.png" width="250" alt="Recently Played & Quick Picks"/>
  &nbsp;&nbsp;
  <img src="screenshots/04_home_made_for_you.png" width="250" alt="Made For You & Daily Mix"/>
  &nbsp;&nbsp;
  <img src="screenshots/05_home_discover_weekly.png" width="250" alt="Discover Weekly & Top Picks"/>
</p>
<p align="center">
  <img src="screenshots/06_home_biggest_hits.png" width="250" alt="Biggest Hits & Most Played"/>
  &nbsp;&nbsp;
  <img src="screenshots/07_home_new_releases.png" width="250" alt="New Releases & Featured Playlists"/>
</p>
</details>

<details>
<summary><strong>🔍 Search</strong></summary>
<br>
<p align="center">
  <img src="screenshots/08_search_songs.png" width="250" alt="Search Songs"/>
  &nbsp;&nbsp;
  <img src="screenshots/09_search_albums.png" width="250" alt="Search Albums"/>
  &nbsp;&nbsp;
  <img src="screenshots/10_search_artists.png" width="250" alt="Search Artists"/>
</p>
</details>

<details>
<summary><strong>📚 Library, Radio & Explore</strong></summary>
<br>
<p align="center">
  <img src="screenshots/11_library.png" width="250" alt="Library"/>
  &nbsp;&nbsp;
  <img src="screenshots/12_radio.png" width="250" alt="Radio"/>
  &nbsp;&nbsp;
  <img src="screenshots/13_explore.png" width="250" alt="Explore"/>
</p>
</details>

<details>
<summary><strong>🎧 Now Playing & Controls</strong></summary>
<br>
<p align="center">
  <img src="screenshots/14_player.png" width="250" alt="Player"/>
  &nbsp;&nbsp;
  <img src="screenshots/15_sleep_timer.png" width="250" alt="Sleep Timer"/>
  &nbsp;&nbsp;
  <img src="screenshots/16_equalizer.png" width="250" alt="Equalizer"/>
</p>
<p align="center">
  <img src="screenshots/17_queue.png" width="250" alt="Queue"/>
  &nbsp;&nbsp;
  <img src="screenshots/18_song_options.png" width="250" alt="Song Options"/>
  &nbsp;&nbsp;
  <img src="screenshots/19_album_playlist.png" width="250" alt="Album Playlist"/>
</p>
</details>

## ✨ Key Features

- 🎧 **Gapless Playback** — Seamless track-to-track transitions with pre-buffering
- 🎚️ **5-Band Equalizer** — Hardware-accelerated DSP with Bass Boost and Loudness Enhancer
- 📻 **Live Radio** — 30+ curated stations across Indian languages
- 🧠 **Smart Recommendations** — Behavior-aware engine that learns your taste
- 📝 **Synced Lyrics** — Binary search-based LRC parser with sub-millisecond accuracy
- ⬇️ **Offline Mode** — Multi-threaded download manager with flexible bitrate control
- 😴 **Sleep Timer & Alarm** — Schedule playback to stop or wake you up
- 🎤 **Voice Commands** — Hands-free music control
- 🎨 **Dynamic Theming** — UI colors adapt to album artwork in real-time

## 🚀 Getting Started

### Flutter App
```bash
cd ninaada_flutter
flutter pub get
flutter run
```

### React Native App
```bash
cd mobile-app
npm install
npx react-native run-android
```

### Web App
```bash
cd frontend-web
npm install
npm run dev
```

## 🏗️ Architecture

> 📖 For a detailed system architecture breakdown with diagrams, see [ARCHITECTURE.md](ARCHITECTURE.md)

The Flutter app follows a **Unidirectional Data Flow** pattern powered by Riverpod, with a layered engine stack:

- **Audio Handler** — Bridges `just_audio` with `audio_service` for background playback
- **Recommendation Engine** — Intelligent song ranking based on user taste profile
- **PreBuffer Engine** — Anticipatory audio loading at 80% track completion
- **MediaTheme Engine** — Real-time glassmorphic UI color shifting from artwork

## 👤 Author

**Abdulappa M**

## 📄 License

This project is licensed under the GPL-3.0 License — see the [LICENSE](LICENSE) file for details.

---

## ⚠️ Disclaimer

This project is for **educational and personal use only**. It is not affiliated with, endorsed by, or associated with any official music streaming service or company. All product names, trademarks, and registered trademarks are the property of their respective owners. The music content accessed through this application is streamed via third-party services and is not hosted or distributed by this project.
