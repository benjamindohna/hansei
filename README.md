# Hansei

**Voice notes on your own mistakes, recorded mid-game on your Apple Watch and turned into a personal coaching dossier.**

*Hansei* (反省) is the Japanese practice of honest self-reflection. During a football match you double-tap the watch and say what just went wrong ("lost the ball because I didn't scan before receiving"). After the game, every note is transcribed, and an LLM coach looks for recurring patterns across games. It quotes your own words as evidence and gives you one focus for the next session.

I built it for myself. I use it in real 11-a-side games, and a second player uses it with a Watch Ultra.

<!-- TODO: Screenshot/GIF Watch + Web nebeneinander -->

## How it works

```
Apple Watch (watchOS)          iPhone (iOS)                 Web (Next.js on Vercel)
─────────────────────          ────────────                 ───────────────────────
HKWorkoutSession keeps   ──►   WatchConnectivity     ──►    /api/upload
the app alive all game         file transfer                  └─ Gemini 2.5 Flash transcription
Double-tap → record            per-game list + playback       └─ stored in Vercel Blob
Outbox + retry until           auto-upload with retry       After the game:
transfer is confirmed                                         └─ Claude analyses all notes
HR, kcal, distance → Health                                      → per-game analysis
                                                                 → long-term coach dossier
```

## Design decisions

- **Reliability beats seamlessness.** A missed recording can't be recovered, so the audio session stays active for the whole game and the next recorder is always pre-prepared, which means zero start latency. Files leave the watch's outbox only after the transfer is confirmed, and in-flight recordings survive app crashes.
- **Double-tap instead of gestures.** A "raise watch to mouth" motion trigger was prototyped and rejected because it wasn't reliable enough on the pitch. Auto-stop on silence was rejected too, since a football pitch is never silent. Recording runs in 60 s segments with a haptic warning before the cap.
- **No database.** All metadata lives in the filename (`rec_<sessionEpoch>_<recEpoch>.m4a`). Blob storage is the single source of truth for audio, transcripts, analyses and the coach's memory.
- **No generic tips.** The coach prompt requires evidence (verbatim quotes from your notes) and causal chains. It returns at most 2–3 problem areas, one focus and 2–3 drills, and says so honestly when there isn't enough data yet. Analysis runs automatically when a game is complete. You never press a button.
- **Multilingual.** The UI is in DE, EN and ES. Transcription keeps the original language, and the coach answers in the language you spoke.

## Stack

| | |
|---|---|
| Watch | SwiftUI, HealthKit (`HKWorkoutSession`, `HKLiveWorkoutBuilder`), AVAudioRecorder (AAC 16 kHz mono) |
| iPhone | SwiftUI, WatchConnectivity, background upload with idempotent retries |
| Web | Next.js 15, Vercel Blob, Gemini 2.5 Flash (speech-to-text), Claude (analysis, structured JSON output) |
| Build | XcodeGen (`project.yml`), Swift 5.10 |

## Run it yourself

```sh
# iOS + watchOS
brew install xcodegen
cp FehlermapiOS/Secrets.swift.example FehlermapiOS/Secrets.swift   # set your upload token
xcodegen generate && open Fehlermap.xcodeproj
# choose your signing team for both targets, install the iPhone app (watch app comes along)

# Web
cd web && npm install
# env: UPLOAD_TOKEN, BLOB_READ_WRITE_TOKEN, GEMINI_API_KEY, ANTHROPIC_API_KEY
npm run dev
```

The project started as "Fehlermap" (German for "mistake map"). The target folders still carry that name.
