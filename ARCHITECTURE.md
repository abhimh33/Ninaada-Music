# 🏗️ Ninaada Music — System Architecture

> Think of this as explaining the app to a friend over coffee ☕

---

## 🎯 The Big Picture

Ninaada is basically a music streaming app with three clients (Flutter, React Native, Web) that all talk to a backend API. The backend fetches music data and serves it to the apps.

Here's how it all fits together:

```
┌─────────────────────────────────────────────────────────────────┐
│                        USER'S DEVICE                            │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ Flutter App   │  │ React Native │  │   Next.js Web App    │  │
│  │ (Android)     │  │ (Android)    │  │   (Browser)          │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬───────────┘  │
│         │                 │                      │              │
│         └─────────────────┼──────────────────────┘              │
│                           │                                     │
│                     HTTPS Requests                              │
│                           │                                     │
└───────────────────────────┼─────────────────────────────────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │   Backend API         │
                │   (FastAPI + Python)  │
                │   Hosted on Render    │
                └───────────┬───────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │   Redis Cache         │
                │   (Upstash)           │
                └───────────────────────┘
```

**In simple words:** You open the app → it asks the backend "give me trending songs" → the backend checks its cache first (super fast), and if it's not cached, it fetches fresh data → sends it back to your phone → you see the songs and tap play.

---

## 📱 Flutter App — The Main Brain

The Flutter app is the most feature-rich client. Here's how it's built:

### Layer Cake Architecture

```
┌─────────────────────────────────────────────────────┐
│                    UI LAYER                          │
│                                                     │
│  Screens    →  What you see on screen               │
│  Widgets    →  Reusable building blocks             │
│                                                     │
├─────────────────────────────────────────────────────┤
│                  STATE LAYER                         │
│                                                     │
│  Providers (Riverpod)  →  Manages app state         │
│  - PlayerProvider      →  What's playing, queue     │
│  - HomeProvider        →  Home feed data            │
│  - LibraryProvider     →  Your downloads & likes    │
│  - NavigationProvider  →  Which screen you're on    │
│                                                     │
├─────────────────────────────────────────────────────┤
│                SERVICE LAYER                         │
│                                                     │
│  Audio Handler     →  Plays the actual music        │
│  Recommendation    →  "What should play next?"      │
│  Download Manager  →  Saves songs offline           │
│  PreBuffer Engine  →  Loads next song in advance    │
│  Behavior Engine   →  Tracks your listening habits  │
│                                                     │
├─────────────────────────────────────────────────────┤
│                  DATA LAYER                          │
│                                                     │
│  API Service       →  Talks to the backend          │
│  Network Manager   →  Handles caching & retries     │
│  Models            →  Song, Album, Artist objects    │
│  Hive (Local DB)   →  Stores data on your phone     │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## 🎧 How Music Plays — The Audio Engine

This is the heart of the app. When you tap a song:

```
You tap "Play" on a song
        │
        ▼
┌─────────────────────┐
│   PlayerNotifier     │  ← Manages play/pause/skip state
│   (Riverpod)         │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────────────────────────┐
│       NinaadaAudioHandler               │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │  just_audio (AudioPlayer)       │    │
│  │                                 │    │
│  │  ConcatenatingAudioSource       │    │  ← Songs are lined up
│  │  [Song1] [Song2] [Song3] ...    │    │    like a playlist.
│  │                                 │    │    When Song1 ends,
│  │  Lazy preparation = only loads  │    │    Song2 starts instantly
│  │  current + next song in memory  │    │    (gapless!)
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │  audio_service (OS Bridge)      │    │  ← Lock screen controls,
│  │  - Notification controls        │    │    notification bar,
│  │  - Audio focus management       │    │    phone call handling
│  │  - Headphone unplug detection   │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │  DSP Pipeline                   │    │  ← The audio effects
│  │  - 5-Band Equalizer             │    │    chain. Hardware
│  │  - Bass Boost                   │    │    accelerated, so
│  │  - Loudness Enhancer            │    │    zero latency.
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
```

**What about gapless playback?**
Instead of loading one song at a time, we use `ConcatenatingAudioSource` — think of it like a playlist buffer. Songs are queued up, and the audio player seamlessly transitions from one to the next. No silence, no loading gap.

**What happens during a phone call?**
The app detects "audio focus" changes. Phone rings → music pauses. Call ends → music resumes. Headphones unplugged → music pauses (so it doesn't blast from your speaker in public 😅).

---

## 🧠 How Recommendations Work

When your queue runs out, the app doesn't just stop — it finds more songs you'll probably like.

```
┌─────────────────────────────────────────────┐
│          Your Taste Profile                  │
│                                              │
│  Stored locally on your phone (Hive DB)      │
│                                              │
│  Tracks:                                     │
│  - Artists you listen to most                │
│  - Genres you prefer                         │
│  - Languages you like                        │
│  - Songs you skip (negative signal!)         │
│  - Songs you play fully (positive signal!)   │
│                                              │
│  All preferences have a 14-day decay         │
│  (what you liked 2 weeks ago matters less)   │
│                                              │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│       Recommendation Engine                  │
│                                              │
│  For each candidate song, calculate score:   │
│                                              │
│  Score = 40% × Artist match                  │
│        + 35% × Genre match                   │
│        + 25% × Language match                │
│        - Penalties for previously skipped     │
│                                              │
│  Then apply Epsilon-Greedy Selection:        │
│                                              │
│  85% of the time → Pick highest scoring      │
│                    songs (safe picks)         │
│                                              │
│  15% of the time → Pick something random     │
│                    (discovery mode!)          │
│                                              │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
          Songs added to your queue
          automatically — infinite music!
