# 🎵 Ninaada Music

**Resonating Beyond Listening**

Ninaada is a premium, high-performance Indian music streaming application built with Flutter. It features a sophisticated audio engine, AI-powered recommendations, live radio, and deep system integration for a professional listening experience.

---

## ✨ Detailed Features

### 🎧 Ninaada 2.0 Core Playback Engine

Ninaada isn't just a player; it's a sophisticated audio workstation designed for the most demanding listeners.

- **Gapless Audio Engine**: Built on a `ConcatenatingAudioSource` pipeline, Ninaada eliminates silence between tracks, pre-loading the next track's buffer while you're still listening to the current one.
- **DSP Audio Pipeline (Phase 11)**: Includes a hardware-accelerated **5-band Equalizer**, **Bass Boost (Virtualizer)**, and a **Loudness Enhancer**. These are piped directly through the hardware audio effects engine for zero-latency processing.
- **Smart Pre-buffering**: The engine proactively monitors playback; when a song hits 80%, it triggers the `PreBufferEngine` to download the upcoming track into a temporary high-speed cache.
- **Hybrid Source Switching**: Automatically detects if a song is available locally. If it is, the app hot-swaps to the offline file mid-playback to save data, without any skip or jitter.
- **Resilient Audio Focus**: Handles system interruptions with grace. The app ducks volume to 20% for navigation prompts and pauses intelligently during incoming calls, resuming automatically when clear.

### 📻 Next-Gen Live Radio Experience

- **Curated Multi-Language Stations**: 30+ stations covering Bollywood, regional Indian languages (Kannada, Telugu, Tamil, etc.), Devotional, and Lofi.
- **Precision Now Playing Banner**: A 4.4px precision-engineered UI that features a real-time reactive waveform animation.
- **Intelligent Controls**: Integrated EQ and Sleep Timer directly in the mini-player for one-tap adjustments.
- **Broadcast Stability**: Uses a robust retry logic that attempts to re-establish broken biological streams up to twice before notifying the user.

### 🧠 Intelligent Personalization

- **Behavior-Aware Engine**: Ninaada tracks user engagement (skips, full listens, likes) to build a locally stored **Taste Profile**.
- **Algorithmic Autoplay**: When your queue ends, the `RecommendationEngine` analyzes your Taste Profile to curate an infinite stream of similar songs.
- **High-Performance Lyrics**: A custom-built LRC parser with a binary search synchronization engine ensures lyrics scroll with sub-millisecond accuracy to the audio.

### ⬇️ Offline Performance & Persistence

- **Multi-Threaded Download Manager**: Downloads songs in parallel streams to maximize your connection speed.
- **Flexible Storage**: Selective bitrate control allows you to choose between **Low**, **Medium**, and **High** quality to balance audio fidelity and storage space.
- **Black-Box Persistence**: The app saves your exact position every few seconds, allowing you to cold-boot the app and resume playback at the exact millisecond you left off.

---

## 🏗️ Architecture

Ninaada follows a strict **Unidirectional Data Flow** pattern powered by **Riverpod**.

### The Engine Stack:
- **Audio Handler**: Bridges `just_audio` with `audio_service` for background playback.
- **Recommendation Engine**: Intelligent ranking of songs based on TasteProfile.
- **PreBuffer Engine**: Anticipatory audio loading.
- **MediaTheme Engine**: Real-time UI color shifting based on artwork to create an immersive "glassmorphic" experience.

> [!TIP]
> For a deep-dive into the internals, see the [Architecture Overview](.gemini/antigravity/brain/7b745012-89c6-4af3-b5b5-7e2f4a0db6bb/architecture_overview.md).

---

## 🚀 Getting Started

### Prerequisites
- **Flutter SDK** ≥ 3.11.0
- **Android Device** (API 21+)
- **Ninaada API Backend**

### Installation
```bash
# 1. Clone the repository
git clone https://github.com/abhimh33/music-app.git

# 2. Install dependencies
flutter pub get

# 3. Build & Run
flutter run
```

---

## 🛠️ Tech Stack

- **Framework**: Flutter (Dart)
- **State**: Riverpod 2.x
- **Audio**: just_audio + audio_service
- **Database**: Hive (NoSQL)
- **Networking**: Dio

---

## 📂 Project Structure
- `lib/core` — Themes, helpers, and global constants.
- `lib/services` — Audio handling, download manager, and AI engines.
- `lib/providers` — Reactive state orchestration.
- `lib/screens` — All primary UI views.
- `lib/widgets` — Reusable components (Lyrics, Mini-player, etc).

---

## 👨‍💻 Author

**Abdulappa M**

Engineered with ❤️ | [GitHub](https://github.com/abhimh33) | [LinkedIn](https://www.linkedin.com/in/abdulappa-m-4262a328a)

---

## 📄 License
This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.
