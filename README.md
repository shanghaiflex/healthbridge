# BoW — bodywithoutorgans.cc on the phone (iOS 17+)

Private SwiftUI app, two jobs:

1. **Лекции** — keeps the two lectures the site says are next (`GET /api/lectures/preload`: what is being
   listened to, then the queue) downloaded on the phone, plays them with the screen locked (lock-screen controls,
   ±15/30 s, speed), and pushes the position back (`PATCH /api/lecture/<id>`) every 15 s and on every pause.
   A finished lecture is marked `listened`, its file deleted, and the next one downloaded. Downloads run in a
   background `URLSession` (they survive the app being suspended or killed by iOS) and resume after a dropped
   connection; Wi-Fi only by default (Settings).
2. **Здоровье** — the old Health Bridge: HealthKit → `POST /v1/ingest/health/<workouts|sleep|metrics>` with a
   bearer token, anchored queries, on-disk retry queue, background delivery via `HKObserverQuery`
   + `BGTaskScheduler`. Every request carries `X-Trigger` (foreground / healthkit:<type> / bg-refresh / manual)
   so the server log shows what woke the app. The «Здоровье» tab has a journal of launches, syncs and downloads.

## Build & install (no App Store, personal team)
```
xcodebuild -project BoW.xcodeproj -scheme BoW -destination 'id=<device udid>' -derivedDataPath build/device -allowProvisioningUpdates build
xcrun devicectl device install app --device <udid> build/device/Build/Products/Debug-iphoneos/BoW.app
xcrun devicectl device process launch --device <udid> cc.bodywithoutorgans.bow
```
Bundle id `cc.bodywithoutorgans.bow`, team = personal (free) → the profile lives 7 days, then the app stops
launching and must be reinstalled. The only real fix is the paid Apple Developer Program (1-year profiles,
TestFlight over the air).

Icon: `swift tools/icon.swift BoW/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

## Files
- `BoWApp.swift` — entry; the AppDelegate does everything a background launch needs (BG tasks, HealthKit observers, audio session, background-session reconnect).
- `LectureStore` / `DownloadManager` / `PlayerEngine` — the lectures side. `LecturesView` is the screen, `PreviewData` feeds the `#Preview`s.
- `SyncCoordinator` / `HealthKitManager` / `AnchorStore` / `QueueManager` / `NetworkClient` — the health side.
- `ActivityLog` — persisted journal shown in the app.
- `openapi.yaml` — the ingest API.