```

**Why epsilon-greedy?**
If we always pick what you've listened to before, you'd never discover new stuff. The 15% randomness means you'll occasionally hear something unexpected — and if you like it, the engine learns and gives you more of that.

**Smart adaptation:** If you're skipping a lot (> 40%), the engine increases exploration to 35%. If you're vibing and playing everything fully (> 70%), it reduces to 10% and sticks to what works.

---

## 🌐 How Data Flows — From Backend to Your Screen

```
You open the app → Home Screen loads
        │
        ▼
┌─────────────────────┐
│  HomeProvider        │  "Hey, I need trending songs"
│  (Riverpod)          │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  ApiService          │  Translates to the right API call
└─────────┬───────────┘
          │
          ▼
┌─────────────────────────────────────────────┐
│  NetworkManager (The Smart Gateway)          │
│                                              │
│  Step 1: Check Memory Cache (instant)        │
│          120 most recent responses stored     │
│          in RAM                               │
│          ↓ miss                               │
│  Step 2: Check Disk Cache (fast)             │
│          Hive box 'apiCache' on phone         │
│          ↓ miss                               │
│  Step 3: Deduplicate                         │
│          If same request is already in-flight │
│          → just wait for that one             │
│          ↓ new request                        │
│  Step 4: Concurrency Gate                    │
│          Max 4 requests at once               │
│          (so we don't overwhelm the server)   │
│          ↓                                    │
│  Step 5: Actual Network Call                 │
│          → Backend API → Response             │
│          → Cache the result for next time     │
│                                              │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
          Song objects created from JSON
                   │
                   ▼
          UI rebuilds and shows the songs
```

**Cache Strategy (TTL = Time To Live):**

| What | Cached For | Why |
|------|-----------|-----|
| Trending/Featured | 1 hour | Changes frequently |
| Song details | 24 hours | Song info rarely changes |
| Search results | 1 hour | Could change with new releases |

**Stale-while-revalidate:** For home feed data, if the cache is expired, the app shows the old data immediately (so you're not staring at a loading spinner) and refreshes in the background.

---

## ⬇️ How Offline Downloads Work

```
You long-press a song → Tap "Download"
        │
        ▼
┌─────────────────────────────────────────────┐
│  DownloadManager                             │
│                                              │
│  Download Queue (FIFO):                      │
│  ┌────────┬────────┬────────┐               │
│  │ Song A │ Song B │ Song C │  ← waiting    │
│  └───┬────┴────────┴────────┘               │
│      │                                       │
│      ▼                                       │
│  Active Downloads (max 2 parallel):          │
│  ┌────────┐  ┌────────┐                     │
│  │ Song A │  │ Song B │  ← downloading      │
│  │  47%   │  │  12%   │                     │
│  └────────┘  └────────┘                     │
│                                              │
│  Saved to phone:                             │
│  📁 ninaada_downloads/                       │
│     ├── {songId}.mp3      (audio)            │
│     └── art/{songId}.jpg  (album art)        │
│                                              │
│  Tracked in Hive DB:                         │
│  { songId → DownloadRecord }                 │
│    - status: queued/downloading/done/error   │
│    - localFilePath                           │
│    - progress: 0.0 → 1.0                    │
└─────────────────────────────────────────────┘
```

**Smart playback:** When playing a song, the audio handler checks if it's downloaded locally. If yes, it plays the local file (saves data). If not, it streams from the server.

---

## 🔮 Pre-buffering — Always One Step Ahead

The app doesn't wait for a song to finish before preparing the next one:

```
Currently playing: Song at 80% ──────────────▶│
                                               │
        ┌──────────────────────────────────────┘
        │ 80% threshold hit!
        ▼
┌─────────────────────────────────────┐
│  PrefetchEngine kicks in:           │
│                                     │
│  1. Pre-load next song's album art  │
│  2. Extract color palette           │
│     (for dynamic theming)           │
│  3. Fetch similar songs             │
│     (in case queue runs out)        │
│                                     │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│  PreBufferEngine:                   │
│                                     │
│  Checks: "Are there < 10 songs     │
│  remaining in queue?"               │
│                                     │
│  If yes → Ask RecommendationEngine  │
│  for more songs → Append to queue   │
│                                     │
│  Result: Infinite, seamless music!  │
│                                     │
└─────────────────────────────────────┘
```

---

## 🎨 Dynamic Theming — Colors From Album Art

When a new song plays, the UI changes colors to match the album art:

```
Album art image
      │
      ▼
┌─────────────────────────────┐
│  MediaThemeEngine           │
│  (runs on separate isolate  │
│   so UI doesn't freeze)     │
│                             │
│  1. Extract dominant colors │
│  2. Generate light/dark     │
│     palette variants        │
│  3. Return color map        │
└──────────┬──────────────────┘
           │
           ▼
    PlayerState.dynamicColors updated
           │
           ▼
    All player UI widgets rebuild
    with new gradient backgrounds,
    text colors, slider accents
```

It's like Spotify's dynamic colors but runs on a background thread (Dart isolate) so the UI stays buttery smooth.

---

## 🛡️ Resilience — Things That Keep the App Stable

| Feature | What It Does |
|---------|-------------|
| **Circuit Breaker** | If the server fails 5 times in a row, stop trying for 30 seconds (don't keep hammering a dead server) |
| **Request Deduplication** | If 3 UI widgets all ask for "trending songs" at once, only 1 network request is made |
| **Concurrency Gate** | Max 4 network requests at a time (prevents flooding) |
| **Queue Persistence** | If the app crashes, it remembers exactly where you were — song, position, full queue |
| **ANR Watchdog** | Detects if the app freezes for too long and reports it |
| **Stale-While-Revalidate** | Shows cached data instantly, refreshes in background |
| **Mutex Queue Lock** | Prevents the song queue from getting corrupted when multiple operations happen at once |

---

## 📱 Screen Navigation

```
┌─────────────────────────────────────────────────┐
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │           Active Screen                     │  │
│  │                                             │  │
│  │  Home → Trending, Made For You, New         │  │
│  │  Explore → Browse by genre/mood             │  │
│  │  Library → Downloads, Likes, History        │  │
│  │  Radio → Live streaming stations            │  │
│  │                                             │  │
│  │  Sub-views stack on top:                    │  │
│  │  Album → Artist → Credits (back pops each) │  │
│  │                                             │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │  Mini Player (always visible when playing) │  │
│  │  [Art] Song Name — Artist     advancement ▶ │  │
│  │  tap to expand to full player              │  │
│  └────────────────────────────────────────────┘  │
│                                                  │
│  ┌──────┬──────┬──────┬──────┐                  │
│  │ Home │Explore│Library│Radio │  ← Bottom Nav  │
│  └──────┴──────┴──────┴──────┘                  │
│                                                  │
└─────────────────────────────────────────────────┘
```

---

## 🧪 App Startup — What Happens When You Open Ninaada

```
App launches
    │
    ├── 1. Initialize Flutter engine
    ├── 2. Set up crash handlers (catch any errors)
    ├── 3. Open local databases (Hive boxes)
    ├── 4. Start crash reporter
    ├── 5. Start ANR watchdog
    ├── 6. Restore last queue (so you can resume)
    ├── 7. Initialize download manager
    ├── 8. Start audio service (OS integration)
    ├── 9. Load your taste profile
    ├── 10. Initialize behavior tracking
    ├── 11. Set up network manager + caches
    ├── 12. Warm up GPU shaders (smooth animations)
    │
    └── 🎵 App is ready — show home screen!
```

Everything is initialized in a specific order because some services depend on others. For example, the recommendation engine needs your taste profile loaded first.

---

**Built with ❤️ by Abdulappa M**
