<p align="center">
  <h1 align="center">DREAM</h1>
  <p align="center"><em>Where Dreams Meet Opportunity</em></p>
  <p align="center">Built by dreamers, for dreamers.</p>
</p>

<p align="center">
  <a href="#-about">About</a> •
  <a href="#-the-problem">The Problem</a> •
  <a href="#-features">Features</a> •
  <a href="#%EF%B8%8F-tech-stack">Tech Stack</a> •
  <a href="#-architecture">Architecture</a> •
  <a href="#-getting-started">Getting Started</a> •
  <a href="#-contributing">Contributing</a> •
  <a href="#-roadmap">Roadmap</a> •
  <a href="#-license">License</a>
</p>

---

## 💭 About

Dream is an open-source platform where people share their unfulfilled dreams through short videos and connect with those who can help make them real. A dreamer records a 60-second video answering one question — *"What's your dream?"* — and the platform connects them with developers, designers, mentors, investors, and anyone willing to help.

Inspired by [Simon Squibb's](https://www.youtube.com/@SimonSquibb) "What's Your Dream?" video series. Simon proves every day that a single question can change someone's life. Dream builds the infrastructure for that energy — a place where inspiration stops being a moment you scroll past and becomes the beginning of something real.

---

## 🔥 The Problem

Most people carry a dream they've never told anyone about. There's nowhere to share it.

- **LinkedIn** is for career status, not raw aspiration.
- **Instagram** rewards polished results, not "I have this idea and I don't know where to start."
- **Kickstarter** needs a finished product and a pitch. Most dreams aren't there yet.
- **Startup platforms** are intimidating if your dream isn't a venture-scale business.

A 17-year-old who wants to open a bakery has no platform. A nurse with a health app idea has no way to find a developer. A retired teacher who wants to write children's books has no community backing them.

**Dream is that platform.**

It's for ALL dreams — not just startups, not just tech, not just business. And it connects people not through algorithms optimised for engagement, but through genuine human resonance. You see someone's dream, it moves you, you offer to help.

---

## ✨ Features

### 🎥 Dream Videos
Record a 60–90 second video telling the world what your dream is. Use the in-app camera or upload from your library. Videos are compressed on-device before upload. Add a title, pick a category, set your dream's stage, and tag what help you need.

### 📱 Video Feed
A full-screen, TikTok-style vertical feed of dream videos. Swipe to discover. Each dream shows the dreamer's name, title, category, and stage overlaid on the video. Auto-playing, memory-efficient, infinite scroll.

### 🤝 "I Can Help"
The core interaction. See a dream that resonates? Tap "I Can Help", select what you can offer (coding, design, funding, mentorship, marketing, legal, or other), write a short message, and send. The dreamer gets notified and can accept or decline. It's structured — not a random DM — so every offer is meaningful.

### 💬 Real-Time Chat
When a dreamer accepts your offer, a conversation opens. Messages delivered in real time. Full chat with bubbles, timestamps, read status, and unread badges.

### 🔍 Search & Filter
Find dreams by category, stage, help type needed, or distance from you. Text search across titles and descriptions with debounced input.

### 🗺️ Explore Map
Discover dreams near you on a map. Custom pins for each category. Tap to preview, tap again to dive into the full dream.

### 👤 Profiles
Your avatar, name, bio, roles (Dreamer / Supporter / Backer), and skills. A grid of your dreams. Incoming support offers with accept/decline. Draft dreams saved locally so you can record now and publish later.

---

## 🛠️ Tech Stack

### iOS App

| Technology | Purpose |
|---|---|
| **SwiftUI** | Declarative UI — views, navigation, state management |
| **Combine** | Reactive streams — API responses, debounced search, real-time updates |
| **AVFoundation** | Video recording, playback, and compression |
| **PhotosUI** | Media picker for existing videos and photos |
| **CoreLocation** | User location for proximity-based discovery |
| **MapKit** | Explore map with dream annotations |
| **SwiftData** | Local persistence — draft dreams, offline feed cache |
| **AuthenticationServices** | Sign in with Apple |
| **Swift Concurrency** | async/await, actors for thread-safe video player pool |

### Backend — Supabase (open source)

| Service | Purpose |
|---|---|
| **PostgreSQL** | Database with Row Level Security |
| **PostgREST** | Auto-generated REST API |
| **Auth** | Sign in with Apple token exchange |
| **Storage** | Video files, thumbnails, avatars with CDN |
| **Realtime** | WebSocket for live chat and offer notifications |
| **Edge Functions** | Push notification dispatch via APNs |

---

## 🏗 Architecture

**MVVM (Model-View-ViewModel)** with protocol-oriented services for testability.

```
dream-ios/
├── App/                # Entry point, dependency injection, tab navigation
├── Models/             # User, Dream, SupportOffer, Conversation, ChatMessage
├── Views/              # SwiftUI views by feature
├── ViewModels/         # Business logic, state, service communication
├── Services/           # APIService, AuthService, VideoService, ChatService
├── Components/         # Reusable UI components
├── Utilities/          # Extensions, Keychain helper, constants
└── Resources/          # Assets, localisation
```

### Database

```
users           → profiles, roles, skills, location
dreams          → video, metadata, category, stage, help needed (FK → users)
support_offers  → offer type, message, status (FK → users, dreams)
conversations   → dreamer + supporter link (FK → users, dreams)
chat_messages   → content, read status (FK → conversations, users)
```

### Navigation

```
TabView
├── Discover     → Video feed → Dream detail → Dreamer profile
├── Explore      → Map / List → Dream detail
├── Create       → Camera / Picker → Metadata form → Publish
├── Messages     → Conversations → Chat view
└── Profile      → My dreams, Offers, Settings
```

---

## 🚀 Getting Started

### Prerequisites

- Xcode 16+
- iOS 17+
- [Supabase](https://supabase.com) project (free tier)
- Apple Developer account

### Setup

```bash
git clone https://github.com/dreambydreamers/dream.git
cd dream/dream-ios
```

Create `Config.xcconfig` (gitignored):

```
SUPABASE_URL = https://your-project.supabase.co
SUPABASE_ANON_KEY = your-anon-key
```

Run the database migrations from `dream-backend/migrations/` in your Supabase SQL editor.

Create three storage buckets:

| Bucket | Access | Max Size |
|---|---|---|
| `dream-videos` | Public read, authenticated write | 100MB |
| `thumbnails` | Public read, authenticated write | 5MB |
| `avatars` | Public read, owner write | 5MB |

Open `Dream.xcodeproj` and run (⌘R).

---

## 🤝 Contributing

Dream is open source because the app itself is a dream — and dreams are built together.

### How You Can Help

- **Code** — SwiftUI frontend, Supabase Edge Functions, infrastructure
- **Design** — UI/UX, icons, animations, Figma files
- **Translation** — Make Dream accessible in more languages
- **Docs** — Guides, tutorials, setup improvements
- **Testing** — Bug reports, test cases, device testing
- **Community** — Spread the word, onboard users, give feedback

### Workflow

1. Fork the repo
2. Create a branch (`git checkout -b feature/your-feature`)
3. Make your changes
4. Commit clearly (`git commit -m "Add: video compression progress bar"`)
5. Push and open a Pull Request

Look for **`good first issue`** labels if you're new. Read our [Code of Conduct](CODE_OF_CONDUCT.md) and [Contributing Guide](CONTRIBUTING.md) before starting.

### The Builders Wall

Every contributor gets their name on the **Builders Wall** inside the app — a dedicated section showing everyone who helped build Dream. Not just a credits page. Proof that this thing was built by real people who believed in it.

---

## 🗺 Roadmap

### Phase 1 — MVP
- [ ] Sign in with Apple
- [ ] Dream video recording, compression, upload
- [ ] TikTok-style video feed
- [ ] Filtering and search
- [ ] "I Can Help" flow
- [ ] Real-time chat
- [ ] User profiles
- [ ] Explore map

### Phase 2 — Community
- [ ] Dream Journey (milestone progress updates)
- [ ] Smarter dream-supporter matching
- [ ] Accessibility (VoiceOver, Dynamic Type)
- [ ] Localisation (English, Spanish, Croatian)
- [ ] Android app

### Phase 3 — Growth
- [ ] Micro-backing (small financial contributions)
- [ ] Sponsored dream challenges
- [ ] Companion web app
- [ ] Simon's Corner (curated editorial section)

---

## 📄 License

Open source under [AGPL-3.0](LICENSE). Free to use, modify, and distribute. If you run a modified version as a service, your changes must be open source too.

---

<p align="center">
  <strong>Everyone has a dream worth pursuing. Let's build the place where they come true.</strong>
</p>

<p align="center">
  <a href="https://github.com/dreambydreamers/dream/issues">Report a Bug</a> •
  <a href="https://github.com/dreambydreamers/dream/issues">Request a Feature</a> •
  <a href="https://github.com/dreambydreamers/dream/discussions">Discuss</a>
</p>
